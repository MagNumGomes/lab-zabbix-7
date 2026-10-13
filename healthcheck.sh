#!/usr/bin/env bash
set -euo pipefail

# Uso: bash healthcheck.sh [host] [tentativas] [intervalo_em_segundos]
host="${1:-localhost}"
attempts="${2:-60}"
interval="${3:-5}"

for dependency in curl timeout; do
  command -v "$dependency" >/dev/null || { echo "ERRO: instale $dependency." >&2; exit 2; }
done
[[ "$attempts" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[0-9]+$ ]] || {
  echo 'ERRO: tentativas deve ser inteiro positivo e intervalo inteiro nao negativo.' >&2
  exit 2
}

for ((attempt=1; attempt<=attempts; attempt++)); do
  http_code="$(curl --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 3 --max-time 5 "http://${host}:8080/" 2>/dev/null)" || http_code=000
  tcp_ok=false
  if timeout 5 bash -c 'exec 3<>/dev/tcp/"$1"/10051' _ "$host" 2>/dev/null; then
    tcp_ok=true
  fi
  if [[ "$http_code" == 200 && "$tcp_ok" == true ]]; then
    echo "OK: http://${host}:8080/ retornou HTTP 200; TCP ${host}:10051 acessivel."
    exit 0
  fi
  echo "Aguardando ($attempt/$attempts): HTTP=$http_code; TCP 10051=$tcp_ok"
  if (( attempt < attempts )); then sleep "$interval"; fi
done

echo 'ERRO: laboratorio indisponivel. Execute docker compose ps e docker compose logs --tail=100.' >&2
exit 1
