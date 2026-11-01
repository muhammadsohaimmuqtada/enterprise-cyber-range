#!/bin/bash
# fw entrypoint: make sure nftables is present, load the range ruleset, and
# stay in the foreground. The compose service already sets
# net.ipv4.ip_forward=1 via sysctls and grants CAP_NET_ADMIN.
set -uo pipefail

# Belt and braces: nftables normally ships with the image; install on demand
# if the image was built from a stripped base.
if ! command -v nft >/dev/null 2>&1; then
  echo "fw: nftables missing, installing at boot"
  apt-get update -qq && apt-get install -y -qq --no-install-recommends nftables
fi

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 \
  || echo "fw: could not set ip_forward via sysctl (compose sysctls should have done it)"

loaded=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if nft -f /fw/nftables.conf 2>/tmp/nft.err; then
    loaded=1
    break
  fi
  echo "fw: ruleset load attempt $i failed: $(tail -2 /tmp/nft.err)"
  sleep 3
done
if [ "$loaded" != "1" ]; then
  echo "fw: ruleset failed to load after 10 attempts; refusing to route without policy"
  exit 1
fi
echo "fw: nftables ruleset loaded (perimeter + east-west + egress)"

# Best-effort kernel-log mirror: nftables 'log' statements land in the kernel
# ring buffer. Where this container can read it (CAP_SYSLOG or unrestricted
# dmesg) we copy the deny lines to stdout (docker logs fw) and to
# /var/log/fw-kernel.log. Where it cannot, the nft counters remain the
# deterministic signal for the blue team (make status / nft -a list chain ...).
(
  dmesg -w 2>/dev/null \
    | grep --line-buffered -E 'FW-(EDGE|EGRESS|LATERAL|INPUT)-DENY' \
    | tee -a /var/log/fw-kernel.log
) >/dev/null 2>&1 &
if [ $? -ne 0 ]; then
  echo "fw: kernel-log mirror could not start (counters still available)"
fi

echo "fw: ready. Blue team: 'docker exec fw nft -a list chain inet filter forward'"
exec tail -f /dev/null
