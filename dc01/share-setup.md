# dc01 — SYSVOL / GPO analog and detection analog (reference documentation)

> Reference documentation — authorized lab use only.

## What the Domain Controller represents

`dc01` is a Samba Active Directory Domain Controller: realm `LAB.LOCAL`,
netbios domain `LAB`, address `10.10.30.10`. It is the video's Domain
Controller chapter made inspectable — Kerberos (88/464), LDAP (389), SMB
(445), DNS (53) all live here, and the workstations `ws1`/`ws2` are real
domain members joined against it.

## SYSVOL / GPO analog

Samba provisions the same structure Windows uses: a `sysvol` tree exported as
the `SYSVOL` and `NETLOGON` shares:

```
/var/lib/samba/sysvol/lab.local/          # the GPO-analog root
/var/lib/samba/sysvol/lab.local/scripts/  # NETLOGON content (logon scripts)
```

Inspect it:

```bash
docker exec dc01 ls -la /var/lib/samba/sysvol/lab.local/
docker exec dc01 smbclient -L //localhost -U 'administrator%Lab-Admin#2026!'
```

There is no group-policy engine in this range (that machinery is
Windows-specific). The represented pieces are:

| Video concept | Lab representation |
|---|---|
| Default Domain Policy (password rules) | `samba-tool domain passwordsettings set ...` — see [`policies/password-policy.md`](../policies/password-policy.md) |
| SYSVOL / NETLOGON share | the provisioned `sysvol` tree above, browsable over SMB |
| Logon scripts distributed via NETLOGON | the `scripts/` directory; drop a file there and it is fetchable by domain clients |
| Local policy on clients | PAM/sssd configuration on `ws1`/`ws2` (client-side enforcement) |
| AppLocker / WDAC (application control) | container images themselves: the web tier runs exactly the image's allowlisted binaries; see `policies/password-policy.md` for the mapping |
| MDM (device configuration) | the compose environment block per service — declarative per-"device" config |

## Detection analog (Windows Event Logs → Linux logs)

The video's blue team reads Windows event logs; this range's blue team reads
the Linux analogs, listed so the mapping is explicit:

| Windows artifact (video) | dc01/ws analog in this range |
|---|---|
| Event 4768 (Kerberos TGT requested) | `/var/log/samba/log.samba` KDC lines on dc01; sssd messages on the workstations |
| Event 4624/4625 (logon success/failure) | samba auth lines in `/var/log/samba/log.samba` |
| Event 4663 (file object access) | `vfs_full_audit` lines in `/var/log/samba/audit.log` on filesrv |
| Sysmon process creation | `auditd` `execve` rules — see [`detections/audit-policy.md`](../detections/audit-policy.md) |
| Event log forwarding to SIEM | Wazuh agent (blue profile) — see [`siem/README.md`](../siem/README.md) |

`auditd` is the closest thing to a host-based detection pipeline here and is
documented (with its container capability caveats) in
`detections/audit-policy.md`. Wazuh file-integrity monitoring on the critical
share is the FIM analog.
