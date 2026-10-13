#!/usr/bin/env bash
set -euo pipefail
# No Windows: Get-Content -Raw .\practice-agent-root.sh | docker compose exec -T -u root linux-lab bash -s
# No Mint com zabbix_agentd instalado: sudo bash practice-agent-root.sh
[[ $EUID -eq 0 ]] || { echo 'Execute como root para esta pratica.' >&2; exit 1; }
workdir="$(mktemp -d /tmp/noc-root.XXXXXX)"
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$workdir"
}
trap cleanup EXIT
cat > "$workdir/agent.conf" <<EOF
PidFile=${workdir}/agent.pid
LogType=console
Server=127.0.0.1
Hostname=noc-root-practice
ListenIP=127.0.0.1
ListenPort=10060
StartAgents=1
AllowRoot=1
User=root
UserParameter=lab.uid,id -u
EOF
zabbix_agentd -f -c "$workdir/agent.conf" > "$workdir/agent.log" 2>&1 &
pid=$!
for attempt in {1..10}; do
  if ! kill -0 "$pid" 2>/dev/null; then cat "$workdir/agent.log"; exit 1; fi
  uid_value="$(zabbix_get -s 127.0.0.1 -p 10060 -k lab.uid 2>/dev/null || true)"
  if [[ "$uid_value" == 0 ]]; then
    echo 'OK: agente classico executado como root, lab.uid=0. Instancia temporaria sera encerrada.'
    exit 0
  fi
  sleep 1
done
cat "$workdir/agent.log"
echo 'Falha ao confirmar UID 0.' >&2
exit 1
