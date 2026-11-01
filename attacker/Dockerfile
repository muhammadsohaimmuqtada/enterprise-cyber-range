FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# Red team workstation. Tool -> video-term mapping lives in
# redteam-tools.md (also copied into /home/red).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      nmap \
      python3-impacket \
      netexec \
      smbclient \
      curl \
      dnsutils \
      openssh-client \
      metasploit-framework \
      tcpdump \
      jq \
      nano \
      sudo \
      python3 \
      iproute2 \
      procps \
      less \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash red \
 && echo 'red ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/red \
 && chmod 0440 /etc/sudoers.d/red

COPY entrypoint.sh /usr/local/bin/attacker-entrypoint.sh
COPY exfil-receiver.py /home/red/exfil-receiver.py
COPY redteam-tools.md /home/red/redteam-tools.md
RUN chmod +x /usr/local/bin/attacker-entrypoint.sh \
 && chown red:red /home/red/exfil-receiver.py /home/red/redteam-tools.md

USER red
WORKDIR /home/red

# Most tools that need raw sockets are run with sudo (passwordless for red).
ENTRYPOINT ["/usr/local/bin/attacker-entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
