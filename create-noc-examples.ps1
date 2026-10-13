param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$AdminPassword = 'zabbix'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
. "$PSScriptRoot/configure-hosts.ps1" -FunctionsOnly -BaseUrl $BaseUrl -Username Admin -Password $AdminPassword
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

try {
    $script:token = Invoke-ZabbixApi 'user.login' @{username='Admin';password=$AdminPassword}

    $linuxGroup = @(Invoke-ZabbixApi 'hostgroup.get' @{output=@('groupid');filter=@{name=@('NOC/Linux')}})
    if (-not $linuxGroup.Count) { throw 'Grupo NOC/Linux nao encontrado. Execute complete-lab.ps1 primeiro.' }
    $linuxGroupId = [string]$linuxGroup[0].groupid
    $adminGroup = @(Invoke-ZabbixApi 'usergroup.get' @{output=@('usrgrpid');filter=@{name=@('NOC Administrators')}})
    $adminGroupId = [string]$adminGroup[0].usrgrpid
    $linuxHost = @(Invoke-ZabbixApi 'host.get' @{output=@('hostid');filter=@{host=@('linux-lab')}})
    $linuxHostId = [string]$linuxHost[0].hostid
    $emailHtml = @(Invoke-ZabbixApi 'mediatype.get' @{output=@('mediatypeid');filter=@{name=@('Email (HTML)')}})
    $emailHtmlId = [string]$emailHtml[0].mediatypeid

    # 1. Roles de exemplo (M05A07): operador com acknowledge + manutencao com foco em maintenance.
    $operatorRules = @{
        'ui.default_access'=0
        ui=@(
            @{name='monitoring.dashboard';status=1},@{name='monitoring.problems';status=1},
            @{name='monitoring.hosts';status=1},@{name='monitoring.latest_data';status=1},
            @{name='monitoring.maps';status=1}
        )
        'actions.default_access'=0
        actions=@(
            @{name='acknowledge_problems';status=1},@{name='close_problems';status=1},
            @{name='change_severity';status=1},@{name='add_problem_comments';status=1},
            @{name='suppress_problems';status=1}
        )
        'modules.default_access'=0
        'api.access'=1;'api.mode'=1
        api=@('host.get','item.get','history.get','problem.get','event.acknowledge','maintenance.get','user.logout')
    }
    $found = @(Invoke-ZabbixApi 'role.get' @{output=@('roleid');filter=@{name=@('NOC Operator')}})
    if ($found.Count) {
        $null = Invoke-ZabbixApi 'role.update' @{roleid=$found[0].roleid;type=1;rules=$operatorRules}
        $operatorRoleId = [string]$found[0].roleid
    } else {
        $res = Invoke-ZabbixApi 'role.create' @{name='NOC Operator';type=1;rules=$operatorRules}
        $operatorRoleId = [string]$res.roleids[0]
    }
    Write-Host "OK: role NOC Operator ($operatorRoleId)."

    $maintRules = @{
        'ui.default_access'=1
        'actions.default_access'=0
        actions=@(
            @{name='acknowledge_problems';status=1},@{name='add_problem_comments';status=1},
            @{name='change_severity';status=1},@{name='edit_maintenance';status=1}
        )
        'modules.default_access'=0
        'api.access'=1;'api.mode'=1
        api=@('host.get','problem.get','maintenance.get','maintenance.create','maintenance.update','event.acknowledge','user.logout')
    }
    $found = @(Invoke-ZabbixApi 'role.get' @{output=@('roleid');filter=@{name=@('NOC Maintenance admin')}})
    if ($found.Count) {
        $null = Invoke-ZabbixApi 'role.update' @{roleid=$found[0].roleid;type=2;rules=$maintRules}
        $maintRoleId = [string]$found[0].roleid
    } else {
        $res = Invoke-ZabbixApi 'role.create' @{name='NOC Maintenance admin';type=2;rules=$maintRules}
        $maintRoleId = [string]$res.roleids[0]
    }
    Write-Host "OK: role NOC Maintenance admin ($maintRoleId)."

    # 2. Grupo + usuario operador (M05A03-A05).
    $found = @(Invoke-ZabbixApi 'usergroup.get' @{output=@('usrgrpid');filter=@{name=@('NOC Operators')}})
    if ($found.Count) {
        $null = Invoke-ZabbixApi 'usergroup.update' @{usrgrpid=$found[0].usrgrpid;gui_access=1;mfa_status=0;hostgroup_rights=@(@{id=$linuxGroupId;permission=2})}
        $operatorsGroupId = [string]$found[0].usrgrpid
    } else {
        $res = Invoke-ZabbixApi 'usergroup.create' @{name='NOC Operators';gui_access=1;mfa_status=0;hostgroup_rights=@(@{id=$linuxGroupId;permission=2})}
        $operatorsGroupId = [string]$res.usrgrpids[0]
    }
    Write-Host "OK: grupo NOC Operators ($operatorsGroupId)."
    $found = @(Invoke-ZabbixApi 'user.get' @{output=@('userid');filter=@{username=@('lab.operator')}})
    if (-not $found.Count) {
        $null = Invoke-ZabbixApi 'user.create' @{username='lab.operator';passwd=(Get-LabSecret 'lab.operator');name='NOC';surname='lab.operator';roleid=$operatorRoleId;usrgrps=@(@{usrgrpid=$operatorsGroupId})}
        Write-Host 'OK: usuario lab.operator criado.'
    } else {
        Write-Host 'OK: usuario lab.operator ja existe.'
    }
    $opUser = @(Invoke-ZabbixApi 'user.get' @{output=@('userid');selectMedias='extend';filter=@{username=@('lab.operator')}})
    $hasMail = @($opUser[0].medias | Where-Object { $_.mediatypeid -eq $emailHtmlId })
    if (-not $hasMail.Count) {
        $existing = @($opUser[0].medias | ForEach-Object { @{mediatypeid=$_.mediatypeid;sendto=$_.sendto;active=$_.active;severity=$_.severity;period=$_.period} })
        $newMedia = @{mediatypeid=$emailHtmlId;sendto='operator@example.com';active=0;severity=63;period='1-7,00:00-24:00'}
        $null = Invoke-ZabbixApi 'user.update' @{userid=$opUser[0].userid;medias=@($existing + @($newMedia))}
        Write-Host 'OK: midia Email (HTML) do lab.operator.'
    } else {
        Write-Host 'OK: midia do lab.operator ja existe.'
    }

    # 3. Tags nas triggers didaticas (base para filtro de acao e widgets).
    $tpl = @(Invoke-ZabbixApi 'template.get' @{output=@('templateid');filter=@{host=@('NOC Linux practice')}})
    $trigs = @(Invoke-ZabbixApi 'trigger.get' @{output=@('triggerid','description');hostids=@($tpl[0].templateid)})
    foreach ($t in $trigs) {
        $null = Invoke-ZabbixApi 'trigger.update' @{triggerid=$t.triggerid;tags=@(@{tag='curso';value='noc'},@{tag='servico';value='lab-demo'})}
    }
    Write-Host "OK: tags curso/servico em $($trigs.Count) triggers do template NOC."

    # 4. Acao de alerta com escalonamento (M04 triggers + notificacao).
    $actionName = 'NOC: avisa queda do servico didatico'
    $found = @(Invoke-ZabbixApi 'action.get' @{output=@('actionid');filter=@{name=@($actionName)}})
    $actionDef = @{
        name=$actionName;eventsource=0;status=0;esc_period='5m'
        pause_suppressed=1;notify_if_canceled=1;pause_symptoms=1
        filter=@{evaltype=0;conditions=@(
            @{conditiontype=0;operator=0;value=$linuxGroupId},
            @{conditiontype=3;operator=2;value='NOC'},
            @{conditiontype=4;operator=5;value='2'}
        )}
        operations=@(
            @{operationtype=0;esc_step_from=1;esc_step_to=1;opmessage_grp=@(@{usrgrpid=$operatorsGroupId});opmessage=@{default_msg=1}},
            @{operationtype=0;esc_step_from=2;esc_step_to=2;opmessage_grp=@(@{usrgrpid=$adminGroupId});opmessage=@{default_msg=1}}
        )
        recovery_operations=@(@{operationtype=11;opmessage=@{default_msg=1}})
    }
    if ($found.Count) {
        $actionDef.actionid = [string]$found[0].actionid
        $null = Invoke-ZabbixApi 'action.update' $actionDef
        $actionId = [string]$found[0].actionid
    } else {
        $res = Invoke-ZabbixApi 'action.create' $actionDef
        $actionId = [string]$res.actionids[0]
    }
    Write-Host "OK: acao $actionName ($actionId) com escalonamento 1->Operators, 2->Administrators."

    # 5. Midia webhook de exemplo, desabilitada (sem dependencia externa).
    $mtName = 'NOC Registro em log (exemplo)'
    $found = @(Invoke-ZabbixApi 'mediatype.get' @{output=@('mediatypeid','status');filter=@{name=@($mtName)}})
    $hookTemplates = @(
        @{eventsource=0;recovery=0;subject='NOC problema: {EVENT.NAME}';message="Host: {HOST.NAME}`nSeveridade: {TRIGGER.SEVERITY}`nHora: {EVENT.DATE} {EVENT.TIME}`nItem: {ITEM.NAME} = {ITEM.VALUE}"},
        @{eventsource=0;recovery=1;subject='NOC resolvido: {EVENT.NAME}';message="Host: {HOST.NAME}`nHora: {EVENT.DATE} {EVENT.TIME}`nDuracao: {EVENT.DURATION}"},
        @{eventsource=0;recovery=2;subject='NOC atualizado: {EVENT.NAME}';message="Host: {HOST.NAME}`nAtualizacao: {EVENT.UPDATE.HISTORY}"}
    )
    if (-not $found.Count) {
        $res = Invoke-ZabbixApi 'mediatype.create' @{name=$mtName;type=4;status=0;timeout='10s';script="return 'OK';";description='Exemplo didatico: webhook sem destino externo. Habilitado de proposito para demonstrar entrega real no log de acoes.';message_templates=$hookTemplates}
        Write-Host "OK: mediatype $mtName ($($res.mediatypeids[0])) habilitado, com modelos de mensagem."
    } else {
        $null = Invoke-ZabbixApi 'mediatype.update' @{mediatypeid=$found[0].mediatypeid;status=0;message_templates=$hookTemplates}
        Write-Host "OK: mediatype $mtName habilitado para entrega real, com modelos de mensagem."
    }

    # 5b. Entrega real do alerta de exemplo: webhook atribuido ao operador.
    # O Email (HTML) tambem esta na midia do usuario, mas sem relay SMTP o envio
    # externo falha; o webhook auto-contido (return 'OK') entrega com sucesso e
    # comprova o caminho trigger -> acao -> midia no log de acoes.
    $mtId = [string](@(Invoke-ZabbixApi 'mediatype.get' @{output=@('mediatypeid');filter=@{name=@($mtName)}}))[0].mediatypeid
    $opUserRefresh = @(Invoke-ZabbixApi 'user.get' @{output=@('userid');selectMedias='extend';filter=@{username=@('lab.operator')}})
    $hasHook = @($opUserRefresh[0].medias | Where-Object { $_.mediatypeid -eq $mtId })
    if (-not $hasHook.Count) {
        $keep = @($opUserRefresh[0].medias | ForEach-Object { @{mediatypeid=$_.mediatypeid;sendto=$_.sendto;active=$_.active;severity=$_.severity;period=$_.period} })
        $null = Invoke-ZabbixApi 'user.update' @{userid=$opUserRefresh[0].userid;medias=@($keep + @(@{mediatypeid=$mtId;sendto='noc-demo';active=0;severity=63;period='1-7,00:00-24:00'}))}
        Write-Host 'OK: webhook NOC atribuido a midia do lab.operator.'
    } else {
        Write-Host 'OK: webhook NOC ja esta na midia do lab.operator.'
    }
    # 6. Manutencao de exemplo num domingo futuro (nao suprime nada agora).
    $mtcName = 'NOC Exemplo - janela de manutencao'
    $found = @(Invoke-ZabbixApi 'maintenance.get' @{output=@('maintenanceid');filter=@{name=@($mtcName)}})
    $now = [DateTimeOffset]::UtcNow
    $daysToSun = (([int][DayOfWeek]::Sunday - [int]$now.DayOfWeek + 7) % 7)
    if ($daysToSun -eq 0) { $daysToSun = 7 }
    $start = $now.Date.AddDays($daysToSun).AddHours(5)
    $startTs = [long]([DateTimeOffset]$start).ToUnixTimeSeconds()
    if (-not $found.Count) {
        $res = Invoke-ZabbixApi 'maintenance.create' @{
            name=$mtcName;maintenance_type=0;active_since=$startTs;active_till=($startTs+7200);description='Exemplo M04/M05: janela semanal de 2h aos domingos. Datas futuras; nao afeta a coleta atual.'
            timeperiods=@(@{timeperiod_type=3;every=1;dayofweek=64;start_time=7200;period=7200})
            hosts=@(@{hostid=$linuxHostId})
        }
        Write-Host "OK: manutencao $mtcName ($($res.maintenanceids[0])) a partir de $($start.ToUniversalTime().ToString('u'))."
    } else {
        Write-Host "OK: manutencao $mtcName ja existe."
    }

    # 7. Dashboard global de exemplo.
    $dashName = 'NOC Visao do curso'
    $found = @(Invoke-ZabbixApi 'dashboard.get' @{output=@('dashboardid');filter=@{name=@($dashName)}})
    if (-not $found.Count) {
        $res = Invoke-ZabbixApi 'dashboard.create' @{
            name=$dashName;'auto_start'=1
            pages=@(@{name='Visao geral';widgets=@(
                @{type='problems';name='Problemas NOC';x=0;y=0;width=12;height=5;view_mode=0;fields=@()},
                @{type='hostavail';name='Disponibilidade dos hosts';x=12;y=0;width=12;height=5;view_mode=0;fields=@()},
                @{type='systeminfo';name='Info do servidor';x=0;y=5;width=12;height=4;view_mode=0;fields=@()}
            )})
        }
        Write-Host "OK: dashboard $dashName ($($res.dashboardids[0]))."
    } else {
        Write-Host "OK: dashboard $dashName ja existe."
    }

    # 8. Servico + SLA de exemplo (pilar disponibilidade, M01).
    $svcName = 'NOC Servico didatico'
    $found = @(Invoke-ZabbixApi 'service.get' @{output=@('serviceid');filter=@{name=@($svcName)}})
    if (-not $found.Count) {
        try {
            $res = Invoke-ZabbixApi 'service.create' @{name=$svcName;algorithm=1;sortorder='0';description='Exemplo: disponibilidade do servico didatico lab.service.up.'}
            $svcId = [string]$res.serviceids[0]
            $null = Invoke-ZabbixApi 'service.update' @{serviceid=$svcId;tags=@(@{tag='servico';value='lab-demo'})}
            Write-Host "OK: servico $svcName ($svcId)."
        } catch {
            Write-Warning "Servico nao criado: $_"
            $svcId = $null
        }
    } else {
        $svcId = [string]$found[0].serviceid
        Write-Host "OK: servico $svcName ja existe."
    }
    if ($svcId) {
        $slaName = 'NOC SLA exemplo'
        $found = @(Invoke-ZabbixApi 'sla.get' @{output=@('slaid');filter=@{name=@($slaName)}})
        if (-not $found.Count) {
            try {
                $res = Invoke-ZabbixApi 'sla.create' @{name=$slaName;slo='99.9';period=1;timezone='America/Sao_Paulo';effective_date=[string][long]$now.ToUnixTimeSeconds();description='Exemplo: 99,9% semanal sobre o servico didatico.';service_tags=@(@{tag='servico';operator=0;value='lab-demo'})}
                Write-Host "OK: SLA $slaName ($($res.slaids[0]))."
            } catch {
                Write-Warning "SLA nao criado: $_"
            }
        } else {
            Write-Host "OK: SLA $slaName ja existe."
        }
    }

    Write-Host "Credenciais dos novos usuarios: $secretPath"
} finally {
    if ($script:token) { try { $null = Invoke-ZabbixApi 'user.logout' @{} } catch { Write-Warning $_ }; $script:token = $null }
    Pop-Location
}
