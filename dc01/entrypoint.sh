#!/bin/bash
# dc01 entrypoint: provision the Samba AD DC on first boot, seed domain users,
# apply the hardened password policy (GPO-analog), start samba, and tail its
# log to stdout. State lives in the dc01_state / dc01_etc named volumes.
#
# Password policy commands are documented in /policies/password-policy.md.
# The SYSVOL/GPO analog and the Windows-event-log analog are documented in
# dc01/share-setup.md.
set -uo pipefail

DC_ADMIN_PASS="${DC_ADMIN_PASS:-Lab-Admin#2026!}"
ETC_SMB=/etc/samba/smb.conf
MARKER=/var/lib/samba/.provisioned

ip route replace default via 10.10.30.1 2>/dev/null \
  || echo "dc01: could not pin default route via fw (continuing)"

if [ ! -f "$ETC_SMB" ] && [ -f "$MARKER" ]; then
  echo "dc01: inconsistent state (provisioned volume present but /etc/samba/smb.conf missing)."
  echo "dc01: run 'make reset' to rebuild the domain from scratch."
  exit 1
fi

if [ ! -f "$ETC_SMB" ]; then
  echo "dc01: first boot - provisioning AD domain LAB.LOCAL (netbios LAB)"
  rm -f /run/samba/*.pid 2>/dev/null || true
  samba-tool domain provision \
    --realm=LAB.LOCAL \
    --domain=LAB \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --use-rfc2307 \
    --adminpass="$DC_ADMIN_PASS"

  echo "dc01: seeding domain users (under the default password policy - see policies/password-policy.md)"
  samba-tool user create jsmith 'Summer2026!'
  samba-tool user create mchen 'Welcome123!'

  echo "dc01: applying hardened password policy (GPO-analog)"
  samba-tool domain passwordsettings set --complexity=on
  samba-tool domain passwordsettings set --min-pwd-length=12
  samba-tool domain passwordsettings set --history-length=5

  echo "dc01: pinning the administrator password from DC_ADMIN_PASS"
  samba-tool user setpassword administrator --newpassword="$DC_ADMIN_PASS"

  touch "$MARKER"
  echo "dc01: provision complete"
else
  echo "dc01: existing domain state found - skipping provision"
fi

echo "dc01: starting samba"
samba -D

for i in $(seq 1 60); do
  if timeout 2 bash -c '</dev/tcp/127.0.0.1/445' 2>/dev/null; then
    echo "dc01: SMB answering on 445"
    break
  fi
  sleep 2
done

echo "dc01: refreshing DNS records"
samba_dnsupdate --verbose \
  || echo "dc01: samba_dnsupdate had nothing to update (or failed) - continuing"

echo "dc01: ready - realm LAB.LOCAL, domain netbios LAB, dc01.lab.local = 10.10.30.10"
echo "dc01: domain controller log follows"
exec tail -F /var/log/samba/log.samba
