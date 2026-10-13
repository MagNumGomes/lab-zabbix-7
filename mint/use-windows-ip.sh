#!/usr/bin/env bash
set -euo pipefail
# Troca o destino da coleta para o IP LAN do Windows, mantendo a VM em NAT.
[[ $EUID -eq 0 ]] || { echo 'Execute com sudo bash use-windows-ip.sh [IP_DO_WINDOWS].' >&2; exit 1; }
server="${1:-192.168.0.9}"
agent_conf=/etc/zabbix/zabbix_agent2.conf
proxy_conf=/etc/zabbix/zabbix_proxy.conf
for command in python3 zabbix_agent2 zabbix_proxy zabbix_get systemctl; do
  command -v "$command" >/dev/null || { echo "Comando ausente: $command" >&2; exit 1; }
done
[[ -f "$agent_conf" && -f "$proxy_conf" ]] || { echo 'Configuracao do agente/proxy nao encontrada.' >&2; exit 1; }

echo "=== Validando destino ${server}:10051 ==="
python3 - "$server" <<'PY'
import ipaddress
import socket
import sys
import time

host = str(ipaddress.IPv4Address(sys.argv[1]))
for attempt in range(3):
    with socket.create_connection((host, 10051), timeout=3):
        print(f'Conexao {attempt + 1}/3: OK', flush=True)
    if attempt < 2:
        time.sleep(1)
PY

mkdir -p /var/backups/zabbix-noc
backup="$(mktemp -d /var/backups/zabbix-noc/network-$(date +%Y%m%d-%H%M%S).XXXXXX)"
cp -a "$agent_conf" "$proxy_conf" "$backup/"
restore_configs() {
  cp -a "$backup/zabbix_agent2.conf" "$agent_conf"
  cp -a "$backup/zabbix_proxy.conf" "$proxy_conf"
  systemctl restart zabbix-agent2 zabbix-proxy || true
  echo "Configuracoes restauradas a partir de $backup" >&2
}

if ! python3 - "$server" "$agent_conf" "$proxy_conf" <<'PY'
from pathlib import Path
import re
import sys

server, agent, proxy = sys.argv[1:]
for filename, parameter, value in (
    (agent, 'ServerActive', server + ':10051'),
    (proxy, 'Server', server),
):
    path = Path(filename)
    lines = path.read_text().splitlines()
    lines = [line for line in lines if not re.match(r'^\s*' + parameter + r'\s*=', line)]
    path.write_text('\n'.join(lines) + f'\n{parameter}={value}\n')
PY
then
  restore_configs
  exit 1
fi

if ! zabbix_agent2 -T -c "$agent_conf"; then
  restore_configs
  exit 1
fi
if zabbix_proxy --help | grep -q -- '--test-config'; then
  if ! zabbix_proxy -T -c "$proxy_conf"; then restore_configs; exit 1; fi
fi
if ! systemctl restart zabbix-agent2 zabbix-proxy; then restore_configs; exit 1; fi
if ! systemctl is-active --quiet zabbix-agent2 || ! systemctl is-active --quiet zabbix-proxy; then
  restore_configs
  exit 1
fi

echo "Destino aplicado. Backup: $backup"
grep -E '^(Hostname|Server|ServerActive)=' "$agent_conf" "$proxy_conf"
echo '=== Aguardando inicializacao do coletor CPU (ate aproximadamente 90s) ==='
# A primeira consulta pode ativar o plugin antes de existir uma amostra de CPU.
# Exige duas rodadas validas para distinguir essa inicializacao de falha persistente.
consecutive=0
for attempt in {1..6}; do
  sleep 5
  round_ok=true
  for key in 'system.cpu.util[,user]' 'system.cpu.util[,guest_nice]'; do
    value="$(timeout 6 zabbix_get -s 127.0.0.1 -t 5 -k "$key" 2>&1 || true)"
    echo "Rodada $attempt / $key: $value"
    if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then round_ok=false; fi
  done
  if [[ "$round_ok" == true ]]; then consecutive=$((consecutive + 1)); else consecutive=0; fi
  if (( consecutive >= 2 )); then break; fi
done

echo '=== Leitura dos contadores pelo usuario do agente ==='
runuser -u zabbix -- head -n 3 /proc/stat || true
echo '=== Mensagens recentes ==='
tail -n 25 /var/log/zabbix/zabbix_agent2.log /var/log/zabbix/zabbix_proxy.log || true
if (( consecutive < 2 )); then
  echo 'Destino de rede atualizado, mas a coleta local de CPU ainda nao foi validada.' >&2
  exit 2
fi
echo 'OK: novo destino configurado e CPU respondeu em duas rodadas. Confirme frescor dos dados no server.'
