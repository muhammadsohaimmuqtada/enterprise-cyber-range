# Firewall baseline — the range's full rule table

> Reference configuration — authorized lab use only.

Source of truth: [`fw/nftables.conf`](../fw/nftables.conf). Rules carry these
IDs as inline comments so `nft -a list chain inet filter forward` maps 1:1 to
this table.

## Forward chain (all inter-segment traffic)

| # | Action | Source | Destination | Port | Matches-video note |
|---|---|---|---|---|---|
| FW-01 | accept | any | any | any | Stateful: `ct state established,related` — "the workhorse of modern networks" |
| FW-02 | drop | any | any | any | Invalid connection state |
| FW-03 | accept (rate 5/s) | any | any | icmp | Rate-limited ping for troubleshooting |
| FW-04 | accept | attack-net | web01 10.10.10.5 | 80, 443/tcp | Perimeter: only the public web app is exposed (north-south inbound) |
| FW-05 | log `FW-EDGE-DENY:` (rate 10/s) | attack-net | any | any | Perimeter deny logging |
| FW-06 | drop | attack-net | any | any | Edge: everything else from outside is dropped |
| FW-07 | accept | dmz | filesrv 10.10.30.11 | 445/tcp | The video's one-door rule: DMZ may speak SMB to this one server (phase 4 path) |
| FW-08 | accept | dmz | dc01 10.10.30.10 | 88, 464/tcp | Kerberos to the DC |
| FW-09 | accept | dmz | dc01 10.10.30.10 | 123/udp | NTP to the DC |
| FW-10 | log `FW-LATERAL-DENY:` (rate 10/s) | dmz | servers | any | East-west deny logging |
| FW-11 | drop | dmz | servers | any | The "blocked path": a compromised web server cannot roam |
| FW-12 | accept | users | filesrv 10.10.30.11 | 445/tcp | "Workstation may speak file sharing to this one server" |
| FW-13 | accept | users | dc01 10.10.30.10 | 53, 88, 135, 389, 445, 464/tcp | AD service set (tcp/53 + 389 added so the domain join works — see fw/README.md) |
| FW-14 | accept | users | dc01 10.10.30.10 | 53, 88, 389, 464/udp | AD service set over UDP (DNS, Kerberos, CLDAP, kpasswd) |
| FW-15 | log `FW-LATERAL-DENY:` (rate 10/s) | users | servers | any | East-west deny logging |
| FW-16 | drop | users | servers | any | Workstations cannot roam either |
| FW-17 | accept | users | dmz | 443/tcp | Users reach the intranet portal over HTTPS |
| FW-18 | log `FW-LATERAL-DENY:` (rate 10/s) | users | dmz | any | East-west deny logging |
| FW-19 | drop | users | dmz | any | No other user→DMZ access |
| FW-20 | accept | web01 10.10.10.5 | attack-net | 443/tcp | Egress: the pre-authorized phase-6 exfil path |
| FW-21 | log `FW-EGRESS-DENY:` (rate 10/s) | dmz, users | attack-net | any | Egress deny logging |
| FW-22 | drop | dmz, users | attack-net | any | Egress filtering: internal hosts do not talk to the outside |
| FW-23 | drop (counter) | any | any | any | **IMPLICIT DENY** — if nothing above explicitly allowed it, it is blocked |

## NAT (prerouting, edge port-forwards)

| # | Action | Match | Target | Note |
|---|---|---|---|---|
| FW-N1 | dnat | attack-net → 172.31.100.1:80 | 10.10.10.5:80 | Public HTTP lands on web01 |
| FW-N2 | dnat | attack-net → 172.31.100.1:443 | 10.10.10.5:443 | Public HTTPS lands on web01 |

## Input chain (traffic to the firewall itself)

| # | Action | Match | Note |
|---|---|---|---|
| FW-I1 | accept | loopback | |
| FW-I2 | accept | established, related | Replies to the firewall's own flows |
| FW-I3 | drop | invalid state | |
| FW-I4 | accept (rate 5/s) | icmp | |
| FW-I5 | accept | attack-net tcp/22 | Admin SSH path (no sshd ships in the reference image) |
| FW-I6 | log `FW-INPUT-DENY:` (rate 10/s) | everything else | |
| FW-I7 | drop | — | Implicit deny on input |

## Reading and using the baseline

```bash
docker exec fw nft list ruleset                          # everything
docker exec fw nft -a list chain inet filter forward     # forward chain + handles
docker exec fw nft -f /fw/nftables.conf                  # reload after edits
docker logs fw 2>&1 | grep FW-                           # deny lines (stdout mirror)
docker exec fw dmesg | grep FW-                          # kernel log (best effort)
```

Properties to keep in mind when changing anything:

- **First match wins** — evaluation stops at the first matching rule, so
  rule order is policy. FW-04 must precede FW-05/FW-06; FW-20 must precede
  FW-21/FW-22.
- **Implicit deny** — FW-23 (and FW-I7) end the chain with `counter drop`.
  Removing an allow rule closes the path; nothing needs to be denied
  explicitly.
- Every deny rule logs (rate-limited to keep the log readable) and counts;
  every allow rule on the attacker's interesting paths counts too, so the
  blue team can see allowed volumes (`make status`).
