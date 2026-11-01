#!/bin/bash
# ws entrypoint (shared by ws1 and ws2): join LAB.LOCAL against dc01 at first
# boot, with retries, and fail SOFT: if the join cannot be completed the
# container stays up and reports unhealthy so the rest of the range still
# comes up. See ws/README.md for the failure semantics.
set -uo pipefail

DC_IP=10.10.30.10
DC_ADMIN_PASS="${DC_ADMIN_PASS:-Lab-Admin#2026!}"
STATE_DIR=/var/lib/range
mkdir -p "$STATE_DIR"

ip route replace default via 10.10.20.1 2>/dev/null \
  || echo "ws: could not pin default route via fw (continuing)"

# Use the domain controller for LAB.LOCAL: Docker's embedded DNS does not know
# AD zones. Queries to 10.10.30.10 cross the fw on the users->servers DNS
# allowlist (FW-13/FW-14 in fw/nftables.conf).
printf 'nameserver %s\nsearch lab.local\n' "$DC_IP" > /etc/resolv.conf
grep -q 'dc01.lab.local' /etc/hosts || echo "$DC_IP dc01.lab.local dc01" >> /etc/hosts

# realmd rides the D-Bus system bus; no systemd here, so start dbus manually.
mkdir -p /run/dbus
dbus-daemon --system --fork || echo "ws: dbus already running or failed to start"

# Wait for the KDC on dc01:88 before touching realmd.
kdc_ok=""
for i in $(seq 1 60); do
  if timeout 2 bash -c "</dev/tcp/$DC_IP/88" 2>/dev/null; then
    kdc_ok=1
    break
  fi
  sleep 2
done
if [ -z "$kdc_ok" ]; then
  echo "ws: FAIL-SOFT - dc01:88 never became reachable; staying up without domain join"
  touch "$STATE_DIR/join-failed"
  exec tail -f /dev/null
fi

# Idempotent join with 5 retries. 'realm' reads the password from stdin when
# it is not attached to a TTY.
joined=0
if realm list 2>/dev/null | grep -qi 'lab.local'; then
  echo "ws: already joined to LAB.LOCAL"
  joined=1
else
  for attempt in 1 2 3 4 5; do
    if printf '%s\n' "$DC_ADMIN_PASS" | realm join LAB.LOCAL -U administrator 2>/tmp/realm.err; then
      echo "ws: domain join succeeded (attempt $attempt)"
      joined=1
      break
    fi
    echo "ws: join attempt $attempt failed: $(tail -2 /tmp/realm.err)"
    sleep 10
  done
fi

if [ "$joined" = "1" ]; then
  if [ -f /etc/sssd/sssd.conf ]; then
    # Short names + predictable home dirs, sssd.conf hardening per sssd docs.
    sed -i 's/^use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
    grep -q '^fallback_homedir' /etc/sssd/sssd.conf \
      || sed -i '/^\[domain\/lab.local\]/a fallback_homedir = /home/%u' /etc/sssd/sssd.conf
    chmod 600 /etc/sssd/sssd.conf
  fi
  pkill -f /usr/sbin/sssd 2>/dev/null || true
  sleep 1
  /usr/sbin/sssd || echo "ws: sssd failed to start (join state kept)"
  rm -f "$STATE_DIR/join-failed"
  touch "$STATE_DIR/joined"
  echo "ws: domain-joined; identity check: getent passwd jsmith (may need a moment)"
  getent passwd jsmith || echo "ws: jsmith not resolvable yet (sssd cache warming)"
else
  echo "ws: FAIL-SOFT - join failed after 5 attempts; container stays up (unhealthy)."
  echo "ws: inspect with 'docker logs ws1', retry with 'docker compose restart ws1'."
  touch "$STATE_DIR/join-failed"
fi

exec tail -f /dev/null
