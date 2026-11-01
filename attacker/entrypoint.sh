#!/bin/bash
# attacker entrypoint: pin the default route through the firewall container so
# all recon/exploit traffic visibly traverses the nftables policy (needs the
# NET_ADMIN cap granted in docker-compose.yml), then exec the CMD.
ip route replace default via 172.31.100.1 2>/dev/null \
  || echo "attacker: could not pin route via fw (traffic may bypass the firewall)"
exec "$@"
