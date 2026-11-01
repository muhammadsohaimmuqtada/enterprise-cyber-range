#!/bin/bash
# filesrv entrypoint: validate smb.conf, provision SMB accounts, generate the
# SIMULATED critical files if missing, start rsyslog (audit routing) + smbd,
# and tail the audit and smbd logs to stdout.
set -euo pipefail

ip route replace default via 10.10.30.1 2>/dev/null \
  || echo "filesrv: could not pin default route via fw (continuing)"

testparm -s /etc/samba/smb.conf >/dev/null 2>&1 \
  || { echo "filesrv: smb.conf failed testparm:"; testparm -s /etc/samba/smb.conf; exit 1; }

# --- SMB accounts (standalone server; usernames mirror the domain) ----------
create_user() { # name password
  local u="$1" p="$2"
  id "$u" >/dev/null 2>&1 || useradd --no-create-home --shell /usr/sbin/nologin "$u"
  printf '%s\n%s\n' "$p" "$p" | smbpasswd -s -a "$u" >/dev/null
  echo "filesrv: smb account ready: $u"
}
create_user fileshare 'F1leShare!2026'
create_user jsmith    'Summer2026!'
create_user mchen     'Welcome123!'
create_user svc_web   'Web#Svc2026!'

# --- Share trees -------------------------------------------------------------
mkdir -p /srv/samba/public /srv/samba/critical/passport-scans /var/log/samba
chown -R nobody:nogroup /srv/samba/public
chown -R fileshare:fileshare /srv/samba/critical
chmod 0777 /srv/samba/public
chmod 2770 /srv/samba/critical

# --- SIMULATED critical files (regenerated if missing) -----------------------
if [ ! -f /srv/samba/critical/q3-financials.csv ]; then
  cat > /srv/samba/critical/board-notes.txt <<'EOF'
ACME CORPORATION - BOARD NOTES
SIMULATED DATA - LAB ONLY. Nothing here is real.

Meeting 2026-01-12 (Q3 wrap):
- Approved widget line expansion ("Project Condor").
- Project Condor must not be discussed outside the board.
- Q4 review scheduled 2026-04-06.
- Legal: keep the passport-scan folder under the HR share restricted.
EOF

  cat > /srv/samba/critical/q3-financials.csv <<'EOF'
# SIMULATED DATA - LAB ONLY. All figures invented.
quarter,region,product,units,revenue_usd,margin_pct
Q3-2025,North,Widget Pro,1200,120000,0.32
Q3-2025,South,Widget Pro,940,94000,0.29
Q3-2025,East,Widget Pro,1105,110500,0.31
Q3-2025,West,Widget Pro,1310,131000,0.34
Q3-2025,North,Widget Lite,2200,110000,0.18
Q3-2025,South,Widget Lite,1810,90500,0.17
Q3-2025,East,Widget Lite,2050,102500,0.19
Q3-2025,West,Widget Lite,2440,122000,0.21
Q3-2025,North,Gearbox Mk2,330,99000,0.41
Q3-2025,South,Gearbox Mk2,290,87000,0.39
Q3-2025,East,Gearbox Mk2,310,93000,0.40
Q3-2025,West,Gearbox Mk2,402,120600,0.43
Q3-2025,North,Condor Prototype,5,250000,0.05
Q3-2025,South,Condor Prototype,0,0,0.00
Q3-2025,East,Condor Prototype,3,150000,0.06
Q3-2025,West,Condor Prototype,7,350000,0.04
Q3-2025,North,Service Contracts,150,45000,0.55
Q3-2025,South,Service Contracts,120,36000,0.52
Q3-2025,East,Service Contracts,140,42000,0.54
Q3-2025,West,Service Contracts,170,51000,0.57
EOF

  cat > /srv/samba/critical/passport-scans/README <<'EOF'
This folder SIMULATES an HR folder of identity documents.
SIMULATED DATA - LAB ONLY. No real personal information is stored here.

In the video, this is the kind of folder whose exfiltration turns a
technical breach into a reportable incident. The blue-team exercise is to
detect the read of this tree (SIEM rule 100920), not to protect real PII.
EOF

  chown -R fileshare:fileshare /srv/samba/critical
  echo "filesrv: SIMULATED critical files generated"
fi

if [ ! -f /srv/samba/public/old-runbook.txt ]; then
  cat > /srv/samba/public/old-runbook.txt <<'EOF'
ACME INFRASTRUCTURE - OLD RUNBOOK (kept on the public share for convenience)
SIMULATED DATA - LAB ONLY.

[Legacy] File server backup mount
  The nightly backup job still mounts //filesrv/critical using the service
  account below. Do not rotate without filing CHG-4471 (never filed).

    fileshare / F1leShare!2026

  Note (2025-11): the backup host was decommissioned; the mount was not.
EOF
  echo "filesrv: public decoy runbook generated"
fi

# --- Services -----------------------------------------------------------------
mkdir -p /var/run/rsyslogd
rsyslogd || echo "filesrv: rsyslog failed to start (audit file may be empty)"

smbd -D

for i in $(seq 1 60); do
  if timeout 2 bash -c '</dev/tcp/127.0.0.1/445' 2>/dev/null; then
    echo "filesrv: SMB answering on 445"
    break
  fi
  sleep 2
done

echo "filesrv: ready - shares: public (guest rw), critical (fileshare only)"
echo "filesrv: audit log follows (also mirrored to stdout)"
exec tail -F /var/log/samba/audit.log /var/log/samba/log.smbd
