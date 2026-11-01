# Phase 1 — Remote entry (external reconnaissance)

> Reference scenario — authorized lab use only. See [`../DISCLAIMER.md`](../DISCLAIMER.md).

## Video concept

Reconnaissance (kill chain step 1), the attack surface concept, and the
perimeter firewall deciding what the outside world can even see.

## Objective

From the attacker container, discover what the enterprise exposes: the edge
firewall at `172.31.100.1`, the DMZ web app behind it on 80/443, and — just
as important — everything that is *not* reachable, because that is the
segmentation doing its job.

## Attacker steps

```bash
# Your seat on the outside:
docker exec -it attacker bash
# (expected IP: 172.31.100.x - check it, the blue team will see this source)
ip -4 addr show eth0

# Sweep the "external" target - the firewall's outside address:
# 22 = the admin path, 80/443 = the DNAT'd web app, 445/3306/3389 = decoys the
# video lists (SMB, database, RDP) that the perimeter must NOT expose.
sudo nmap -sV -Pn -T4 --host-timeout 180s -p 22,80,443,445,3306,3389 172.31.100.1
#   expected: 80/tcp and 443/tcp open (nginx, web01 behind the FW-N1/FW-N2
#   port-forwards), 22 open|filtered (rule FW-I5, no sshd installed),
#   everything else filtered.

# Confirm the web app is the entire exposure:
curl -sk -I https://172.31.100.1/ | head -5
curl -sk https://172.31.100.1/login | head -10

# The other outside host is the fake ISP hop - make sure it is not confused
# with the target:
nmap -sV -p 80 172.31.100.10
```

## What the blue team sees

| Signal | Where | Sample line | Detection |
|---|---|---|---|
| Edge accepts (FW-04) | fw counters | `tcp dport { 80, 443 } ... counter packets 57 bytes 8412 accept comment "FW-04 ..."` | `docker exec fw nft -a list chain inet filter forward` |
| Edge denies for the closed ports | fw log | `FW-EDGE-DENY: IN=eth0 OUT=eth1 SRC=172.31.100.3 DST=10.10.10.5 PROTO=TCP SPT=55432 DPT=445` | SIEM rule 100900; burst → 100901 |
| The probes that reached the portal | web01 nginx | `172.31.100.3 - - [15/Jan/2026:03:00:09 +0000] "GET /login HTTP/1.1" 200 941 "-" "curl/8.5.0"` | `docker exec web01 tail /var/log/nginx/access.log` |

```bash
# Blue-team commands:
docker exec fw nft -a list chain inet filter forward      # counters per rule
docker logs fw 2>&1 | grep 'FW-EDGE-DENY' | tail          # deny lines (stdout mirror)
docker exec web01 tail -20 /var/log/nginx/access.log      # what the scan looked like
```

First-match-wins in action: the 80/443 probes match FW-04 and never reach
FW-05/FW-06; the 445/3389 probes fall through to the edge-deny log and drop.

## IOC vs IoA box

- **IOC (artifact):** the scanning source IP (`172.31.100.3` above) recorded
  in `FW-EDGE-DENY` lines and nginx access logs — a concrete observable you
  could block at the edge.
- **IoA (behavior):** six ports probed in one quick sweep from a single
  external source — the *pattern* of a scan, even when every individual
  packet is unremarkable.

## Kill chain position

Step 1 — reconnaissance. (The scan also maps the attack surface: exactly one
service is reachable, which is the perimeter firewall's answer to "how big is
our outside?".)
