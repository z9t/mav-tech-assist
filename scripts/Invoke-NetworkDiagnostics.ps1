[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

function Test-TcpPort {
    param(
        [Parameter(Mandatory)]
        [string]$HostName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$TimeoutMs = 4000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        $connected = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $connected) {
            return [pscustomobject]@{
                Host       = $HostName
                Port       = $Port
                Reachable  = $false
                Message    = "Timed out after $TimeoutMs ms."
            }
        }

        $client.EndConnect($async)
        return [pscustomobject]@{
            Host       = $HostName
            Port       = $Port
            Reachable  = $true
            Message    = "Connected."
        }
    }
    catch {
        return [pscustomobject]@{
            Host       = $HostName
            Port       = $Port
            Reachable  = $false
            Message    = $_.Exception.Message
        }
    }
    finally {
        $client.Close()
    }
}

function Get-PingSummary {
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )

    $raw = & ping.exe -n 4 $Target 2>&1 | Out-String
    $avg = $null
    $loss = $null

    if ($raw -match "Average = (\d+)ms") {
        $avg = [int]$Matches[1]
    }

    if ($raw -match "Lost = \d+ \((\d+)% loss\)") {
        $loss = [int]$Matches[1]
    }

    return [pscustomobject]@{
        AverageMs   = $avg
        LossPercent = $loss
        Raw         = $raw
    }
}

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$configPath = Join-Path $toolkitRoot "config\network-servers.json"
$reportPath = New-ToolkitReportPath -Category "network-diagnostics" -ToolkitRoot $toolkitRoot
$config = Read-ToolkitJson -Path $configPath

$hostName = $config.diagnostics.host
$httpsPort = [int]$config.diagnostics.httpsPort
$httpsRequired = if ($null -ne $config.diagnostics.httpsRequired) { [bool]$config.diagnostics.httpsRequired } else { $false }
$iperfPort = [int]$config.diagnostics.iperfPort
$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

Write-ToolkitStatus "Running deep network diagnostics against $hostName..."

$adapters = @(Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and $_.HardwareInterface -and $_.InterfaceDescription -notmatch "(?i)virtual|vpn|hyper-v|bluetooth|loopback"
    } | Select-Object Name, InterfaceDescription, LinkSpeed, MacAddress, ifIndex)

$ipConfigs = @(Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer)

try {
    $dnsRecords = @(Resolve-DnsName -Name $hostName -ErrorAction Stop)
    Write-ToolkitStatus "DNS resolved $hostName." -Level Success
}
catch {
    $dnsRecords = @()
    $issues.Add("DNS did not resolve ${hostName}: $($_.Exception.Message)")
    Write-ToolkitStatus "DNS did not resolve $hostName." -Level Error
}

$ping = Get-PingSummary -Target $hostName
if ($ping.LossPercent -gt 0) {
    $issues.Add("Ping to $hostName shows packet loss: $($ping.LossPercent)%.")
}

$httpsCheck = Test-TcpPort -HostName $hostName -Port $httpsPort
if ($httpsCheck.Reachable) {
    Write-ToolkitStatus "HTTPS/TCP port $httpsPort is reachable." -Level Success
}
else {
    $message = "TCP port $httpsPort on $hostName is not reachable: $($httpsCheck.Message)"
    if ($httpsRequired) {
        $issues.Add($message)
        Write-ToolkitStatus "HTTPS/TCP port $httpsPort is not reachable." -Level Error
    }
    else {
        $warnings.Add($message)
        Write-ToolkitStatus "HTTPS/TCP port $httpsPort is not reachable, but HTTPS is optional for this test host." -Level Warn
    }
}

$iperfCheck = Test-TcpPort -HostName $hostName -Port $iperfPort
if ($iperfCheck.Reachable) {
    Write-ToolkitStatus "iperf3/TCP port $iperfPort is reachable." -Level Success
}
else {
    $issues.Add("TCP port $iperfPort on $hostName is not reachable. If you want throughput tests, start iperf3 on the server and allow this port through the firewall.")
    Write-ToolkitStatus "iperf3/TCP port $iperfPort is not reachable." -Level Warn
}

$proxyText = & netsh winhttp show proxy 2>&1 | Out-String

$report = [ordered]@{
    Script       = "Invoke-NetworkDiagnostics.ps1"
    RanAt        = (Get-Date).ToString("s")
    Host         = $hostName
    Adapters     = $adapters
    IpConfig     = $ipConfigs
    DnsRecords   = $dnsRecords
    Ping         = $ping
    HttpsCheck   = $httpsCheck
    IperfCheck   = $iperfCheck
    WinHttpProxy = $proxyText
    Issues       = @($issues)
    Warnings     = @($warnings)
    Help         = @(
        "If DNS fails, check Wi-Fi/Ethernet, DNS server settings, and captive portals.",
        "If HTTPS fails and you expect a web page on this hostname, check internet access, local firewall, or server availability.",
        "If only port 5201 fails, check iperf3 is running on showtime.mav.z9t.me and that TCP 5201 is open."
    )
}

Save-ToolkitJson -Path $reportPath -Data $report

if ($issues.Count -gt 0) {
    Write-ToolkitStatus "Network diagnostics found issues. Report saved to $reportPath" -Level Warn
    exit 2
}

Write-ToolkitStatus "Network diagnostics passed. Report saved to $reportPath" -Level Success
