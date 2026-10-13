#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 600
bash ./healthcheck.sh
echo 'Acesse http://localhost:8080 - usuario Admin / senha zabbix'
