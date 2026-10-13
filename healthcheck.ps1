param(
    [string]$TargetHost = 'localhost',
    [ValidateRange(1, 3600)][int]$Attempts = 60,
    [ValidateRange(0, 3600)][int]$IntervalSeconds = 5
)

$ErrorActionPreference = 'Stop'
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $httpCode = 0
    $tcpOk = $false
    try {
        $response = Invoke-WebRequest -Uri "http://${TargetHost}:8080/" -UseBasicParsing -TimeoutSec 5
        $httpCode = [int]$response.StatusCode
    } catch { }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.ConnectAsync($TargetHost, 10051)
        $tcpOk = $pending.Wait(5000) -and $client.Connected
    } catch { } finally { $client.Dispose() }

    if ($httpCode -eq 200 -and $tcpOk) {
        Write-Host "OK: http://${TargetHost}:8080/ retornou HTTP 200; TCP ${TargetHost}:10051 acessivel."
        exit 0
    }
    Write-Host "Aguardando ($attempt/$Attempts): HTTP=$httpCode; TCP 10051=$tcpOk"
    if ($attempt -lt $Attempts) { Start-Sleep -Seconds $IntervalSeconds }
}
Write-Error 'Laboratorio indisponivel. Execute docker compose ps e docker compose logs --tail=100.'
exit 1
