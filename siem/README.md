# siem — Wazuh manager (blue profile, reference configuration)

> Reference configuration — authorized lab use only.

The `siem` service is a single-node Wazuh manager (`wazuh/wazuh-manager:4.7.5`)
started only with the blue profile:

```bash
make blue                      # == docker compose --profile blue up -d
```

Budget roughly **4 GB of RAM** for the manager (`mem_limit: 4g` is set in
`docker-compose.yml`). Custom rules from `siem/rules/local-rules.xml` are
mounted read-only at `/var/ossec/etc/rules/local_rules.xml` (range
100900-100999).

## What the rules detect

| Rule | Level | Fires on |
|---|---|---|
| 100900 | 5 | any `FW-EDGE-DENY` perimeter deny |
| 100901 | 10 | burst: 20+ edge denies within 60 s (recon/brute-force shape) |
| 100902 | 8 | `FW-LATERAL-DENY` east-west move blocked by segmentation |
| 100910 | 12 | `AUTH-BYPASS` — simulated login bypass accepted on web01 |
| 100911 | 12 | `CONSOLE-EXEC` — command ran through the `/console` shell |
| 100920 | 12 | `smbd_audit ... critical|open|ok` — file read on the `critical` share |
| 100921 | 12 | modify/rename/delete on the `critical` share (FIM-analog) |
| 100930 | 8 | `FW-EGRESS-DENY` — internal host attempted outbound traffic |
| 100931 | 12 | `FW-EGRESS-DENY ... DPT=445` — outbound SMB exfil attempt |
| 100940 | 10 | deletion of a `.log` file over SMB (covering-tracks analog) |

## Validating rules without agents

You can exercise the custom rulepack immediately — no agents required:

```bash
docker exec -it siem /var/ossec/bin/wazuh-logtest
# paste, for example:
# FW-EDGE-DENY: IN=eth0 OUT=eth1 SRC=172.31.100.3 DST=10.10.30.11 PROTO=TCP SPT=55500 DPT=445
# expected: rule 100900 fires (level 5)
```

## Connecting the log sources (agent install)

The range's log sources are `web01` (`/var/log/app/access.log`), `filesrv`
(`/var/log/samba/audit.log`), and `fw` (`/var/log/fw-kernel.log` when the
kernel-log mirror is readable). Wazuh agents ship those files to the manager.

The manager listens for agents on tcp/1514 and enrollment on tcp/1515 on
`10.10.30.20`. Because the firewall's DMZ->servers allowlist deliberately does
not include those ports, install time is the one moment you open them — which
is itself a nice blue-team exercise in controlled rule changes.

```bash
# 1) Temporarily allow agent traffic dmz/servers -> siem (prepend = wins first-match):
docker exec fw nft insert rule inet filter forward ip daddr 10.10.30.20 tcp dport { 1514, 1515 } accept comment "blue: temporary agent install"
# 2) Install the agent matching the manager version, point it at the SIEM:
docker exec web01 bash -c 'curl -s https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.5-1_amd64.deb -o /tmp/wazuh-agent.deb && WAZUH_MANAGER=10.10.30.20 dpkg -i /tmp/wazuh-agent.deb && service wazuh-agent start'
docker exec filesrv bash -c 'curl -s https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.7.5-1_amd64.deb -o /tmp/wazuh-agent.deb && WAZUH_MANAGER=10.10.30.20 dpkg -i /tmp/wazuh-agent.deb && service wazuh-agent start'
# 3) Revert the temporary rules (find the handles first):
docker exec fw nft -a list chain inet filter forward
docker exec fw nft delete rule inet filter forward handle <N>
```

Wazuh-manager reads its own alert stream at `/var/ossec/logs/alerts/alerts.json`
inside the `siem` container.

## EDR-analog note

This range has no commercial EDR. The analog stack is:

- **auditd** on the hosts for process/file telemetry (`execve`, watches on
  `/srv/critical` and `/srv/notes`) — rules and caveats in
  [`detections/audit-policy.md`](../detections/audit-policy.md);
- **Wazuh FIM (syscheck)** watching `/srv/critical` once an agent is installed
  — the file-integrity half of the EDR picture;
- **vfs_full_audit** providing the file-access event stream that Windows
  environments would get from 4663-style event logging.
