#!/usr/bin/env bash
set -uo pipefail
# Diagnostico somente leitura. Executar na VM: sudo bash diagnose-mint.sh
echo '=== Hora local e sincronizacao ==='
date --iso-8601=seconds
timedatectl status || true
echo '=== Hora HTTP do servidor Windows/Docker ==='
curl -fsSI --connect-timeout 3 --max-time 5 http://10.0.2.2:8080/ | grep -i '^date:' || true
echo '=== Recursos ==='
uptime
free -h
df -h / /var/lib/zabbix
echo '=== Servicos ==='
systemctl status zabbix-agent2 zabbix-proxy --no-pager || true
echo '=== Processos ==='
ps -eo pid,comm,%cpu,%mem,etime --sort=-%cpu | head -n 15
echo '=== Configuracao de filas, destino e timeout (sem credenciais) ==='
grep -HE '^(Server|ServerActive|Hostname|Timeout|BufferSend|BufferSize|EnablePersistentBuffer|PersistentBufferPeriod|RefreshActiveChecks|ForceActiveChecksOnStart|Plugins\.[^.]+\.System\.Capacity)=' \
  /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.d/*.conf 2>/dev/null || true
grep -E '^(Server|Hostname|ProxyMode|ProxyConfigFrequency|DataSenderFrequency|Timeout|StartPollers|StartAgentPollers)=' \
  /etc/zabbix/zabbix_proxy.conf || true
echo '=== Consultas locais ao agente ==='
for key in agent.ping system.localtime 'system.cpu.util[,guest_nice]' system.uptime; do
  echo "Item: $key"
  timeout 15 zabbix_get -s 127.0.0.1 -t 10 -k "$key" || true
done
echo '=== Ultimas mensagens ==='
journalctl -u zabbix-agent2 -u zabbix-proxy -n 60 --no-pager || true
tail -n 60 /var/log/zabbix/zabbix_agent2.log /var/log/zabbix/zabbix_proxy.log 2>/dev/null || true
