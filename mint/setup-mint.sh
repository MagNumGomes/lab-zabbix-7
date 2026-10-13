#!/usr/bin/env bash
set -euo pipefail

# Executar no Linux Mint baseado em Ubuntu: sudo bash setup-mint.sh
[[ $EUID -eq 0 ]] || { echo 'Execute com sudo bash setup-mint.sh.' >&2; exit 1; }
[[ -r /etc/upstream-release/lsb-release ]] || { echo 'Este script requer Linux Mint baseado em Ubuntu.' >&2; exit 1; }
source /etc/upstream-release/lsb-release
case "$DISTRIB_RELEASE" in
  20.04|22.04|24.04) ;;
  *) echo "Base Ubuntu ainda nao validada por este script: $DISTRIB_RELEASE" >&2; exit 1 ;;
esac

# IP LAN deste Windows: o alias NAT 10.0.2.2 apresentou timeouts nos testes.
# Em outra rede/apos mudar DHCP, informe ZABBIX_LAB_SERVER explicitamente.
server="${ZABBIX_LAB_SERVER:-192.168.0.9}"
timeout 5 bash -c 'exec 3<>/dev/tcp/"$1"/10051' _ "$server" || {
  echo "Nao foi possivel acessar ${server}:10051. Inicie o Docker Desktop e a stack." >&2
  exit 1
}

backup="/var/backups/zabbix-noc/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for file in /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_proxy.conf; do
  if [[ -f "$file" ]]; then cp -a "$file" "$backup/"; fi
done

apt-get update
apt-get install -y ca-certificates curl
curl -fsSL --retry 3 \
  "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu${DISTRIB_RELEASE}_all.deb" \
  -o /tmp/zabbix-release-noc.deb
dpkg -i /tmp/zabbix-release-noc.deb
apt-get update
apt-get install -y zabbix-agent2='1:7.0.*' zabbix-proxy-sqlite3='1:7.0.*' zabbix-get='1:7.0.*' sqlite3

install -d -o zabbix -g zabbix /var/lib/zabbix /var/log/zabbix /run/zabbix
cat > /etc/zabbix/zabbix_proxy.conf <<EOF
ProxyMode=0
Server=${server}
Hostname=mint-proxy
LogFile=/var/log/zabbix/zabbix_proxy.log
LogFileSize=10
PidFile=/run/zabbix/zabbix_proxy.pid
SocketDir=/run/zabbix
DBName=/var/lib/zabbix/mint-proxy.db
ProxyConfigFrequency=10
DataSenderFrequency=1
Timeout=10
EOF
chown root:zabbix /etc/zabbix/zabbix_proxy.conf
chmod 640 /etc/zabbix/zabbix_proxy.conf

# O proxy cria o schema SQLite no primeiro inicio quando o arquivo nao existe.
# Atualiza parametros sem duplicar e preserva as demais configuracoes do agente.
set_agent_parameter() {
  local name="$1" value="$2"
  sed -i "/^[[:space:]]*${name}[[:space:]]*=/d" /etc/zabbix/zabbix_agent2.conf
  printf '%s=%s\n' "$name" "$value" >> /etc/zabbix/zabbix_agent2.conf
}
set_agent_parameter Server 127.0.0.1
set_agent_parameter ServerActive "${server}:10051"
set_agent_parameter Hostname linux-mint

install -d /etc/zabbix/zabbix_agent2.d
include='Include=/etc/zabbix/zabbix_agent2.d/noc-lab.conf'
if ! grep -Eq '^Include=/etc/zabbix/zabbix_agent2\.d/(\*|\*\.conf|noc-lab\.conf)[[:space:]]*$' /etc/zabbix/zabbix_agent2.conf; then
  printf '%s\n' "$include" >> /etc/zabbix/zabbix_agent2.conf
fi
cat > /etc/zabbix/zabbix_agent2.d/noc-lab.conf <<'EOF'
UserParameter=lab.service.up,test ! -f /tmp/lab-service-down && echo 1 || echo 0
UserParameter=lab.service.errors,test ! -f /tmp/lab-service-errors && echo 0 || echo 10
UserParameter=lab.key.allowed,echo 1
UserParameter=lab.key.blocked,echo 1
AllowKey=lab.key.allowed
DenyKey=lab.key.blocked
EOF

systemctl enable zabbix-agent2 zabbix-proxy
systemctl restart zabbix-agent2 zabbix-proxy
systemctl is-active zabbix-agent2 zabbix-proxy
zabbix_get -s 127.0.0.1 -k agent.ping
zabbix_get -s 127.0.0.1 -k lab.key.allowed
echo 'A chave abaixo deve ser recusada por DenyKey:'
zabbix_get -s 127.0.0.1 -k lab.key.blocked || true
echo "OK. Backup das configuracoes: $backup"
echo 'Hosts no painel: Linux Mint (VirtualBox), para checks ativos diretos; Linux Mint via Proxy, para passivos via mint-proxy.'
echo 'Aguarde alguns minutos e confira Latest data. Se houver erro: sudo tail -n 50 /var/log/zabbix/zabbix_proxy.log'
