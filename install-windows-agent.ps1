param([string]$Version = '7.0.31')
$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argsText = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Version `"$Version`""
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $argsText -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Instalacao elevada falhou: $($process.ExitCode). Consulte windows-install.log." }
    exit 0
}

Start-Transcript -Path "$PSScriptRoot/windows-install.log" -Append | Out-Null
try {
    $existing = Get-Service -Name 'Zabbix Agent' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host 'Servico Zabbix Agent ja instalado. Verifique a coleta antes de reinstalar.'
        Get-Service -Name 'Zabbix Agent'
    } else {
        $downloads = Join-Path $PSScriptRoot 'downloads'
        $null = New-Item -ItemType Directory -Path $downloads -Force
        $msi = Join-Path $downloads "zabbix_agent-$Version-windows-amd64-openssl.msi"
        $url = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/$Version/zabbix_agent-$Version-windows-amd64-openssl.msi"
        & curl.exe --fail --location --retry 3 --output $msi $url
        if ($LASTEXITCODE -ne 0) { throw 'Falha no download do MSI oficial.' }
        $signature = Get-AuthenticodeSignature $msi
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Zabbix') {
            throw "Assinatura MSI inesperada: $($signature.Status), $($signature.SignerCertificate.Subject)"
        }
        $log = Join-Path $PSScriptRoot 'windows-msi.log'
        $arguments = "/i `"$msi`" /qn /norestart /L*v `"$log`" HOSTNAME=windows-host SERVER=127.0.0.1 SERVERACTIVE=127.0.0.1:10051 ENABLEPATH=1 SKIP=fw"
        $installer = Start-Process msiexec.exe -ArgumentList $arguments -PassThru -Wait
        if ($installer.ExitCode -notin @(0, 3010)) { throw "MSI falhou: $($installer.ExitCode). Consulte $log" }
        Set-Service -Name 'Zabbix Agent' -StartupType Automatic
        Start-Service -Name 'Zabbix Agent'
        Get-Service -Name 'Zabbix Agent'
        Write-Host 'OK: Windows configurado para checks ativos, Hostname=windows-host.'
    }
} catch {
    Write-Output "ERRO: $_"
    exit 1
} finally { Stop-Transcript | Out-Null }
