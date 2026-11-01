# Video mapping — chapter → repo artifact

> Reference documentation — authorized lab use only.

Every chapter of "Red Team vs Blue Team — Cybersecurity Terms & Concepts
Explained" is runnable somewhere in this repository. This table is the
index; each row names the artifact(s) that demonstrate the concept.

| # | Video chapter | Where it lives in this repo |
|---|---|---|
| 0 | Ground rules: isolated lab, authorization, defensive goal | `DISCLAIMER.md` (the three rules verbatim), `scenario/PHASE-0-setup.md`, compose networks with no published host ports |
| 1 | Red team / blue team / purple team | `attacker/` (red), `siem/` + `detections/` (blue), the two-pass purple-team tip in `scenario/PHASE-0-setup.md`, paired attacker/defender sections in every phase doc |
| 2 | Attack surface | `fw/nftables.conf` FW-04..FW-06 (exactly one service exposed), `docs/architecture.md`, phase 1's port sweep |
| 3 | The 8-step cyber kill chain (recon, initial access, execution, persistence, privilege escalation, lateral movement, exfiltration, impact) | `scenario/PHASE-1..7` — each phase doc states its kill chain position; `docs/architecture.md` shows the paths between steps |
| 4 | TTPs, IOC vs IoA | `attacker/redteam-tools.md` (tool → TTP mapping), `detections/ioc-ioa-worksheet.md`, the "IOC vs IoA box" in every phase doc, `siem/rules/local-rules.xml` |
| 5 | Dwell time | `scenario/PHASE-7-persistence-covering-tracks.md` (beacon rhythm, log tampering vs centralized copies), `detections/soc-runbook.md`, `siem/README.md` |
| 6 | NAT, DMZ, VLANs, north-south vs east-west | `docker-compose.yml` (four bridge networks = VLAN analogs), `fw/nftables.conf` (DNAT = NAT, segment allowlists), `docs/ips-vlans.md`, `docs/architecture.md` (north-south/east-west flows) |
| 7 | Ports 80/443/22/53/135/445/3389 | `fw/nftables.conf` (each port appears as an explicit allow or a logged deny), `dc01/Dockerfile` EXPOSE list, `docs/ips-vlans.md` port map, phase 3's probe table |
| 8 | IDS/IPS, NAC, jump host, SIEM, EDR; client vs server OS; Domain Controller / Active Directory / Kerberos | `siem/` (SIEM), `detections/audit-policy.md` (EDR analog), `ws/` (client OS joined to the domain), `dc01/` (AD DC: Kerberos 88/464, LDAP, SYSVOL analog in `dc01/share-setup.md`), `docs/architecture.md` (where IDS/IPS/NAC/jump host/NGFW/WAF would slot in) |
| 9 | Five firewall types; rule anatomy; first-match-wins; implicit deny; security policies (local, GPO/SYSVOL, AppLocker/WDAC, MDM) | `fw/README.md` (type comparison + rule table), `fw/nftables.conf` (first-match-wins ordering, FW-23 implicit deny, per-rule counters), `policies/password-policy.md` (GPO analog via `samba-tool domain passwordsettings`), `dc01/share-setup.md` (SYSVOL analog) |

## Phase-to-chapter cross-reference

| Scenario phase | Primary chapter(s) | Kill chain steps |
|---|---|---|
| 0 — setup | 0, 1 | — |
| 1 — remote entry | 2, 7, 9 | 1 reconnaissance |
| 2 — initial foothold | 4 (TTP/IOC), 8 | 2 initial access |
| 3 — execution + discovery | 6 (east-west), 9 | 3 execution |
| 4 — lateral movement | 6, 7, 9 | 6 lateral movement |
| 5 — privilege + critical access | 4 (IoA), 8 | 5 privilege escalation |
| 6 — exfiltration | 6 (egress), 9 | 7 exfiltration (+ 8 impact) |
| 7 — persistence + covering tracks | 5 (dwell time), 8 | 4 persistence (+ 8 impact) |
