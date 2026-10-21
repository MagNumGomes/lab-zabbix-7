param([switch]$RequireMintProxy, [switch]$RequireMfaEnrollment)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/configure-hosts.ps1" -FunctionsOnly
$secrets=Get-Content "$PSScriptRoot/credentials.local.json" -Raw | ConvertFrom-Json
$failures=New-Object 'System.Collections.Generic.List[string]'
$pending=New-Object 'System.Collections.Generic.List[string]'
$report=New-Object 'System.Collections.Generic.List[object]'
function Assert-Lab([bool]$Condition,[string]$Message){
    if($Condition){Write-Host "OK: $Message"}else{$failures.Add($Message);Write-Warning $Message}
}
try {
    Push-Location $PSScriptRoot
    $services=@(docker compose ps --format json | ForEach-Object {$_ | ConvertFrom-Json})
    Assert-Lab ($LASTEXITCODE -eq 0 -and $services.Count -eq 7 -and @($services|Where-Object{$_.Health -ne 'healthy'}).Count -eq 0) 'Sete containers saudaveis'
    $windows=Get-Service 'Zabbix Agent' -ErrorAction SilentlyContinue
    Assert-Lab ($null -ne $windows -and $windows.Status -eq 'Running') 'Servico Windows Zabbix Agent em execucao'
    $script:token=Invoke-ZabbixApi 'user.login' @{username='Admin';password='zabbix'}
    $expectedHosts=@('Zabbix server','linux-lab','linux-mint','windows-host','mysql-lab','linux-mint-proxy')
    $hostsFound=@(Invoke-ZabbixApi 'host.get' @{output=@('hostid','host','monitored_by','proxyid','status');filter=@{host=$expectedHosts}})
    foreach($name in $expectedHosts){
        Assert-Lab (@($hostsFound|Where-Object{$_.host -eq $name -and $_.status -eq '0'}).Count -eq 1) "Host $name existe e esta habilitado"
    }
    $proxies=@(Invoke-ZabbixApi 'proxy.get' @{output=@('proxyid','name','lastaccess','version')})
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $mintProxyReady=$false
    foreach($name in @('lab-proxy','mint-proxy')){
        $p=@($proxies|Where-Object{$_.name -eq $name})
        $ready=$p.Count -eq 1 -and [long]$p[0].lastaccess -gt 0 -and ($now-[long]$p[0].lastaccess) -lt 120
        if($name -eq 'mint-proxy'){$mintProxyReady=$ready}
        if($name -eq 'mint-proxy' -and -not $ready -and -not $RequireMintProxy){
            $pending.Add('Executar setup-mint.sh na VM: mint-proxy ainda sem comunicacao')
        }else{Assert-Lab $ready "Proxy $name comunicando recentemente"}
    }
    foreach($h in $hostsFound){
        if($h.host -eq 'linux-mint-proxy' -and -not $mintProxyReady -and -not $RequireMintProxy){continue}
        $key=if($h.host -eq 'mysql-lab'){'mysql.uptime'}else{'system.uptime'}
        $items=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid','key_','lastclock','lastvalue','state','error');hostids=@($h.hostid);filter=@{key_=@($key)}})
        $fresh=$items.Count -eq 1 -and $items[0].state -eq '0' -and [long]$items[0].lastclock -gt 0 -and ($now-[long]$items[0].lastclock) -lt 180
        Assert-Lab $fresh "Coleta recente $($h.host) / $key"
        if($items.Count){$report.Add(@{host=$h.host;key=$key;value=$items[0].lastvalue;ageSeconds=($now-[long]$items[0].lastclock);error=$items[0].error})}
        $unsupported=@(Invoke-ZabbixApi 'item.get' @{output=@('key_','error');hostids=@($h.hostid);filter=@{status=0;state=1}})
        $warmup=@()
        $calculationErrors=@($unsupported|Where-Object{$_.key_ -eq 'mysql.innodb_log_file_size' -and $_.error -match 'not enough data'})
        if($calculationErrors.Count){
            $source=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid','value_type');hostids=@($h.hostid);filter=@{key_=@('mysql.innodb_os_log_written')}})
            if($source.Count -eq 1){
                $older=@(Invoke-ZabbixApi 'history.get' @{output=@('clock');history=[int]$source[0].value_type;itemids=@($source[0].itemid);time_till=($now-3600);limit=1})
                if(-not $older.Count){$warmup=$calculationErrors}
            }
        }
        foreach($item in $warmup){$pending.Add("$($h.host) / $($item.key_): calculo precisa de uma hora de historico")}
        $errors=@($unsupported|Where-Object{$_ -notin $warmup})
        Assert-Lab ($errors.Count -eq 0) "$($h.host): nenhum erro de coleta (exceto calculo inicial de 1h)"
        if($errors.Count){$errors|Format-Table -Wrap}
    }
    $linux=@($hostsFound|Where-Object{$_.host -eq 'linux-lab'})[0]
    $proxy=@($proxies|Where-Object{$_.name -eq 'lab-proxy'})[0]
    Assert-Lab ($linux.monitored_by -eq '1' -and $linux.proxyid -eq $proxy.proxyid) 'linux-lab associado ao Proxy Docker'
    $mint=@($hostsFound|Where-Object{$_.host -eq 'linux-mint-proxy'})
    $mintProxy=@($proxies|Where-Object{$_.name -eq 'mint-proxy'})
    Assert-Lab ($mint.Count -eq 1 -and $mintProxy.Count -eq 1 -and $mint[0].monitored_by -eq '1' -and $mint[0].proxyid -eq $mintProxy[0].proxyid) 'Mint passivo associado ao proxy nativo correto'
    foreach($key in @('lab.service.up','lab.service.errors','lab.key.allowed','vfs.file.size[/etc/hostname]')){
        $items=@(Invoke-ZabbixApi 'item.get' @{output=@('lastclock','state','error');hostids=@($linux.hostid);filter=@{key_=@($key)}})
        Assert-Lab ($items.Count -eq 1 -and $items[0].state -eq '0' -and [long]$items[0].lastclock -gt 0 -and ($now-[long]$items[0].lastclock) -lt 180) "Item didatico com coleta recente: $key"
    }
    $authentication=Invoke-ZabbixApi 'authentication.get' @{output=@('mfa_status','mfaid')}
    $mfas=@(Invoke-ZabbixApi 'mfa.get' @{output=@('mfaid','name','type','hash_function','code_length')})
    $mfaUsers=@(Invoke-ZabbixApi 'user.get' @{output=@('userid');filter=@{username=@('lab.mfa')};selectUsrgrps=@('usrgrpid')})
    $mfaGroups=@(Invoke-ZabbixApi 'usergroup.get' @{output=@('usrgrpid','mfa_status','mfaid');filter=@{name=@('NOC MFA')}})
    $totp=@($mfas|Where-Object{$_.name -eq 'NOC TOTP' -and $_.type -eq '1' -and $_.hash_function -eq '1' -and $_.code_length -eq '6'})
    Assert-Lab ($authentication.mfa_status -eq '1' -and $totp.Count -eq 1 -and $mfaUsers.Count -eq 1 -and $mfaGroups.Count -eq 1 -and $mfaGroups[0].mfa_status -eq '1' -and $mfaGroups[0].mfaid -eq $totp[0].mfaid -and $mfaUsers[0].usrgrps.usrgrpid -contains $mfaGroups[0].usrgrpid) 'TOTP configurado e associado corretamente a lab.mfa'
    # Leitura apenas do estado de confirmacao, sem consultar a chave secreta TOTP.
    $mfaQuery=@'
export MYSQL_PWD="$MYSQL_PASSWORD"
mysql -u "$MYSQL_USER" -D "$MYSQL_DATABASE" -Nse "SELECT COUNT(*) FROM mfa_totp_secret s JOIN users u ON u.userid=s.userid WHERE u.username='lab.mfa' AND s.status=1;"
'@
    $confirmed=$mfaQuery | docker compose exec -T mysql sh
    if($LASTEXITCODE -ne 0){throw 'Nao foi possivel consultar o estado do vinculo TOTP.'}
    $enrolled=[int]($confirmed|Select-Object -Last 1) -gt 0
    if($RequireMfaEnrollment){Assert-Lab $enrolled 'Autenticador pessoal de lab.mfa vinculado e confirmado'}
    if(-not $enrolled){$pending.Add('MFA: lab.mfa ainda sem autenticador vinculado/confirmado')}
    $null=Invoke-ZabbixApi 'user.logout' @{}
    $script:token=$null

    # Verificacao real dos direitos, usando cada conta criada.
    foreach($username in @('lab.user','lab.admin','lab.super','lab.noc')){
        $script:token=Invoke-ZabbixApi 'user.login' @{username=$username;password=$secrets.$username}
        $visible=@(Invoke-ZabbixApi 'host.get' @{output=@('hostid','host','name')})
        $names=@($visible|ForEach-Object{$_.host})
        Assert-Lab ($names -contains 'linux-lab') "$username consegue visualizar Linux"
        if($username -in @('lab.user','lab.noc')){
            Assert-Lab ($names -notcontains 'windows-host' -and $names -notcontains 'mysql-lab' -and $names -notcontains 'Zabbix server') "$username limitado ao grupo Linux"
        }
        if($username -eq 'lab.user'){
            $denied=$false
            try{$null=Invoke-ZabbixApi 'host.update' @{hostid=$linux.hostid;name='linux-lab'}}catch{
                if($_ -match 'permission|Not authorized|not allowed'){$denied=$true}else{throw}
            }
            Assert-Lab $denied 'Usuario somente leitura nao pode alterar host'
        }
        if($username -eq 'lab.admin'){
            $editable=@(Invoke-ZabbixApi 'host.get' @{output=@('host');editable=$true})
            $editableNames=@($editable|ForEach-Object{$_.host})
            Assert-Lab ($editableNames -contains 'windows-host' -and $editableNames -contains 'mysql-lab' -and $editableNames -notcontains 'Zabbix server') 'Admin gerencia grupos do laboratório, sem acesso administrativo ao host de infraestrutura'
        }
        if($username -eq 'lab.super'){Assert-Lab ($names -contains 'Zabbix server') 'Super admin acessa infraestrutura'}
        if($username -eq 'lab.noc'){
            $denied=$false
            try{$null=Invoke-ZabbixApi 'role.get' @{output=@('name')}}catch{
                if($_ -match 'permission|Not authorized|not allowed'){$denied=$true}else{throw}
            }
            Assert-Lab $denied 'Role NOC bloqueia API fora da lista permitida'
        }
        $null=Invoke-ZabbixApi 'user.logout' @{}
        $script:token=$null
    }
    $result=@{checkedAt=[DateTimeOffset]::Now.ToString('o');failures=@($failures.ToArray());pending=@($pending.ToArray());metrics=@($report.ToArray())}
    [IO.File]::WriteAllText("$PSScriptRoot/validation.local.json",($result|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
    foreach($entry in $pending){Write-Host "PENDENTE: $entry"}
    Write-Host 'MFA: vinculacao do autenticador e login interativo sao feitos pelo usuario.'
    if($failures.Count){throw "$($failures.Count) verificacoes falharam. Consulte validation.local.json."}
    Write-Host 'Validacoes locais concluidas.'
} finally {
    if($script:token){try{$null=Invoke-ZabbixApi 'user.logout' @{} }catch{};$script:token=$null}
    Pop-Location
}
