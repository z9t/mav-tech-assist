[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

function Get-AdapterCategory {
    param(
        [Parameter(Mandatory)]
        $Adapter
    )

    $text = "$($Adapter.Name) $($Adapter.InterfaceDescription)"
    if ($text -match "(?i)wi-?fi|wireless|802\.11") {
        return "Wi-Fi"
    }

    return "Ethernet"
}

function Test-GatewayPing {
    param(
        [Parameter(Mandatory)]
        [string]$SourceIp,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $output = & ping.exe -n 4 -S $SourceIp $Target 2>&1 | Out-String
    $avg = $null
    $loss = $null

    if ($output -match "Average = (\d+)ms") {
        $avg = [int]$Matches[1]
    }

    if ($output -match "Lost = \d+ \((\d+)% loss\)") {
        $loss = [int]$Matches[1]
    }

    return [pscustomobject]@{
        AverageMs   = $avg
        LossPercent = $loss
        Raw         = $output
    }
}

function Convert-IperfRaw {
    param(
        [Parameter(Mandatory)]
        [string]$Raw,

        [Parameter(Mandatory)]
        [ValidateSet("download", "upload")]
        [string]$Direction
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $null
    }

    $jsonText = $Raw.Trim()

    try {
        $json = $jsonText | ConvertFrom-Json
    }
    catch {
        $jsonStart = $jsonText.IndexOf("{")
        $jsonEnd = $jsonText.LastIndexOf("}")

        if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
            return $null
        }

        $jsonText = $jsonText.Substring($jsonStart, $jsonEnd - $jsonStart + 1)

        try {
            $json = $jsonText | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }

    $jsonEnd = Get-OptionalPropertyValue -InputObject $json -Name "end"
    if (-not $jsonEnd) {
        return [pscustomobject]@{
            Mbps        = $null
            Bytes       = $null
            Retransmits = $null
            Error       = "iperf3 JSON did not contain an end block."
        }
    }

    if ($Direction -eq "download") {
        $summary = Get-OptionalPropertyValue -InputObject $jsonEnd -Name "sum_received"
        if (-not $summary) {
            $summary = Get-OptionalPropertyValue -InputObject $jsonEnd -Name "sum"
        }
    }
    else {
        $summary = Get-OptionalPropertyValue -InputObject $jsonEnd -Name "sum_sent"
        if (-not $summary) {
            $summary = Get-OptionalPropertyValue -InputObject $jsonEnd -Name "sum"
        }
    }

    if (-not $summary) {
        return [pscustomobject]@{
            Mbps        = $null
            Bytes       = $null
            Retransmits = $null
            Error       = if (Get-OptionalPropertyValue -InputObject $json -Name "error") { [string](Get-OptionalPropertyValue -InputObject $json -Name "error") } else { "iperf3 JSON did not contain a throughput summary." }
        }
    }

    return [pscustomobject]@{
        Mbps        = [math]::Round(($summary.bits_per_second / 1e6), 2)
        Bytes       = [int64]$summary.bytes
        Retransmits = if (Get-OptionalPropertyValue -InputObject $summary -Name "retransmits") { [int](Get-OptionalPropertyValue -InputObject $summary -Name "retransmits") } else { $null }
        Error       = if (Get-OptionalPropertyValue -InputObject $json -Name "error") { [string](Get-OptionalPropertyValue -InputObject $json -Name "error") } else { $null }
    }
}

function Get-OptionalPropertyValue {
    param(
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if (-not $property) {
        return $null
    }

    return $property.Value
}

function Convert-SpeedtestRaw {
    param(
        [Parameter(Mandatory)]
        [string]$Raw
    )

    try {
        $json = $Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    return [pscustomobject]@{
        DownloadMbps = [math]::Round((($json.download.bandwidth * 8) / 1e6), 2)
        UploadMbps   = [math]::Round((($json.upload.bandwidth * 8) / 1e6), 2)
        PingMs       = [math]::Round([double]$json.ping.latency, 2)
        JitterMs     = [math]::Round([double]$json.ping.jitter, 2)
        PacketLoss   = if ($json.packetLoss -ne $null) { [math]::Round([double]$json.packetLoss, 2) } else { $null }
        Server       = if ($json.server) { "$($json.server.name), $($json.server.location)" } else { $null }
    }
}

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$configPath = Join-Path $toolkitRoot "config\network-servers.json"
$reportPath = New-ToolkitReportPath -Category "network-test" -ToolkitRoot $toolkitRoot
$config = Read-ToolkitJson -Path $configPath

$toolDirectories = @(
    (Join-Path $toolkitRoot "tools"),
    $PSScriptRoot
)

$iperfPath = Find-Executable -Names @("iperf3.exe", "iperf3") -AdditionalDirectories $toolDirectories
$speedtestPath = Find-Executable -Names @("speedtest.exe", "speedtest") -AdditionalDirectories $toolDirectories
$bundledToolDirectory = (Resolve-Path -LiteralPath (Join-Path $toolkitRoot "tools")).Path
$iperfMissingSupportFiles = @()

if ($iperfPath) {
    $iperfDirectory = (Resolve-Path -LiteralPath (Split-Path -Path $iperfPath -Parent)).Path
    if ($iperfDirectory -eq $bundledToolDirectory) {
        $iperfSupportFiles = @(
            "cygcrypto-3.dll",
            "cygwin1.dll",
            "cygz.dll"
        )

        foreach ($supportFile in $iperfSupportFiles) {
            $supportPath = Join-Path $iperfDirectory $supportFile
            if (-not (Test-Path -LiteralPath $supportPath -PathType Leaf)) {
                $iperfMissingSupportFiles += $supportFile
            }
        }

        if ($iperfMissingSupportFiles.Count -gt 0) {
            Write-ToolkitStatus "Bundled iperf3 support files are missing: $($iperfMissingSupportFiles -join ', ')" -Level Warn
            $iperfPath = $null
        }
    }
}

$rawAdapters = Get-NetAdapter | Where-Object {
    $_.Status -eq "Up" -and $_.HardwareInterface -and $_.InterfaceDescription -notmatch "(?i)virtual|vpn|hyper-v|bluetooth|loopback"
}

$adapters = @(foreach ($adapter in $rawAdapters) {
    $ipv4 = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254*" } |
        Select-Object -First 1
    $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue

    [pscustomobject]@{
        Name        = $adapter.Name
        Category    = Get-AdapterCategory -Adapter $adapter
        LinkSpeed   = $adapter.LinkSpeed
        InterfaceIx = $adapter.ifIndex
        SourceIp    = if ($ipv4) { $ipv4.IPAddress } else { $null }
        Gateway     = if ($ipConfig.IPv4DefaultGateway) { $ipConfig.IPv4DefaultGateway.NextHop } else { $null }
        DnsServers  = if ($ipConfig.DNSServer) { @($ipConfig.DNSServer.ServerAddresses) } else { @() }
    }
})

if ($adapters.Count -eq 0) {
    throw "No active physical Wi-Fi or Ethernet adapters were found."
}

$adapterNames = @($adapters | ForEach-Object { $_.Name } | Sort-Object)
Write-ToolkitStatus "Active adapters: $($adapterNames -join ', ')"

$latencyChecks = foreach ($adapter in $adapters) {
    if (-not $adapter.SourceIp -or -not $adapter.Gateway) {
        [pscustomobject]@{
            Adapter     = $adapter.Name
            Category    = $adapter.Category
            Gateway     = $adapter.Gateway
            AverageMs   = $null
            LossPercent = $null
            Notes       = "Missing source IP or default gateway."
        }
        continue
    }

    Write-ToolkitStatus "Pinging gateway $($adapter.Gateway) from $($adapter.Name) ($($adapter.SourceIp))"
    $ping = Test-GatewayPing -SourceIp $adapter.SourceIp -Target $adapter.Gateway
    [pscustomobject]@{
        Adapter     = $adapter.Name
        Category    = $adapter.Category
        Gateway     = $adapter.Gateway
        AverageMs   = $ping.AverageMs
        LossPercent = $ping.LossPercent
        Notes       = $null
    }
}

$iperfServers = @($config.iperf3.servers | Where-Object { $_.host -and $_.host -notmatch "(?i)change-me|example" })
$iperfAdapters = @($adapters | Where-Object { $_.SourceIp } | Select-Object Name, Category, SourceIp)
$jobs = New-Object System.Collections.Generic.List[object]
$methodUsed = $null

if ($iperfPath -and $iperfServers.Count -gt 0) {
    $methodUsed = "iperf3"
    $serverSubset = @($iperfServers | Select-Object -First ([math]::Min([int]$config.iperf3.maxConcurrentServers, $iperfServers.Count)))
    $iperfAdaptersJson = $iperfAdapters | ConvertTo-Json -Compress -Depth 4

    foreach ($server in $serverSubset) {
        $portNumber = [int]$server.port
        $testSeconds = [int]$config.iperf3.seconds
        $parallelStreams = [int]$config.iperf3.parallelStreams
        Write-ToolkitStatus "Queueing iperf3 tests against $($server.name) ($($server.host):$($server.port)) for $($iperfAdapters.Count) adapter(s). One adapter at a time will be run per server."
        $job = Start-Job -ScriptBlock {
            param($tool, $serverName, $hostName, $port, $seconds, $parallel, $adapterInputsJson)

            $adapterInputs = @($adapterInputsJson | ConvertFrom-Json)
            $results = @()
            foreach ($adapter in $adapterInputs) {
                $downloadRaw = & $tool -c $hostName -p $port -J -t $seconds -P $parallel -B $adapter.SourceIp -R 2>&1 | Out-String
                $downloadExit = $LASTEXITCODE
                $uploadRaw = & $tool -c $hostName -p $port -J -t $seconds -P $parallel -B $adapter.SourceIp 2>&1 | Out-String
                $uploadExit = $LASTEXITCODE

                $results += [pscustomobject]@{
                    Method        = "iperf3"
                    Adapter       = $adapter.Name
                    Category      = $adapter.Category
                    SourceIp      = $adapter.SourceIp
                    Server        = $serverName
                    Host          = $hostName
                    Port          = $port
                    DownloadRaw   = $downloadRaw
                    UploadRaw     = $uploadRaw
                    DownloadExit  = $downloadExit
                    UploadExit    = $uploadExit
                }
            }

            return $results
        } -ArgumentList $iperfPath, $server.name, $server.host, $portNumber, $testSeconds, $parallelStreams, $iperfAdaptersJson
        $jobs.Add($job)
    }
}
elseif ($speedtestPath) {
    $methodUsed = "ookla-speedtest"
    $serverIds = @($config.ookla.serverIds)
    $serverId = if ($serverIds.Count -gt 0) { [string]$serverIds[0] } else { $null }

    foreach ($adapter in @($adapters | Where-Object { $_.SourceIp })) {
        Write-ToolkitStatus "Queueing best-effort Ookla test for $($adapter.Name)"
        $job = Start-Job -ScriptBlock {
            param($tool, $adapterName, $category, $sourceIp, $serverId)

            $attempts = New-Object System.Collections.Generic.List[object]
            $baseArgs = @("--format=json", "--accept-license", "--accept-gdpr")
            if ($serverId) {
                $baseArgs += "--server-id=$serverId"
            }

            $attempts.Add(@("--interface=$adapterName") + $baseArgs)
            $attempts.Add(@("--ip=$sourceIp") + $baseArgs)
            $attempts.Add($baseArgs)

            foreach ($args in $attempts) {
                $raw = & $tool @args 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                if ($exitCode -eq 0) {
                    return [pscustomobject]@{
                        Method    = "ookla-speedtest"
                        Adapter   = $adapterName
                        Category  = $category
                        SourceIp  = $sourceIp
                        Mode      = ($args -join " ")
                        Raw       = $raw
                        ExitCode  = $exitCode
                    }
                }
            }

            return [pscustomobject]@{
                Method    = "ookla-speedtest"
                Adapter   = $adapterName
                Category  = $category
                SourceIp  = $sourceIp
                Mode      = "failed"
                Raw       = $raw
                ExitCode  = $exitCode
            }
        } -ArgumentList $speedtestPath, $adapter.Name, $adapter.Category, $adapter.SourceIp, $serverId
        $jobs.Add($job)
    }
}
else {
    $methodUsed = "gateway-only"
    Write-ToolkitStatus "Neither iperf3 nor Ookla Speedtest CLI was found. Only gateway/DNS diagnostics were run." -Level Warn
}

$speedResults = @()
if ($jobs.Count -gt 0) {
    Write-ToolkitStatus "Waiting for concurrent network tests to finish..."
    $null = $jobs | Wait-Job
    $jobOutput = @($jobs | Receive-Job)
    $jobs | Remove-Job -Force | Out-Null

    foreach ($item in $jobOutput) {
        if ($item.Method -eq "iperf3") {
            $download = Convert-IperfRaw -Raw $item.DownloadRaw -Direction download
            $upload = Convert-IperfRaw -Raw $item.UploadRaw -Direction upload
            $downloadExitCode = if ($item.DownloadExit -ne $null) { [int]$item.DownloadExit } else { $null }
            $uploadExitCode = if ($item.UploadExit -ne $null) { [int]$item.UploadExit } else { $null }
            $notes = New-Object System.Collections.Generic.List[string]

            if ($downloadExitCode -ne 0) {
                $notes.Add("download exit $downloadExitCode")
            }

            if ($uploadExitCode -ne 0) {
                $notes.Add("upload exit $uploadExitCode")
            }

            if ($download -and $download.Error) {
                $notes.Add("download $($download.Error)")
            }

            if ($upload -and $upload.Error) {
                $notes.Add("upload $($upload.Error)")
            }

            if (-not $download -and -not $upload) {
                $notes.Add("no parseable iperf3 JSON")
            }

            $speedResults += [pscustomobject]@{
                Method       = $item.Method
                Adapter      = $item.Adapter
                Category     = $item.Category
                SourceIp     = $item.SourceIp
                Server       = $item.Server
                DownloadMbps = if ($download -and $download.Mbps -ne $null) { $download.Mbps } else { $null }
                UploadMbps   = if ($upload -and $upload.Mbps -ne $null) { $upload.Mbps } else { $null }
                PingMs       = $null
                PacketLoss   = $null
                DownloadExitCode = $downloadExitCode
                UploadExitCode   = $uploadExitCode
                DownloadJsonParsed = [bool]$download
                UploadJsonParsed   = [bool]$upload
                DownloadPreview = if ($downloadExitCode -ne 0 -or -not $download) { ($item.DownloadRaw | Out-String).Trim().Substring(0, [Math]::Min(220, (($item.DownloadRaw | Out-String).Trim()).Length)) } else { $null }
                UploadPreview   = if ($uploadExitCode -ne 0 -or -not $upload) { ($item.UploadRaw | Out-String).Trim().Substring(0, [Math]::Min(220, (($item.UploadRaw | Out-String).Trim()).Length)) } else { $null }
                Notes        = if ($notes.Count -gt 0) { "iperf3 " + ($notes -join "; ") + "." } else { $null }
            }
        }
        elseif ($item.Method -eq "ookla-speedtest") {
            $converted = Convert-SpeedtestRaw -Raw $item.Raw
            $speedResults += [pscustomobject]@{
                Method       = $item.Method
                Adapter      = $item.Adapter
                Category     = $item.Category
                SourceIp     = $item.SourceIp
                Server       = if ($converted) { $converted.Server } else { $null }
                DownloadMbps = if ($converted) { $converted.DownloadMbps } else { $null }
                UploadMbps   = if ($converted) { $converted.UploadMbps } else { $null }
                PingMs       = if ($converted) { $converted.PingMs } else { $null }
                PacketLoss   = if ($converted) { $converted.PacketLoss } else { $null }
                Notes        = if ($item.Mode -eq "failed") { "All Speedtest CLI binding attempts failed." } else { $item.Mode }
            }
        }
    }
}

$issues = New-Object System.Collections.Generic.List[string]
if ($methodUsed -eq "gateway-only") {
    if ($iperfMissingSupportFiles.Count -gt 0) {
        $issues.Add("The bundled iperf3 files are incomplete. Restore iperf3.exe together with cygcrypto-3.dll, cygwin1.dll, and cygz.dll in the tools folder, or put speedtest.exe in the tools folder as a fallback.")
    }
    else {
        $issues.Add("No throughput tool was found. Restore the bundled iperf3 files in the tools folder, or put speedtest.exe in the tools folder as a fallback.")
    }
}

foreach ($latency in $latencyChecks) {
    if ($latency.LossPercent -gt 0) {
        $issues.Add("$($latency.Adapter) has packet loss to its gateway ($($latency.LossPercent)%).")
    }
    elseif ($latency.AverageMs -gt 20) {
        $issues.Add("$($latency.Adapter) gateway latency is higher than expected at $($latency.AverageMs) ms.")
    }
    elseif ($latency.Notes) {
        $issues.Add("$($latency.Adapter): $($latency.Notes)")
    }
}

foreach ($speedResult in $speedResults) {
    if (-not $speedResult.DownloadMbps) {
        $issues.Add("$($speedResult.Adapter) did not return a usable speed result.")
    }
}

$bestByCategory = $speedResults |
    Where-Object { $_.DownloadMbps } |
    Group-Object Category |
    ForEach-Object {
        $_.Group | Sort-Object DownloadMbps -Descending | Select-Object -First 1
    }

$comparison = $null
$wifiBest = @($bestByCategory | Where-Object { $_.Category -eq "Wi-Fi" }) | Select-Object -First 1
$ethernetBest = @($bestByCategory | Where-Object { $_.Category -eq "Ethernet" }) | Select-Object -First 1

if ($wifiBest -and $ethernetBest) {
    if ($wifiBest.DownloadMbps -gt $ethernetBest.DownloadMbps) {
        $comparison = "Wi-Fi tested faster than Ethernet on download throughput."
    }
    elseif ($ethernetBest.DownloadMbps -gt $wifiBest.DownloadMbps) {
        $comparison = "Ethernet tested faster than Wi-Fi on download throughput."
    }
    else {
        $comparison = "Wi-Fi and Ethernet were effectively tied on download throughput."
    }
}

$report = [ordered]@{
    Script          = "Invoke-NetworkTest.ps1"
    RanAt           = (Get-Date).ToString("s")
    MethodUsed      = $methodUsed
    Adapters        = @($adapters)
    LatencyChecks   = @($latencyChecks)
    SpeedResults    = @($speedResults)
    Comparison      = $comparison
    Issues          = @($issues)
    Tooling         = @{
        IperfPath     = $iperfPath
        SpeedtestPath = $speedtestPath
    }
}

if ($comparison) {
    Write-ToolkitStatus $comparison -Level Success
}

if ($issues.Count -gt 0) {
    Write-ToolkitStatus "Network issues were detected. Check the JSON report for detail." -Level Warn
}
else {
    Write-ToolkitStatus "No obvious network issues were detected." -Level Success
}

Save-ToolkitJson -Path $reportPath -Data $report
Write-ToolkitStatus "Network report saved to $reportPath" -Level Success

if ($issues.Count -gt 0) {
    exit 2
}
