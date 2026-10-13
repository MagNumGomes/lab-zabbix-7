. "$PSScriptRoot/configure-hosts.ps1" -FunctionsOnly
$failures = @()
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { Write-Host "OK: $Name $Detail" } else { Write-Host "FALHA: $Name $Detail"; $script:failures += $Name }
}
Push-Location $PSScriptRoot
try {
    $script:token = Invoke-ZabbixApi 'user.login' @{username='Admin';password='zabbix'}

    # Roles
    $roles = @(Invoke-ZabbixApi 'role.get' @{output=@('roleid','name');selectRules='extend'})
    $op = @($roles | Where-Object { $_.name -eq 'NOC Operator' })[0]
    Check 'role NOC Operator existe' ($null -ne $op)
    if ($op) {
        $ack = @($op.rules.actions | Where-Object { $_.name -eq 'acknowledge_problems' })[0]
        Check 'role Operator pode reconhecer problemas' ($ack.status -eq '1')
        Check 'role Operator tem API event.acknowledge' ($op.rules.api -contains 'event.acknowledge')
    }
    $maint = @($roles | Where-Object { $_.name -eq 'NOC Maintenance admin' })[0]
    Check 'role NOC Maintenance admin existe' ($null -ne $maint)
    if ($maint) {
        $em = @($maint.rules.actions | Where-Object { $_.name -eq 'edit_maintenance' })[0]
        Check 'role Maintenance pode editar manutencao' ($em.status -eq '1')
    }
    $noc = @($roles | Where-Object { $_.name -eq 'NOC NOC read only' })[0]
    Check 'role NOC read only existe' ($null -ne $noc)

    # Grupo + usuario operador
    $grp = @(Invoke-ZabbixApi 'usergroup.get' @{output=@('usrgrpid');filter=@{name=@('NOC Operators')}})
    Check 'grupo NOC Operators existe' ($grp.Count -eq 1)
    $usr = @(Invoke-ZabbixApi 'user.get' @{output=@('userid','roleid');selectMedias='extend';filter=@{username=@('lab.operator')}})
    Check 'usuario lab.operator existe' ($usr.Count -eq 1)
    if ($usr.Count -eq 1 -and $op) { Check 'lab.operator usa role Operator' ($usr[0].roleid -eq $op.roleid) }
    $hasMail = @($usr[0].medias | Where-Object { $_.sendto -eq 'operator@example.com' })
    Check 'lab.operator tem midia de email' ($hasMail.Count -ge 1)

    # Login real do operador + visibilidade
    $null = Invoke-ZabbixApi 'user.logout' @{}
    $script:token = $null
    $opSecret = (Get-Content (Join-Path $PSScriptRoot 'credentials.local.json') -Raw | ConvertFrom-Json).'lab.operator'
    $script:token = Invoke-ZabbixApi 'user.login' @{username='lab.operator';password=$opSecret}
    $visible = @(Invoke-ZabbixApi 'host.get' @{output=@('host');filter=@{host=@('linux-lab')}})
    Check 'lab.operator enxerga linux-lab' ($visible.Count -eq 1)
    $null = Invoke-ZabbixApi 'user.logout' @{}
    $script:token = $null
    $script:token = Invoke-ZabbixApi 'user.login' @{username='Admin';password='zabbix'}

    # Acao de alerta
    $act = @(Invoke-ZabbixApi 'action.get' @{output=@('actionid','name','status','esc_period');selectOperations='extend';selectRecoveryOperations='extend';selectFilter='extend';filter=@{name=@('NOC: avisa queda do servico didatico')}})
    Check 'acao NOC de alerta existe' ($act.Count -eq 1)
    if ($act.Count -eq 1) {
        Check 'acao habilitada' ($act[0].status -eq '0')
        Check 'acao tem 2 operacoes de escalonamento' ($act[0].operations.Count -eq 2)
        Check 'acao tem operacao de recuperacao' ($act[0].recovery_operations.Count -ge 1)
        Check 'acao filtra grupo + nome + severidade' ($act[0].filter.conditions.Count -eq 3)
    }

    # Midia webhook + teste real
    $mt = @(Invoke-ZabbixApi 'mediatype.get' @{output=@('mediatypeid','name','type','status','script');filter=@{name=@('NOC Registro em log (exemplo)')}})
    Check 'mediatype webhook de exemplo existe' ($mt.Count -eq 1)
    if ($mt.Count -eq 1) {
        Check 'mediatype e webhook habilitado e auto-contido' ($mt[0].type -eq '4' -and $mt[0].status -eq '0' -and $mt[0].script -match "return 'OK'") "(entrega real testada via alerta; ver Reports > Action log)"
    }

    # Manutencao futura
    $m = @(Invoke-ZabbixApi 'maintenance.get' @{output=@('maintenanceid','name','active_since','active_till');selectHosts=@('hostid');selectTimeperiods='extend';filter=@{name=@('NOC Exemplo - janela de manutencao')}})
    Check 'manutencao de exemplo existe' ($m.Count -eq 1)
    if ($m.Count -eq 1) {
        $nowTs = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Check 'manutencao e futura (nao suprime agora)' ([long]$m[0].active_since -gt $nowTs) ("inicio: $([DateTimeOffset]::FromUnixTimeSeconds([long]$m[0].active_since).ToString('u'))")
    }

    # Dashboard
    $d = @(Invoke-ZabbixApi 'dashboard.get' @{output=@('dashboardid','name');selectPages='extend';filter=@{name=@('NOC Visao do curso')}})
    Check 'dashboard NOC existe' ($d.Count -eq 1)
    if ($d.Count -eq 1) {
        $widgets = @($d[0].pages[0].widgets)
        Check 'dashboard tem 3 widgets' ($widgets.Count -eq 3) ("tipos: $(($widgets | ForEach-Object { $_.type }) -join ', ')")
    }

    # Servico + SLA
    $s = @(Invoke-ZabbixApi 'service.get' @{output=@('serviceid','name');filter=@{name=@('NOC Servico didatico')}})
    Check 'servico de exemplo existe' ($s.Count -eq 1)
    $sla = @(Invoke-ZabbixApi 'sla.get' @{output=@('slaid','name','slo');filter=@{name=@('NOC SLA exemplo')}})
    Check 'SLA de exemplo existe' ($sla.Count -eq 1)
    if ($sla.Count -eq 1) { Check 'SLA 99,9%' ($sla[0].slo -eq '99.9') }

    # Tags nas triggers
    $tpl = @(Invoke-ZabbixApi 'template.get' @{output=@('templateid');filter=@{host=@('NOC Linux practice')}})
    $trigs = @(Invoke-ZabbixApi 'trigger.get' @{output=@('triggerid');selectTags='extend';hostids=@($tpl[0].templateid)})
    $tagged = @($trigs | Where-Object { @($_.tags | Where-Object { $_.tag -eq 'curso' -and $_.value -eq 'noc' }).Count -ge 1 })
    Check 'triggers NOC com tag curso:noc' ($tagged.Count -eq $trigs.Count) ("$($tagged.Count)/$($trigs.Count)")

    if ($failures.Count) { throw "Verificacao com $($failures.Count) falha(s): $($failures -join '; ')" }
    Write-Host 'OK: todos os exemplos validados.'
} finally {
    if ($script:token) { try { $null = Invoke-ZabbixApi 'user.logout' @{} } catch {}; $script:token = $null }
    Pop-Location
}
