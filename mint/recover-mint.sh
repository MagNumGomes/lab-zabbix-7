#!/usr/bin/env bash
set -euo pipefail
# Recuperacao controlada e comparacao de conectividade; executar no Mint com sudo.
[[ $EUID -eq 0 ]] || { echo 'Execute: sudo bash recover-mint.sh' >&2; exit 1; }
for binary in zabbix_agent2 zabbix_get python3 systemctl timeout; do
  command -v "$binary" >/dev/null || { echo "Comando necessario ausente: $binary" >&2; exit 1; }
done
started="$(date --iso-8601=seconds)"
lan_host="${ZABBIX_WINDOWS_IP:-192.168.0.9}"

echo '=== Validacao e reinicio controlado do Agent 2 ==='
zabbix_agent2 -T -c /etc/zabbix/zabbix_agent2.conf
systemctl restart zabbix-agent2
systemctl is-active zabbix-agent2
ready=false
for attempt in {1..15}; do
  if [[ "$(timeout 4 zabbix_get -s 127.0.0.1 -t 3 -k agent.ping 2>/dev/null || true)" == 1 ]]; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == true ]] || { journalctl -u zabbix-agent2 --since "$started" --no-pager; exit 1; }
# Permite ao coletor de CPU produzir as primeiras amostras apos o reinicio.
sleep 5

echo '=== Consultas locais depois do reinicio ==='
local_failures=0
for key in agent.ping system.uptime 'system.cpu.util[,user]' 'system.cpu.util[,guest_nice]'; do
  echo "Item: $key"
  if ! result="$(timeout 15 zabbix_get -s 127.0.0.1 -t 10 -k "$key" 2>&1)"; then
    local_failures=$((local_failures + 1))
  elif [[ "$result" == *ZBX_NOTSUPPORTED* ]]; then
    local_failures=$((local_failures + 1))
  fi
  printf '%s\n' "$result"
done

echo '=== Amostras TCP 10051: NAT VirtualBox e IP do Windows ==='
python3 - "$lan_host" <<'PY'
import concurrent.futures
import datetime
import socket
import sys
import time

targets = ['10.0.2.2', sys.argv[1]]
failures = dict.fromkeys(targets, 0)

def probe(host):
    start = time.monotonic()
    try:
        with socket.create_connection((host, 10051), timeout=3):
            pass
        return host, True, f'{(time.monotonic() - start) * 1000:.0f} ms'
    except OSError as exc:
        return host, False, str(exc)

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    for sample in range(1, 11):
        for host, ok, detail in pool.map(probe, targets):
            failures[host] += not ok
            print(f'{datetime.datetime.now().isoformat(timespec="seconds")} '
                  f'{sample}/10 {host}:10051 {"OK" if ok else "FALHA"} {detail}', flush=True)
        if sample < 10:
            time.sleep(2)

for host, count in failures.items():
    print(f'RESUMO {host}: {count}/10 falhas TCP')
print('Amostragem TCP nao comprova estabilidade continua nem envio do historico Zabbix.')
PY

echo '=== Mensagens do servico desde este reinicio ==='
journalctl -u zabbix-agent2 --since "$started" -n 40 --no-pager || true
echo '=== Ultimas mensagens de upload do Agent 2 (conferir os horarios) ==='
tail -n 30 /var/log/zabbix/zabbix_agent2.log || true
echo "Falhas nas consultas locais: $local_failures"
echo 'Envie esta saida. A recuperacao da coleta deve ser confirmada no server apos alguns minutos.'
(( local_failures == 0 ))
