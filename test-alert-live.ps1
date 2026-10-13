. "$PSScriptRoot/configure-hosts.ps1" -FunctionsOnly
Push-Location $PSScriptRoot
try {
    $script:token = Invoke-ZabbixApi 'user.login' @{username='Admin';password='zabbix'}
    $h = @(Invoke-ZabbixApi 'host.get' @{output=@('hostid');filter=@{host=@('linux-lab')}})[0]
    $parent = @(Invoke-ZabbixApi 'trigger.get' @{output=@('triggerid','value');hostids=@($h.hostid);filter=@{description=@('NOC: Service is down')}})[0]
    $act = @(Invoke-ZabbixApi 'action.get' @{output=@('actionid');filter=@{name=@('NOC: avisa queda do servico didatico')}})[0]

    docker compose exec -T linux-lab rm -f /tmp/lab-service-down /tmp/lab-service-errors | Out-Null
    $t0 = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    Write-Host 'Gerando falha didatica (lab.service.up -> 0)...'
    docker compose exec -T linux-lab touch /tmp/lab-service-down | Out-Null

    # Aguarda problema do evento.
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $problem = $null
    do {
        Start-Sleep -Seconds 5
        $problem = @(Invoke-ZabbixApi 'problem.get' @{output=@('eventid','clock','name');hostids=@($h.hostid);filter=@{name=@('NOC: Service is down')}})
    } while (-not $problem.Count -and [DateTime]::UtcNow -lt $deadline)
    if (-not $problem.Count) { throw 'Problema NOC nao apareceu em 120s.' }
    Write-Host "OK: problema aberto (evento $($problem[0].eventid))."

    # Aguarda alerta da acao de exemplo.
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $alerts = @()
    do {
        Start-Sleep -Seconds 5
        $alerts = @(Invoke-ZabbixApi 'alert.get' @{output=@('alertid','clock','sendto','subject','status','error','mediatypeid');actionids=@($act.actionid);filter=@{}})
        $alerts = @($alerts | Where-Object { [long]$_.clock -ge $t0 })
    } while (-not $alerts.Count -and [DateTime]::UtcNow -lt $deadline)
    if (-not $alerts.Count) { throw 'Nenhum alerta da acao NOC em 120s.' }
    $mt = @(Invoke-ZabbixApi 'mediatype.get' @{output=@('mediatypeid','name')})
    foreach ($a in $alerts) {
        $mName = (@($mt | Where-Object { $_.mediatypeid -eq $a.mediatypeid })[0]).name
        $st = @{ '0' = 'nao enviado'; '1' = 'enviado'; '2' = 'falha' }[$a.status]
        Write-Host "Alerta $($a.alertid): midia=$mName para=$($a.sendto) status=$st erro=$($a.error)"
    }
    $sent = @($alerts | Where-Object { $_.status -eq '1' })
    if (-not $sent.Count) { throw 'Acao disparou, mas nenhum alerta com entrega confirmada.' }
    Write-Host 'OK: alerta de exemplo entregue (webhook). Veja tambem Reports > Action log.'

    Write-Host 'Limpando falha e aguardando recuperacao...'
    docker compose exec -T linux-lab rm -f /tmp/lab-service-down /tmp/lab-service-errors | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    do {
        Start-Sleep -Seconds 5
        $t = @(Invoke-ZabbixApi 'trigger.get' @{output=@('value');triggerids=@($parent.triggerid)})[0]
    } while ($t.value -ne '0' -and [DateTime]::UtcNow -lt $deadline)
    if ($t.value -ne '0') { throw 'Trigger nao recuperou em 120s.' }
    Write-Host 'OK: recuperacao confirmada; notificacao de recovery enviada pela acao.'
} finally {
    docker compose exec -T linux-lab rm -f /tmp/lab-service-down /tmp/lab-service-errors | Out-Null
    if ($script:token) { try { $null = Invoke-ZabbixApi 'user.logout' @{} } catch {}; $script:token = $null }
    Pop-Location
}
