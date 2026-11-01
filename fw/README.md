# fw — the range's firewall (reference configuration)

> Reference configuration — authorized lab use only.

The `fw` container is a Debian box running nftables, attached to all four
compose networks with static `.1` addresses. It is the **only** router between
segments: every packet that crosses a segment boundary must traverse this
ruleset, which makes it the lab's perimeter firewall and its internal
segmentation firewall at the same time.

```
attack-net 172.31.100.0/24 ──┐
        dmz 10.10.10.0/24  ──┤   fw (nftables, ip_forward=1, CAP_NET_ADMIN)
      users 10.10.20.0/24  ──┤   ruleset: /fw/nftables.conf (mounted read-only)
    servers 10.10.30.0/24  ──┘
```

## Which of the video's five firewall types is this?

| Type (from the video) | What it decides on | In this range |
|---|---|---|
| Packet-filtering | header fields only: IPs, ports, protocol, per rule, no memory of previous packets | The `ct state invalid` / plain header rules (FW-02) are pure packet-filtering |
| **Stateful** | header fields **plus connection state** (conntrack): replies to allowed flows are accepted without new rules | **This is the type `fw` implements** — FW-01 `ct state established,related accept` is the workhorse the video describes |
| Proxy / WAF | the actual application payload: terminates the connection, inspects HTTP, rewrites or blocks | Not installed. Slot-in documented below (squid as a userspace forward proxy; nginx+ModSecurity in front of the Flask app as the WAF) |
| Next-Generation Firewall (NGFW) | applications and identities, not just ports: app-aware filtering, TLS inspection, feeds | Not installed. The closest analog is the SIEM rule pack (`siem/rules/local-rules.xml`) doing app-aware detection out of band |
| Host-based | runs **on the endpoint** and filters its own traffic | Not installed as a daemon; the analog is per-host policy: Samba share ACLs on `filesrv` and `WEAK_AUTH=0` on `web01` — authorization enforced by the host itself |

So: `fw` is a **stateful packet-filtering firewall with NAT**, exactly the
"the workhorse of modern networks" category from the video. The `inet nat`
table (`FW-N1`, `FW-N2`) does the edge port-forwarding: inbound 80/443 to
`172.31.100.1` is DNAT'd to `web01` (`10.10.10.5`) — the classic NAT
port-forward that lets a private DMZ host serve a public site.

## Rule table

Full annotated table with video mappings: [`detections/fw-baseline.md`](../detections/fw-baseline.md).
Quick orientation:

| Prefix | Meaning | Rules |
|---|---|---|
| — (accept) | perimeter: only web01 :80/:443 reachable from outside | FW-04 |
| `FW-EDGE-DENY` | outside tried anything else | FW-05, FW-06 |
| — (accept) | DMZ may speak SMB to filesrv only, Kerberos+NTP to the DC | FW-07..09 |
| `FW-LATERAL-DENY` | east-west move the segmentation forbids | FW-10, FW-11, FW-15, FW-16, FW-18, FW-19 |
| — (accept) | workstation rule: file share + AD service ports | FW-12..14, FW-17 |
| — (accept) | egress: web01 may make outbound HTTPS (the phase-6 exfil path) | FW-20 |
| `FW-EGRESS-DENY` | internal host tried to phone home | FW-21, FW-22 |
| — (drop) | **IMPLICIT DENY** — final catch-all with counter | FW-23 |
| `FW-INPUT-DENY` | traffic addressed to the firewall itself | FW-I1..I7 |

Two properties to internalize while walking the phases:

1. **First match wins.** Rules are evaluated top to bottom and the first match
   terminates evaluation. FW-04 accepts web traffic *before* FW-05/FW-06 can
   ever see it; FW-20 accepts web01:443 egress *before* FW-21/FW-22 can deny
   it. Moving a rule changes behavior.
2. **Implicit deny.** FW-23 is the last rule: `counter drop`. Delete every
   explicit allow and the network still fails closed.

## Operating it

```bash
docker exec fw nft -f /fw/nftables.conf                    # reload the ruleset
docker exec fw nft list ruleset                            # full ruleset
docker exec fw nft -a list chain inet filter forward       # counters + rule handles
docker exec fw nft delete rule inet filter forward handle <N>   # remove one rule
docker exec fw nft insert rule inet filter forward ip saddr 10.10.10.5 drop \
  comment "blue: quarantine web01"                         # prepend a rule (wins first-match)
docker logs fw 2>&1 | grep FW-                             # deny lines mirrored to stdout
docker exec fw dmesg | grep FW-                            # kernel log (best effort; needs
                                                           # readable dmesg in-container)
```

Every deny rule carries a `counter`, so `nft -a list chain ...` shows packet
and byte counts per rule — that is the deterministic blue-team signal in any
environment, including GitHub Codespaces.

## Where the proxy/WAF and NGFW would slot in

**Userspace forward proxy (the "proxy firewall" row).** A squid container in
the DMZ would terminate outbound connections from `web01` and re-originate
them, so egress control moves from "which IP:port" to "which URL". Sketch:

```yaml
  # add to docker-compose.yml, then change FW-20 to send web01's egress to the
  # proxy instead of straight out:
  proxy:
    image: ubuntu/squid:latest
    container_name: proxy
    hostname: proxy
    networks:
      dmz:
        ipv4_address: 10.10.10.6
      attack-net: {}
    # squid.conf: http_access allow to_localhost 443; http_access deny all
```

With a proxy in place the firewall rule becomes "DMZ may reach only
10.10.10.6:3128" and the proxy enforces the allowlist — that is the
proxy-firewall idea from the video.

**WAF.** Put ModSecurity (or a commercial WAF) in front of gunicorn inside
`web01`'s nginx: it would be the component that recognizes
`admin' OR 1=1--` as an attack payload rather than an odd password.

**NGFW.** An NGFW would add application- and identity-aware controls on the
same wire: "this is SMB, but *this* service account may not write" — much of
which this lab demonstrates out of band via the SIEM rules instead.

## Operational notes

- Network gateway addresses are pinned to `.254` in `docker-compose.yml`
  specifically so the `fw` container can own `.1` — the address every
  scenario doc treats as the default gateway. Service entrypoints pin
  `ip route replace default via <fw>` so cross-segment traffic cannot bypass
  the firewall over the Docker host's own routing.
- DNS from workstations to the DC (udp/tcp 53) is part of the AD allowlist
  (FW-13/FW-14). The container runtime's embedded resolver can also proxy
  some DNS on behalf of containers; the allowlist still governs direct
  client traffic.
- `FW-I5` permits admin SSH from attack-net to the firewall. The reference
  image deliberately ships no sshd; the rule documents where interactive
  firewall administration would attach.
- tcp/53 and tcp/389 appear in the workstation-to-DC allowlist in addition to
  the video's minimal port set because the Samba domain join (realmd/adcli)
  needs DNS-over-TCP and LDAP; they are commented inline as FW-13/FW-14.
