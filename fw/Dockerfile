FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      nftables \
      bash \
      iproute2 \
      curl \
      procps \
      grep \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/fw-entrypoint.sh
RUN chmod +x /usr/local/bin/fw-entrypoint.sh

# The ruleset itself is mounted read-only from fw/nftables.conf so it can be
# edited without rebuilding:  docker exec fw nft -f /fw/nftables.conf
ENTRYPOINT ["/usr/local/bin/fw-entrypoint.sh"]
