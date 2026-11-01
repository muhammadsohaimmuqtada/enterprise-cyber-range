#!/bin/bash
# web01 entrypoint: pin routing through the firewall, start cron (the phase-7
# persistence demo needs a scheduler), start gunicorn, then hand PID 1 to
# nginx. gunicorn's stdout (portal + request logs) is captured by the
# container json-file driver, so it survives local log tampering.
set -euo pipefail

ip route replace default via 10.10.10.1 2>/dev/null \
  || echo "web01: could not pin default route via fw (continuing)"

mkdir -p /var/log/app /var/log/nginx

cron || echo "web01: cron did not start (phase 7 persistence demo will be unavailable)"

gunicorn --chdir /opt/app --bind 127.0.0.1:8000 --workers 2 \
         --access-logfile - --error-logfile - --capture-output app:app &

echo "web01: portal up (WEAK_AUTH=${WEAK_AUTH:-0})"
exec nginx -g 'daemon off;'
