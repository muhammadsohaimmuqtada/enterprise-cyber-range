FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Debian "client OS" analog: realmd/sssd join LAB.LOCAL against dc01 on first
# boot. dbus is required because 'realm' talks to the realmd daemon over the
# system bus (there is no systemd in the container).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      realmd \
      sssd \
      sssd-tools \
      sssd-ad \
      adcli \
      krb5-user \
      libpam-sss \
      libnss-sss \
      dbus \
      iproute2 \
      procps \
      curl \
      less \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/ws-entrypoint.sh
RUN chmod +x /usr/local/bin/ws-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ws-entrypoint.sh"]
