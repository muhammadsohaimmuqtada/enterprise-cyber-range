# SOC runbook — alert → investigate → contain

> Reference configuration — authorized lab use only.

First-response playbook for the alerts this range produces. "First 3" means
the first three commands to run, in order, before touching anything.

| Alert (SIEM rule / source) | Log source | First 3 investigation commands | Containment |
|---|---|---|---|
| Perimeter deny burst (100901 / FW-EDGE-DENY) | fw kernel log, mirrored to `docker logs fw` | 1. `docker logs fw 2>&1 \| grep 'FW-EDGE-DENY' \| tail -50` 2. `docker logs fw 2>&1 \| grep 'FW-EDGE-DENY' \| awk '{for(i=1;i<=NF;i++) if($i~/^SRC=/) print $i}' \| sort \| uniq -c \| sort -rn` 3. `docker exec web01 tail -50 /var/log/nginx/access.log` | If a single external source: `docker exec fw nft insert rule inet filter forward ip saddr <SRC> drop comment "blue: block scanned source"` (revert: `nft delete rule ... handle <N>`) |
| Auth bypass accepted (100910 / AUTH-BYPASS) | web01 `/var/log/app/access.log` + stdout | 1. `docker exec web01 grep 'AUTH-BYPASS' /var/log/app/access.log` 2. `docker exec web01 grep 'CONSOLE-EXEC' /var/log/app/access.log \| tail -20` 3. `docker logs web01 2>&1 \| tail -100` | Rebuild the web tier: `docker compose up -d --force-recreate web01` (keeps logs in `docker logs` history; resets the foothold) |
| Web shell command executed (100911 / CONSOLE-EXEC) | web01 app log + stdout | 1. `docker exec web01 grep 'CONSOLE-EXEC' /var/log/app/access.log` 2. `docker exec web01 ls -la /tmp/ /tmp/staging 2>/dev/null` 3. `docker exec web01 crontab -l` | Quarantine at the firewall: `docker exec fw nft insert rule inet filter forward ip saddr 10.10.10.5 drop comment "blue: quarantine web01"`; then recreate web01 |
| East-west move denied (100902 / FW-LATERAL-DENY) | fw log | 1. `docker logs fw 2>&1 \| grep 'FW-LATERAL-DENY' \| tail -50` 2. `docker logs fw 2>&1 \| grep 'FW-LATERAL-DENY' \| grep -o 'SRC=[^ ]* DST=[^ ]* DPT=[0-9]*' \| sort \| uniq -c` 3. `docker exec filesrv tail -50 /var/log/samba/audit.log` | Usually "working as intended". If the *source* is compromised: see the quarantine rule above |
| Critical share read (100920 / smbd_audit critical\|open) | filesrv `/var/log/samba/audit.log` | 1. `docker exec filesrv grep 'critical\|open\|ok' /var/log/samba/audit.log \| tail` 2. `docker exec filesrv grep 'fileshare\|' /var/log/samba/audit.log \| awk -F'\|' '{print $2}' \| sort -u` (every source IP) 3. `docker exec web01 grep 'critical' /var/log/app/access.log \| tail` | Rotate the share credential: `docker exec -i filesrv smbpasswd -s fileshare` (type the new password twice); then hunt other readers via the audit log |
| Outbound SMB egress attempt (100931 / FW-EGRESS-DENY DPT=445) | fw log | 1. `docker logs fw 2>&1 \| grep 'FW-EGRESS-DENY' \| tail -50` 2. `docker exec web01 grep -E 'curl -T\|tar czf' /var/log/app/access.log \| tail` 3. `docker exec web01 ls -la /tmp/staging 2>/dev/null` | Close the egress hole: `docker exec fw nft insert rule inet filter forward ip saddr 10.10.10.5 ip daddr 172.31.100.0/24 tcp dport 443 drop comment "blue: egress block"` (revert with the handle from `nft -a list chain ...`) |
| Log deletion over SMB (100940) / local truncate attempt | filesrv audit / web01 stdout | 1. `docker logs web01 2>&1 \| grep 'truncate'` 2. `docker logs web01 2>&1 \| grep -c 'AUTH-BYPASS'` (evidence survived?) 3. `docker exec filesrv grep 'unlink' /var/log/samba/audit.log \| tail` | Treat as full compromise: `make reset` and replay; if a SIEM agent is installed, export `siem:/var/ossec/logs/alerts/` before resetting |

## Standing notes

- Every containment `nft insert rule` wins by **first-match-wins** (prepend);
  revert with `docker exec fw nft -a list chain inet filter forward` to get
  the handle, then `nft delete rule inet filter forward handle <N>`.
- `docker logs` survives in-container log tampering (json-file driver), which
  is why investigation step 3 for web01 alerts always checks stdout.
- After any incident, run `make reset` for a clean range, then re-run the
  phase as the defender while reading the logs live.
