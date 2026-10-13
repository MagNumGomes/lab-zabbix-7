FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini procps iproute2 \
    && curl -fsSL --retry 3 \
       https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb \
       -o /tmp/zabbix-release.deb \
    && dpkg -i /tmp/zabbix-release.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends zabbix-agent='1:7.0.*' zabbix-get='1:7.0.*' \
    && rm -rf /var/lib/apt/lists/* /tmp/zabbix-release.deb

COPY zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf

USER zabbix
EXPOSE 10050
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/sbin/zabbix_agentd", "--foreground", "--config", "/etc/zabbix/zabbix_agentd.conf"]
