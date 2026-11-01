# Architecture — the range at a glance

> Reference documentation — authorized lab use only.

## Topology

```
                     (simulated internet)
                     internet 172.31.100.10 (fake "ISP" page)
                              |
   +--------------------------+--------------------------+
   |            attack-net   172.31.100.0/24              |  VLAN-100 analog: outside
   |            attacker 172.31.100.x (Kali)              |
   +--------------------------+--------------------------+
                              |
                     +----------------+
   fw is the ONLY    |       fw       | 172.31.100.1 / 10.10.10.1 / 10.10.20.1 / 10.10.30.1
   path between      |   (nftables)   | stateful packet filter + NAT (dnat) + egress filter
   segments          +----------------+ ruleset: fw/nftables.conf
                              |
   +--------------------------+--------------------------+
   |                   dmz   10.10.10.0/24               |  VLAN-10 analog: DMZ
   |                   web01 10.10.10.5                  |
   |             (nginx TLS + Flask portal)              |
   +--------------------------+--------------------------+
                              |
   +--------------------------+--------------------------+
   |                 users   10.10.20.0/24               |  VLAN-20 analog: office LAN
   |        ws1 10.10.20.5        ws2 10.10.20.6         |
   |        (domain-joined Debian workstations)          |
   +--------------------------+--------------------------+
                              |
   +--------------------------+--------------------------+
   |                servers  10.10.30.0/24               |  VLAN-30 analog: server VLAN
   |     dc01 10.10.30.10 (Samba AD DC, realm LAB.LOCAL) |
   |     filesrv 10.10.30.11 (standalone SMB, shares     |
   |                         public + critical)          |
   |     siem 10.10.30.20 (Wazuh, "blue" profile)        |
   +-----------------------------------------------------+
```

Every service entrypoint pins `ip route replace default via <fw>`, so all
inter-segment traffic physically traverses the firewall container; Docker's
own inter-bridge isolation prevents shortcuts over the host. Gateway
addresses are pinned to `.254` precisely so the `fw` container can own the
`.1` addresses the scenarios treat as default gateways.

## IP plan

| Segment | Subnet | Members | Gateway (fw) | Docker IPAM gateway |
|---|---|---|---|---|
| attack-net | 172.31.100.0/24 | attacker (dynamic 172.31.100.x), internet 172.31.100.10 | 172.31.100.1 | 172.31.100.254 |
| dmz | 10.10.10.0/24 | web01 10.10.10.5 | 10.10.10.1 | 10.10.10.254 |
| users | 10.10.20.0/24 | ws1 10.10.20.5, ws2 10.10.20.6 | 10.10.20.1 | 10.10.20.254 |
| servers | 10.10.30.0/24 | dc01 10.10.30.10, filesrv 10.10.30.11, siem 10.10.30.20 (blue profile) | 10.10.30.1 | 10.10.30.254 |

Full addressing and service-port detail: [`ips-vlans.md`](ips-vlans.md).

## North-south vs east-west (the video's terminology)

**North-south** is traffic crossing the perimeter: the attacker's HTTPS into
`web01` (FW-04, after the FW-N1/FW-N2 DNAT) and `web01`'s outbound 443 toward
the external segment (FW-20) are the two north-south doors this range has.
Everything else crossing the perimeter is logged as `FW-EDGE-DENY` or
`FW-EGRESS-DENY` and dropped — the video's point that perimeter rules are
few, explicit, and everything-not-listed dies.

**East-west** is traffic between internal segments: `web01 → filesrv` SMB
(FW-07 — the one door the phase-4 lateral movement walks through),
workstation → DC AD traffic (FW-12..14 — the "workstation may speak file
sharing to this one server" rule), workstation → portal HTTPS (FW-17).
East-west is where segmentation pays: the phase-3 port sweep shows the
compromised DMZ host reaching almost nothing, because lateral movement is
what internal segmentation is for.

## Where the video's defensive tooling would add on (and why it is out of scope)

**IDS/IPS.** An IDS reads copies of traffic and alerts; an IPS sits inline
and blocks. In this range the nftables rules already *are* the inline
blocker, and the SIEM rules are the alerting half. A real IDS/IPS (Suricata
on the fw container, tapping the forward path with NFQUEUE or a mirror
interface) would add signature-based payload detection — e.g. flagging the
`admin' OR 1=1--` string in transit rather than at the application log.
Out of scope because the lab teaches the boundary and the logs, not sensor
tuning.

**NAC.** Network Access Control authenticates *devices* before letting them
onto a network (802.1X). The range's analog is static: only workstations
that joined the domain hold valid machine identities on the users segment.
A NAC deployment would put a RADIUS/802.1X gate in front of the users
segment. Out of scope because Docker bridges have no 802.1X port concept.

**Jump host.** A hardened bastion through which admins reach internal hosts.
Today the admin path is FW-I5 (SSH to the firewall from attack-net). A jump
host would be a dedicated container in the users segment, with the firewall
rewritten so *no* direct admin path exists. It is out of scope to keep the
host count small, and it is called out here so its absence is a decision,
not an oversight.

**EDR.** Endpoint Detection and Response runs on the hosts, watching
processes, files, and memory. The range's analog stack is auditd (reference
rules in `detections/audit-policy.md`) plus Wazuh FIM (`siem/README.md`).
A real EDR agent would give the same telemetry with kernel-level coverage.
Out of scope for licensing and container-capability reasons; the analog
teaches the same "endpoint telemetry → detection" loop.

**NGFW.** An application- and identity-aware firewall would sit exactly
where `fw` sits, but decide on applications ("this is SMB, but this account
may not write") instead of ports. The range demonstrates the missing half
out of band: `filesrv`'s share ACLs make per-identity decisions the packet
filter cannot. Out of scope because NGFW functionality needs userspace
inspection that would double the lab's complexity.

**WAF.** A web application firewall would sit in front of the Flask portal
(nginx + ModSecurity) and is the component that would recognize the login
bypass payload as an attack. The range deliberately ships the vulnerable
portal *without* it, because phase 2's detection (SIEM 100910) is the lesson;
`fw/README.md` documents exactly where a WAF would slot in.
