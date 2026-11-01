FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 \
      python3-pip \
      nginx \
      openssl \
      curl \
      ca-certificates \
      smbclient \
      cron \
      iproute2 \
      iputils-ping \
      netcat-openbsd \
      procps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED

COPY requirements.txt /opt/app/requirements.txt
RUN pip3 install --no-cache-dir -r /opt/app/requirements.txt

COPY app.py /opt/app/app.py
COPY nginx.conf /etc/nginx/sites-available/default
COPY entrypoint.sh /usr/local/bin/web01-entrypoint.sh

# /srv/notes/deployment.txt is the simulated weak point the red team discovers
# in phase 3: a provisioning note containing fake database credentials.
RUN chmod +x /usr/local/bin/web01-entrypoint.sh \
 && mkdir -p /var/log/app /var/log/nginx /etc/nginx/ssl /srv/notes \
 && printf '%s\n' \
      'Acme Intranet Portal - provisioning note' \
      'SIMULATED DATA - LAB ONLY. Nothing in this file is real.' \
      '' \
      'Portal database service account (fake):' \
      '  svc_web / Web#Svc2026!' \
      '' \
      'Deployed 2026-01-04 by infra-oncall (simulated).' \
      'If this note leaks, treat the web tier as compromised (scenario phase 3).' \
      > /srv/notes/deployment.txt \
 && openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout /etc/nginx/ssl/key.pem -out /etc/nginx/ssl/cert.pem \
      -subj "/CN=web01.lab.local/O=Acme (SIMULATED)/OU=Lab" \
 && chmod 600 /etc/nginx/ssl/key.pem

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/web01-entrypoint.sh"]
