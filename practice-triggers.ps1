$ErrorActionPreference='Stop'
. "$PSScriptRoot/configure-hosts.ps1" -FunctionsOnly
function Set-TestFile([string]$Action,[string]$Path){
    if($Action -eq 'remove'){docker compose exec -T linux-lab rm -f $Path}else{docker compose exec -T linux-lab touch $Path}
    if($LASTEXITCODE -ne 0){throw "Falha ao manipular $Path"}
}
function Wait-Trigger([string]$Id,[string]$Value){
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    do{
        $t=@(Invoke-ZabbixApi 'trigger.get' @{output=@('value','state','error');triggerids=@($Id)})[0]
        if($t.value -eq $Value -and $t.state -eq '0'){return}
        Start-Sleep -Seconds 2
    }while([DateTime]::UtcNow -lt $deadline)
    throw "Trigger $Id nao chegou a $Value. $($t.error)"
}
function Wait-Item([string]$Key,[string]$Value){
    $deadline=[DateTime]::UtcNow.AddSeconds(90)
    do{
        $item=@(Invoke-ZabbixApi 'item.get' @{output=@('lastvalue','lastclock');hostids=@($script:labHostId);filter=@{key_=@($Key)}})[0]
        if($item.lastvalue -eq $Value -and [long]$item.lastclock -gt 0){return}
        Start-Sleep -Seconds 2
    }while([DateTime]::UtcNow -lt $deadline)
    throw "Item $Key nao chegou a $Value."
}
Push-Location $PSScriptRoot
try{
    $script:token=Invoke-ZabbixApi 'user.login' @{username='Admin';password='zabbix'}
    $h=@(Invoke-ZabbixApi 'host.get' @{output=@('hostid');filter=@{host=@('linux-lab')}})[0]
    $script:labHostId=$h.hostid
    $triggers=@(Invoke-ZabbixApi 'trigger.get' @{output=@('triggerid','description','value');hostids=@($h.hostid);filter=@{description=@('NOC: Service is down','NOC: Too many service errors')};selectDependencies=@('triggerid')})
    $parent=@($triggers|Where-Object{$_.description -eq 'NOC: Service is down'})[0]
    $child=@($triggers|Where-Object{$_.description -eq 'NOC: Too many service errors'})[0]
    if(-not $parent -or -not $child -or $child.dependencies.triggerid -notcontains $parent.triggerid){throw 'Triggers ou dependencia nao configuradas.'}
    Set-TestFile remove /tmp/lab-service-down
    Set-TestFile remove /tmp/lab-service-errors
    Wait-Item lab.service.errors 0
    Wait-Trigger $parent.triggerid 0
    Wait-Trigger $child.triggerid 0

    Set-TestFile create /tmp/lab-service-errors
    Wait-Trigger $child.triggerid 1
    Write-Host 'OK: erro acima da macro gera problema.'
    Set-TestFile remove /tmp/lab-service-errors
    Wait-Trigger $child.triggerid 0
    Write-Host 'OK: remocao da causa recupera o problema.'

    Set-TestFile create /tmp/lab-service-down
    Wait-Trigger $parent.triggerid 1
    Set-TestFile create /tmp/lab-service-errors
    Wait-Item lab.service.errors 10
    $t=@(Invoke-ZabbixApi 'trigger.get' @{output=@('value');triggerids=@($child.triggerid)})[0]
    if($t.value -ne '0'){throw 'Trigger filha nao foi suprimida pela dependencia.'}
    Write-Host 'OK: com a trigger pai em problema, o erro dependente nao abre novo problema.'

    Set-TestFile remove /tmp/lab-service-errors
    Wait-Item lab.service.errors 0
    Set-TestFile remove /tmp/lab-service-down
    Wait-Trigger $parent.triggerid 0
    Write-Host 'OK: recuperacao final; ambiente de exercicio normalizado.'
}finally{
    docker compose exec -T linux-lab rm -f /tmp/lab-service-down /tmp/lab-service-errors
    if($script:token){try{$null=Invoke-ZabbixApi 'user.logout' @{} }catch{};$script:token=$null}
    Pop-Location
}
