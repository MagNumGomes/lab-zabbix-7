param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$AdminPassword = 'zabbix'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

# Inicializacao da base e reutilizacao das funcoes da API.
. "$PSScriptRoot/configure-hosts.ps1" -BaseUrl $BaseUrl -Username Admin -Password $AdminPassword
$secretPath = Join-Path $PSScriptRoot 'credentials.local.json'
$secrets = @{}
if (Test-Path $secretPath) {
    (Get-Content $secretPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $secrets[$_.Name] = $_.Value }
}
function Get-LabSecret([string]$Name) {
    if (-not $secrets.ContainsKey($Name)) {
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 24
        $rng.GetBytes($bytes)
        $rng.Dispose()
        $secrets[$Name] = 'Z7!' + ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
        [IO.File]::WriteAllText($secretPath, ($secrets | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    return $secrets[$Name]
}
function Ensure-NamedObject([string]$Kind, [string]$Name, [hashtable]$Properties = @{}) {
    if ($Kind -eq 'mfa') {
        $found = @(Invoke-ZabbixApi 'mfa.get' @{output='extend'} | Where-Object {$_.name -eq $Name})
    } else {
        $found = @(Invoke-ZabbixApi "$Kind.get" @{ output = 'extend'; filter = @{ name = @($Name) } })
    }
    $idField = switch ($Kind) {
        'hostgroup' { 'groupid' }; 'templategroup' { 'groupid' }; 'proxy' { 'proxyid' }
        'role' { 'roleid' }; 'usergroup' { 'usrgrpid' }; 'mfa' { 'mfaid' }
    }
    if (-not $idField) { throw "Tipo nao suportado: $Kind" }
    if ($found.Count -gt 0) {
        if ($Kind -eq 'role' -and $Properties.Count) {
            $update = @{roleid=$found[0].roleid}
            foreach($key in $Properties.Keys){$update[$key]=$Properties[$key]}
            $null=Invoke-ZabbixApi 'role.update' $update
        }
        return [string]$found[0].$idField
    }
    $payload = @{ name = $Name }
    foreach ($key in $Properties.Keys) { $payload[$key] = $Properties[$key] }
    $result = Invoke-ZabbixApi "$Kind.create" $payload
    return [string]$result."${idField}s"[0]
}
function Get-LabHost([string]$Name) {
    $found = @(Invoke-ZabbixApi 'host.get' @{
        output = @('hostid', 'host'); filter = @{ host = @($Name) }
        selectHostGroups = @('groupid'); selectParentTemplates = @('templateid'); selectMacros = 'extend'
    })
    if ($found.Count -ne 1) { throw "Host nao encontrado: $Name" }
    return $found[0]
}
function Add-HostGroup([string]$Name, [string]$GroupId) {
    $hostObject = Get-LabHost $Name
    $ids = @(@($hostObject.hostgroups | ForEach-Object { $_.groupid }) + @($GroupId) | Select-Object -Unique)
    $null = Invoke-ZabbixApi 'host.update' @{hostid=$hostObject.hostid; groups=@($ids | ForEach-Object {@{groupid=$_}})}
}
function Ensure-ActiveHost([string]$Name, [string]$VisibleName, [string]$Template, [string]$GroupId) {
    $found = @(Invoke-ZabbixApi 'host.get' @{output=@('hostid');filter=@{host=@($Name)}})
    if ($found.Count -eq 0) {
        $templateObject = @(Invoke-ZabbixApi 'template.get' @{output=@('templateid');filter=@{host=@($Template)}})
        if ($templateObject.Count -ne 1) { throw "Template nao encontrado: $Template" }
        $null = Invoke-ZabbixApi 'host.create' @{
            host=$Name; name=$VisibleName; status=0; groups=@(@{groupid=$GroupId})
            templates=@(@{templateid=$templateObject[0].templateid})
        }
    }
}
function Set-LabMacro([string]$HostId, [string]$Macro, [string]$Value, [int]$Type = 0) {
    $found = @(Invoke-ZabbixApi 'usermacro.get' @{output=@('hostmacroid');hostids=@($HostId);filter=@{macro=@($Macro)}})
    if ($found.Count) {
        $null = Invoke-ZabbixApi 'usermacro.update' @{hostmacroid=$found[0].hostmacroid;value=$Value;type=$Type}
    } else {
        $null = Invoke-ZabbixApi 'usermacro.create' @{hostid=$HostId;macro=$Macro;value=$Value;type=$Type}
    }
}

try {
    $script:token = Invoke-ZabbixApi 'user.login' @{username='Admin';password=$AdminPassword}
    $linuxGroup = Ensure-NamedObject 'hostgroup' 'NOC/Linux'
    $windowsGroup = Ensure-NamedObject 'hostgroup' 'NOC/Windows'
    $databaseGroup = Ensure-NamedObject 'hostgroup' 'NOC/Databases'
    $templateGroup = Ensure-NamedObject 'templategroup' 'Templates/NOC'

    # Dois proxies independentes: Docker pronto localmente e nativo instalado pelo script Mint.
    $dockerProxy = Ensure-NamedObject 'proxy' 'lab-proxy' @{operating_mode=0}
    $mintProxy = Ensure-NamedObject 'proxy' 'mint-proxy' @{operating_mode=0}
    $linuxHost = Get-LabHost 'linux-lab'
    $null = Invoke-ZabbixApi 'host.update' @{hostid=$linuxHost.hostid;monitored_by=1;proxyid=$dockerProxy}
    Add-HostGroup 'linux-lab' $linuxGroup
    Ensure-ActiveHost 'linux-mint' 'Linux Mint (VirtualBox)' 'Linux by Zabbix agent active' $linuxGroup
    Add-HostGroup 'linux-mint' $linuxGroup
    Ensure-ActiveHost 'windows-host' 'Windows principal' 'Windows by Zabbix agent active' $windowsGroup

    Set-LabHost -Name 'linux-mint-proxy' -DnsName '127.0.0.1' -GroupId $linuxGroup -TemplateNames @('Linux by Zabbix agent')
    $mintHost = Get-LabHost 'linux-mint-proxy'
    $null = Invoke-ZabbixApi 'host.update' @{hostid=$mintHost.hostid;name='Linux Mint via Proxy';monitored_by=1;proxyid=$mintProxy}
    Write-Host 'OK: proxies registrados; linux-lab usa lab-proxy. Mint via Proxy aguarda setup-mint.sh.'

    # Conta SQL dedicada; senha persistida fora dos arquivos versionados.
    $mysqlPassword = Get-LabSecret 'mysql.monitor'
    $sql = @"
CREATE USER IF NOT EXISTS 'zbx_monitor'@'%' IDENTIFIED BY '$mysqlPassword';
ALTER USER 'zbx_monitor'@'%' IDENTIFIED BY '$mysqlPassword';
GRANT REPLICATION CLIENT, PROCESS, SHOW DATABASES, SHOW VIEW ON *.* TO 'zbx_monitor'@'%';
"@
    $sql | docker compose exec -T mysql sh -c 'MYSQL_PWD=$MYSQL_ROOT_PASSWORD exec mysql -uroot'
    if ($LASTEXITCODE -ne 0) { throw 'Falha na criacao do usuario MySQL de monitoramento.' }
    Set-LabHost -Name 'mysql-lab' -DnsName 'zabbix-agent2' -GroupId $databaseGroup -TemplateNames @('MySQL by Zabbix agent 2')
    $dbHost = Get-LabHost 'mysql-lab'
    Set-LabMacro $dbHost.hostid '{$MYSQL.DSN}' 'tcp://mysql:3306'
    Set-LabMacro $dbHost.hostid '{$MYSQL.USER}' 'zbx_monitor'
    Set-LabMacro $dbHost.hostid '{$MYSQL.PASSWORD}' $mysqlPassword 1
    Write-Host 'OK: host mysql-lab, conta de monitoramento, template e macros preparados.'

    # Template didatico: itens, macro, value map e dependencia de triggers.
    $templateName = 'NOC Linux practice'
    $templateObjects = @(Invoke-ZabbixApi 'template.get' @{output=@('templateid');filter=@{host=@($templateName)}})
    if ($templateObjects.Count) { $templateId = $templateObjects[0].templateid } else {
        $result = Invoke-ZabbixApi 'template.create' @{host=$templateName;groups=@(@{groupid=$templateGroup})}
        $templateId = $result.templateids[0]
    }
    Set-LabMacro $templateId '{$NOC.ERRORS.MAX}' '5'
    $maps = @(Invoke-ZabbixApi 'valuemap.get' @{output=@('valuemapid');hostids=@($templateId);filter=@{name=@('NOC service state')}})
    if ($maps.Count) { $mapId=$maps[0].valuemapid } else {
        $result=Invoke-ZabbixApi 'valuemap.create' @{hostid=$templateId;name='NOC service state';mappings=@(@{value='0';newvalue='Down'},@{value='1';newvalue='Up'})}
        $mapId=$result.valuemapids[0]
    }
    foreach ($definition in @(
        @{name='NOC: Service state';key_='lab.service.up';valuemapid=$mapId},
        @{name='NOC: Service errors';key_='lab.service.errors'},
        @{name='NOC: Allowed key';key_='lab.key.allowed'}
    )) {
        $items=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid');hostids=@($templateId);filter=@{key_=@($definition.key_)}})
        if (-not $items.Count) {
            $payload=@{hostid=$templateId;type=0;value_type=3;delay='10s';history='7d';trends='30d'}
            foreach($key in $definition.Keys){$payload[$key]=$definition[$key]}
            $null=Invoke-ZabbixApi 'item.create' $payload
        }
    }
    $triggerDefinitions=@(
        @{description='NOC: Service is down';expression='last(/NOC Linux practice/lab.service.up)=0';priority=4},
        @{description='NOC: Too many service errors';expression='last(/NOC Linux practice/lab.service.errors)>{$NOC.ERRORS.MAX}';priority=2}
    )
    $parentTrigger=$null
    foreach($definition in $triggerDefinitions){
        $found=@(Invoke-ZabbixApi 'trigger.get' @{output=@('triggerid');hostids=@($templateId);filter=@{description=@($definition.description)}})
        if($found.Count){$triggerId=$found[0].triggerid}else{
            if($parentTrigger){$definition.dependencies=@(@{triggerid=$parentTrigger})}
            $result=Invoke-ZabbixApi 'trigger.create' $definition
            $triggerId=$result.triggerids[0]
        }
        if(-not $parentTrigger){$parentTrigger=$triggerId}
    }
    foreach($name in @('linux-lab','linux-mint-proxy')){
        $h=Get-LabHost $name
        $ids=@(@($h.parentTemplates|ForEach-Object{$_.templateid})+@($templateId)|Select-Object -Unique)
        $null=Invoke-ZabbixApi 'host.update' @{hostid=$h.hostid;templates=@($ids|ForEach-Object{@{templateid=$_}})}
    }
    $activeItems=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid');hostids=@($linuxHost.hostid);filter=@{key_=@('vfs.file.size[/etc/hostname]')}})
    if(-not $activeItems.Count){
        $null=Invoke-ZabbixApi 'item.create' @{hostid=$linuxHost.hostid;name='NOC: Active check via proxy';key_='vfs.file.size[/etc/hostname]';type=7;value_type=3;units='B';delay='30s';history='7d';trends='30d'}
    }
    Write-Host 'OK: template NOC, value map, macro, itens ativos/passivos e triggers dependentes.'

    # Restricoes de acesso: usuario ve Linux; admin gerencia Linux/Windows/DB; NOC tem role limitada.
    $readGroup=Ensure-NamedObject 'usergroup' 'NOC Readers' @{gui_access=1;mfa_status=0;hostgroup_rights=@(@{id=$linuxGroup;permission=2})}
    $writeGroup=Ensure-NamedObject 'usergroup' 'NOC Administrators' @{
        gui_access=1;mfa_status=0
        hostgroup_rights=@(@{id=$linuxGroup;permission=3},@{id=$windowsGroup;permission=3},@{id=$databaseGroup;permission=3})
        templategroup_rights=@(@{id=$templateGroup;permission=3})
    }
    $nocRole=Ensure-NamedObject 'role' 'NOC NOC read only' @{
        type=1;rules=@{
            'ui.default_access'=0
            ui=@(@{name='monitoring.dashboard';status=1},@{name='monitoring.problems';status=1},@{name='monitoring.hosts';status=1},@{name='monitoring.latest_data';status=1})
            'actions.default_access'=0;'modules.default_access'=0
            'api.access'=1;'api.mode'=1;api=@('host.get','item.get','history.get','problem.get','user.logout')
        }
    }
    $roles=@(Invoke-ZabbixApi 'role.get' @{output=@('roleid','name');filter=@{name=@('User role','Admin role','Super admin role')}})
    $userRole=($roles|Where-Object{$_.name -eq 'User role'}).roleid
    $adminRole=($roles|Where-Object{$_.name -eq 'Admin role'}).roleid
    $superRole=($roles|Where-Object{$_.name -eq 'Super admin role'}).roleid
    $mfaId=Ensure-NamedObject 'mfa' 'NOC TOTP' @{type=1;hash_function=1;code_length=6}
    $mfaGroup=Ensure-NamedObject 'usergroup' 'NOC MFA' @{gui_access=1;mfa_status=1;mfaid=$mfaId;hostgroup_rights=@(@{id=$linuxGroup;permission=2})}
    $accounts=@(
        @{username='lab.user';roleid=$userRole;groupid=$readGroup},
        @{username='lab.admin';roleid=$adminRole;groupid=$writeGroup},
        @{username='lab.super';roleid=$superRole;groupid=$writeGroup},
        @{username='lab.noc';roleid=$nocRole;groupid=$readGroup},
        @{username='lab.mfa';roleid=$userRole;groupid=$mfaGroup}
    )
    foreach($account in $accounts){
        $found=@(Invoke-ZabbixApi 'user.get' @{output=@('userid');filter=@{username=@($account.username)}})
        if(-not $found.Count){
            $password=Get-LabSecret $account.username
            $null=Invoke-ZabbixApi 'user.create' @{
                username=$account.username;passwd=$password;name='NOC';surname=$account.username
                roleid=$account.roleid;usrgrps=@(@{usrgrpid=$account.groupid})
            }
        }
    }
    $null=Invoke-ZabbixApi 'authentication.update' @{mfa_status=1;mfaid=$mfaId}
    Write-Host 'OK: usuarios, grupos, role NOC e TOTP configurados. Vincule o autenticador no primeiro login de lab.mfa.'

    # Ajuste especifico ao laboratorio: funcionalidades ausentes e campo removido na API Docker.
    $unsupportedKeys=@(
        'zabbix[process,ipmi poller,avg,busy]','zabbix[process,ipmi manager,avg,busy]',
        'zabbix[process,java poller,avg,busy]','zabbix[process,snmp trapper,avg,busy]',
        'zabbix[process,vmware collector,avg,busy]','zabbix[vmware,buffer,pused]',
        'zabbix[process,report writer,avg,busy]','zabbix[process,report manager,avg,busy]',
        'zabbix[connector_queue]','zabbix[process,connector manager,avg,busy]',
        'zabbix[process,connector worker,avg,busy]','system.sw.packages.get','docker.kernel_mem.enabled'
    )
    $serverHost=Get-LabHost 'Zabbix server'
    $items=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid','key_');hostids=@($serverHost.hostid);filter=@{key_=$unsupportedKeys}})
    foreach($item in $items){$null=Invoke-ZabbixApi 'item.update' @{itemid=$item.itemid;status=1}}
    Write-Host "OK: $($items.Count) itens nao aplicaveis desabilitados somente no host Zabbix server."
    $windowsHost=Get-LabHost 'windows-host'
    # O adaptador OpenVPN DCO deste Windows nao fornece AdapterTypeId via WMI.
    # Desabilita somente o metadado de tipo; trafego/estado da interface continuam coletados.
    $dcoTypeKey='net.if.type["{3D3F542C-8A72-4DF2-BE8E-1CB4794BF18F}"]'
    $missingMetadata=@(Invoke-ZabbixApi 'item.get' @{output=@('itemid','error');hostids=@($windowsHost.hostid);filter=@{key_=@($dcoTypeKey);state=1;status=0}})
    foreach($item in $missingMetadata){
        if($item.error -match 'no data matches'){$null=Invoke-ZabbixApi 'item.update' @{itemid=$item.itemid;status=1}}
    }
    Write-Host "Credenciais dos novos usuarios: $secretPath"
} finally {
    if($script:token){try{$null=Invoke-ZabbixApi 'user.logout' @{} }catch{Write-Warning $_};$script:token=$null}
    Pop-Location
}
