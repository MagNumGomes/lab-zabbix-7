$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    docker compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Configuracao Compose invalida.' }
    docker compose up -d --build --wait --wait-timeout 600
    if ($LASTEXITCODE -ne 0) { throw 'Falha na inicializacao. Consulte docker compose logs --tail=100.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/healthcheck.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Healthcheck falhou.' }
    Write-Host 'Acesse http://localhost:8080 - usuario Admin / senha zabbix'
    Write-Host 'Para provisionar hosts, proxies e configurações do laboratório: .\complete-lab.ps1'
} finally { Pop-Location }
