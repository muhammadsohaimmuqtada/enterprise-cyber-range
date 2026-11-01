FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Standalone SMB server. rsyslog routes vfs_full_audit output (local7) into
# /var/log/samba/audit.log (see rsyslog-audit.conf).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      samba \
      samba-vfs-modules \
      rsyslog \
      smbclient \
      iproute2 \
      procps \
 && rm -rf /var/lib/apt/lists/*

COPY smb.conf /etc/samba/smb.conf
COPY entrypoint.sh /usr/local/bin/filesrv-entrypoint.sh
RUN chmod +x /usr/local/bin/filesrv-entrypoint.sh

EXPOSE 139/tcp 445/tcp

ENTRYPOINT ["/usr/local/bin/filesrv-entrypoint.sh"]
