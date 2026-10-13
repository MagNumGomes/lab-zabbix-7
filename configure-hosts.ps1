param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$Username = 'Admin',
    [string]$Password = 'zabbix',
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
$script:token = $null
$script:requestId = 0

function Invoke-ZabbixApi {
    param([string]$Method, [object]$Parameters)
    $script:requestId++
    $body = @{
        jsonrpc = '2.0'
        method = $Method
        params = $Parameters
        id = $script:requestId
    }
    if ($script:token) { $body.auth = $script:token }
    $result = Invoke-RestMethod -Method Post -Uri "$($BaseUrl.TrimEnd('/'))/api_jsonrpc.php" `
        -ContentType 'application/json-rpc' -Body ($body | ConvertTo-Json -Depth 20) -TimeoutSec 30
    if ($result.error) { throw "$Method : $($result.error.message) $($result.error.data)" }
    return $result.result
}

function Set-LabHost {
    param([string]$Name, [string]$DnsName, [string[]]$TemplateNames, [string]$GroupId)
    $templates = @(Invoke-ZabbixApi 'template.get' @{
        output = @('templateid', 'host')
        filter = @{ host = $TemplateNames }
    })
    if ($templates.Count -ne $TemplateNames.Count) {
        throw "Templates nao encontrados para ${Name}: $($TemplateNames -join ', ')"
    }
    $hostsFound = @(Invoke-ZabbixApi 'host.get' @{
        output = @('hostid')
        filter = @{ host = @($Name) }
        selectInterfaces = @('interfaceid', 'type', 'main')
        selectParentTemplates = @('templateid')
    })
    $interface = @{ type = 1; main = 1; useip = 0; ip = '127.0.0.1'; dns = $DnsName; port = '10050' }
    if ($hostsFound.Count -eq 0) {
        $null = Invoke-ZabbixApi 'host.create' @{
            host = $Name
            status = 0
            groups = @(@{ groupid = $GroupId })
            interfaces = @($interface)
            templates = @($templates | ForEach-Object { @{ templateid = $_.templateid } })
        }
    } else {
        $existing = $hostsFound[0]
        $templateIds = @(@($existing.parentTemplates | ForEach-Object { $_.templateid }) +
            @($templates | ForEach-Object { $_.templateid }) | Select-Object -Unique)
        $null = Invoke-ZabbixApi 'host.update' @{
            hostid = $existing.hostid
            status = 0
            templates = @($templateIds | ForEach-Object { @{ templateid = $_ } })
        }
        $agentInterfaces = @($existing.interfaces | Where-Object { $_.type -eq '1' -and $_.main -eq '1' })
        if ($agentInterfaces.Count -gt 0) {
            $interface.interfaceid = $agentInterfaces[0].interfaceid
            $null = Invoke-ZabbixApi 'hostinterface.update' $interface
        } else {
            $interface.hostid = $existing.hostid
            $null = Invoke-ZabbixApi 'hostinterface.create' $interface
        }
    }
    Write-Host "OK: $Name -> ${DnsName}:10050; templates: $($TemplateNames -join ', ')"
}

if ($FunctionsOnly) { return }

try {
    $script:token = Invoke-ZabbixApi 'user.login' @{ username = $Username; password = $Password }
    $groups = @(Invoke-ZabbixApi 'hostgroup.get' @{
        output = @('groupid'); filter = @{ name = @('Lab Zabbix 7') }
    })
    if ($groups.Count -eq 0) {
        $created = Invoke-ZabbixApi 'hostgroup.create' @{ name = 'Lab Zabbix 7' }
        $groupId = $created.groupids[0]
    } else { $groupId = $groups[0].groupid }

    Set-LabHost -Name 'Zabbix server' -DnsName 'zabbix-agent2' -GroupId $groupId `
        -TemplateNames @('Linux by Zabbix agent', 'Zabbix server health', 'Docker by Zabbix agent 2')
    Set-LabHost -Name 'linux-lab' -DnsName 'linux-lab' -GroupId $groupId `
        -TemplateNames @('Linux by Zabbix agent')
    Write-Host 'Cadastro concluido. Consulte Monitoring > Latest data apos alguns minutos.'
} finally {
    if ($script:token) {
        try { $null = Invoke-ZabbixApi 'user.logout' @{} } catch { Write-Warning $_ }
        $script:token = $null
    }
}
