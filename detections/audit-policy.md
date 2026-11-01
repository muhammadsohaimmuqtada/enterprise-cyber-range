# Audit policy — host-level detection analog (auditd + samba full_audit)

> Reference configuration — authorized lab use only.

This range has no commercial EDR. The host-level analog is auditd for
process and file telemetry, plus Samba's `vfs_full_audit` for share access.
This document is the audit reference for `web01` and `filesrv`.

## auditd rules for the range

Contents for `/etc/audit/rules.d/range.rules` on **filesrv**:

```conf
# Sensitive SIMULATED data tree (board notes, financials, passport-scans)
-w /srv/samba/critical -p rwa -k range-critical-files
# Public share (decoy runbook reads explain the escalation chain)
-w /srv/samba/public -p wa -k range-public-share
# Everything executed (the Sysmon/EDR execve analog)
-a always,exit -F arch=b64 -S execve -k range-exec
-a always,exit -F arch=b32 -S execve -k range-exec
```

Contents for **web01**:

```conf
# The provisioning note with the fake svc_web credentials (phase 3 reads it)
-w /srv/notes -p rwa -k range-provisioning-notes
# Application logs (the files phase 7 truncates)
-w /var/log/app -p wa -k range-app-logs
# Everything executed (the web shell's commands become events)
-a always,exit -F arch=b64 -S execve -k range-exec
-a always,exit -F arch=b32 -S execve -k range-exec
```

Enable on a host (requires `CAP_AUDIT_CONTROL` in a container — see caveat):

```bash
apt-get install -y auditd
# install the rules above, then:
augenrules --load
auditctl -l          # verify the rules are active
```

**Container caveat:** auditd talks to the kernel's audit subsystem, which
needs `CAP_AUDIT_CONTROL` (rule loading) and `CAP_AUDIT_READ` — beyond
Docker's default capability set. On hosts where the kernel audit queue is
shared and restricted, in-container auditd may not load rules. That is why
the range ships this policy as *documentation* and relies on the always-on
analogs below for the runnable scenario.

## samba full_audit (active in the range)

Configured in `filesrv/smb.conf`; writes to `/var/log/samba/audit.log` via
rsyslog (facility local7, see `filesrv/rsyslog-audit.conf`):

```
vfs objects = full_audit
full_audit:prefix = %u|%I|%S
full_audit:success = connect, disconnect, opendir, mkdir, rmdir, open, close, unlink, rename, pwrite
full_audit:failure = none
full_audit:facility = local7
full_audit:priority = notice
```

Line shape (the SIEM's 100920/100921/100940 rules key on this):

```
Jan 15 03:04:11 filesrv smbd_audit: fileshare|10.10.10.5|critical|open|ok|q3-financials.csv
```

This is the Windows 4663 (file object access) analog: who, from where, on
which share, doing what, to which file.

## What each source contributes to the EDR picture

| Detection need (video) | Source in this range |
|---|---|
| Process creation (who ran what) | auditd `execve` (reference) / web01's `CONSOLE-EXEC` app-log lines (active) |
| Sensitive file access | samba `full_audit` on `critical` (active) / auditd watch on `/srv/samba/critical` (reference) |
| Log tampering | auditd watch on `/var/log/app` (reference); stdout copies in the container runtime (active, defeats the truncate in phase 7) |
| File-integrity (FIM) | Wazuh syscheck on `/srv/critical` with an installed agent — see `siem/README.md` |
| Identity / auth events | sssd and samba auth lines on dc01/ws (`dc01/share-setup.md` maps them to Windows event IDs) |
