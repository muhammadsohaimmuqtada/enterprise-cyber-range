# IP plan and VLAN mapping

> Reference documentation — authorized lab use only.

## Segment-to-VLAN mapping

Docker bridge networks emulate VLANs: same isolation property (hosts on one
segment cannot reach hosts on another except through the firewall), no
802.1Q tagging. The mapping used throughout the repo:

| Segment | Subnet | Docker network | VLAN analog | Notes |
|---|---|---|---|---|
| attack-net | 172.31.100.0/24 | `ecr-attack-net` | VLAN 100 — external/transit | Where the attacker and the fake ISP hop live |
| dmz | 10.10.10.0/24 | `ecr-dmz` | VLAN 10 — DMZ | Public-facing services only |
| users | 10.10.20.0/24 | `ecr-users` | VLAN 20 — office LAN | Domain workstations |
| servers | 10.10.30.0/24 | `ecr-servers` | VLAN 30 — server VLAN | AD DC, file server, SIEM |

## Full IP plan

| Host | IP | Segment | Role |
|---|---|---|---|
| fw | 172.31.100.1 | attack-net | Perimeter + internal firewall (nftables), default gateway for all segments |
| fw | 10.10.10.1 | dmz | Gateway |
| fw | 10.10.20.1 | users | Gateway |
| fw | 10.10.30.1 | servers | Gateway |
| attacker | 172.31.100.x (dynamic) | attack-net | Kali red-team workstation (user `red`) |
| internet | 172.31.100.10 | attack-net | Simulated ISP hop (static page on 80) |
| web01 | 10.10.10.5 | dmz | nginx + Flask "Acme Intranet Portal" (gunicorn on 127.0.0.1:8000) |
| ws1 | 10.10.20.5 | users | Domain workstation |
| ws2 | 10.10.20.6 | users | Domain workstation |
| dc01 | 10.10.30.10 | servers | Samba AD DC — realm LAB.LOCAL, netbios LAB |
| filesrv | 10.10.30.11 | servers | Standalone SMB server — shares `public`, `critical` |
| siem | 10.10.30.20 | servers | Wazuh manager (blue profile only) |

Docker IPAM gateways are pinned to `.254` in each subnet so the `fw`
container can hold the `.1` addresses; all service entrypoints route
`default via <fw>`.

## DNS

| Consumer | Resolver | Why |
|---|---|---|
| ws1, ws2 | 10.10.30.10 (dc01, Samba internal DNS) | AD discovery needs the DC's SRV records; `/etc/resolv.conf` set by the ws entrypoint |
| dc01, filesrv, web01, attacker | Docker embedded resolver (127.0.0.11) | Service-name resolution inside the compose project |
| Domain zone | `lab.local` served by dc01 (53/tcp+udp) | `dc01.lab.local = 10.10.30.10`, SRV records for Kerberos/LDAP |

## Service port map (the video's port list)

| Host | Port | Service | Reachable from |
|---|---|---|---|
| fw | 80, 443 (DNAT → web01) | Public web | attack-net only |
| fw | 22 | Admin SSH path (no sshd in the reference image) | attack-net only |
| web01 | 80, 443 | Portal (nginx → gunicorn) | attack-net (via DNAT), users (443 via FW-17) |
| dc01 | 53 | DNS (Samba internal) | users (FW-13/14); servers directly |
| dc01 | 88, 464 | Kerberos / kpasswd | dmz (FW-08), users (FW-13/14) |
| dc01 | 135 | RPC endpoint mapper | users (FW-13) |
| dc01 | 389, 636 | LDAP / LDAPS | users (FW-13); 636 not allowlisted |
| dc01 | 445 | SMB (SYSVOL, NETLOGON, admin shares) | users (FW-13) |
| filesrv | 445, 139 | SMB (public, critical) | dmz (FW-07), users (FW-12) |
| siem | 1514, 1515 | Wazuh agent / enrollment | Not allowlisted — opened temporarily per `siem/README.md` |
| internet | 80 | Fake ISP page | attack-net |
