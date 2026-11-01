FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Samba AD DC role: 'samba' provides samba-ad-dc + samba-tool; dsdb modules
# are needed by samba-tool database operations; bind9-dnsutils provides
# nsupdate for samba_dnsupdate.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      samba \
      samba-dsdb-modules \
      samba-vfs-modules \
      smbclient \
      krb5-user \
      bind9-dnsutils \
      iproute2 \
      procps \
      curl \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/dc01-entrypoint.sh
RUN chmod +x /usr/local/bin/dc01-entrypoint.sh

# Ports from the video's list that a Domain Controller owns:
#   53 dns | 88 kerberos | 135 rpc epmapper | 139 netbios-ssn
#   389 ldap | 445 smb | 464 kpasswd | 636 ldaps
EXPOSE 53/tcp 53/udp 88/tcp 88/udp 135/tcp 139/tcp 389/tcp 389/udp 445/tcp 464/tcp 464/udp 636/tcp

ENTRYPOINT ["/usr/local/bin/dc01-entrypoint.sh"]
