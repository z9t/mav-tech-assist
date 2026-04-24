[CmdletBinding()]
param(
    [ValidateSet("Discover", "Probe", "Setup")]
    [string]$Mode = "Discover",

    [string]$Cidr,

    [string]$InputPath,

    [switch]$EnableSshServer,

    [switch]$EnableFileSharing,

    [switch]$EnableNetworkDiscovery,

    [switch]$PreferPrivateNetworkProfile,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

function ConvertTo-IPv4Integer {
    param(
        [Parameter(Mandatory)]
        [string]$Address
    )

    $ip = [System.Net.IPAddress]::Parse($Address)
    $bytes = $ip.GetAddressBytes()
    if ($bytes.Length -ne 4) {
        throw "Only IPv4 addresses are supported."
    }

    [array]::Reverse($bytes)
    return [System.BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-IPv4Integer {
    param(
        [Parameter(Mandatory)]
        [uint32]$Value
    )

    $bytes = [System.BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-NetworkHelperConfig {
    $toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
    $configPath = Join-Path $toolkitRoot "config\network-helper-signatures.json"
    return Read-ToolkitJson -Path $configPath
}

function Get-ActiveNetworkSummaries {
    $rawAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq "Up" -and $_.HardwareInterface -and $_.InterfaceDescription -notmatch "(?i)virtual|vpn|hyper-v|bluetooth|loopback"
        })

    $summaries = foreach ($adapter in $rawAdapters) {
        $ipv4 = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254*" } |
            Select-Object -First 1

        if (-not $ipv4) {
            continue
        }

        $prefixLength = [int]$ipv4.PrefixLength
        $addressInt = ConvertTo-IPv4Integer -Address $ipv4.IPAddress
        $maskInt = if ($prefixLength -eq 0) {
            [uint32]0
        }
        else {
            [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefixLength))
        }

        $networkInt = $addressInt -band $maskInt
        $networkAddress = ConvertFrom-IPv4Integer -Value $networkInt
        $suggestedPrefix = if ($prefixLength -lt 24) { 24 } else { $prefixLength }
        if ($suggestedPrefix -gt 30) {
            $suggestedPrefix = 30
        }

        $suggestedMaskInt = if ($suggestedPrefix -eq 0) {
            [uint32]0
        }
        else {
            [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $suggestedPrefix))
        }
        $suggestedNetworkInt = $addressInt -band $suggestedMaskInt

        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue

        [pscustomobject]@{
            AdapterName    = $adapter.Name
            InterfaceIndex = $adapter.ifIndex
            IpAddress      = $ipv4.IPAddress
            PrefixLength   = $prefixLength
            NetworkAddress = $networkAddress
            Gateway        = if ($ipConfig.IPv4DefaultGateway) { $ipConfig.IPv4DefaultGateway.NextHop } else { $null }
            DnsServers     = if ($ipConfig.DNSServer) { @($ipConfig.DNSServer.ServerAddresses) } else { @() }
            SuggestedCidr  = "{0}/{1}" -f (ConvertFrom-IPv4Integer -Value $suggestedNetworkInt), $suggestedPrefix
        }
    }

    return @($summaries)
}

function Resolve-ScanRange {
    param(
        [string]$RequestedCidr,

        [Parameter(Mandatory)]
        [int]$MaxHosts,

        [Parameter(Mandatory)]
        [object[]]$ActiveNetworks
    )

    $notes = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($RequestedCidr)) {
        $defaultNetwork = @($ActiveNetworks | Select-Object -First 1)
        if ($defaultNetwork.Count -eq 0) {
            return [pscustomobject]@{
                RequestedCidr = $null
                EffectiveCidr = $null
                Addresses     = @()
                TotalHosts    = 0
                Notes         = @("No active IPv4 network was detected. Enter a CIDR range manually.")
            }
        }

        $RequestedCidr = [string]$defaultNetwork[0].SuggestedCidr
        $notes.Add("No CIDR was supplied. Using $RequestedCidr from the first active adapter.")
    }

    if ($RequestedCidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        throw "CIDR must look like 10.0.0.0/24."
    }

    $baseAddress = $Matches[1]
    $prefixLength = [int]$Matches[2]
    if ($prefixLength -lt 16 -or $prefixLength -gt 30) {
        throw "CIDR prefix must be between /16 and /30 for this helper."
    }

    $baseInt = ConvertTo-IPv4Integer -Address $baseAddress
    $maskInt = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefixLength))
    $networkInt = $baseInt -band $maskInt
    $usableHosts = [math]::Max(0, [int]([math]::Pow(2, 32 - $prefixLength) - 2))
    $scanHostCount = [math]::Min($usableHosts, $MaxHosts)

    if ($usableHosts -gt $MaxHosts) {
        $notes.Add("The requested range has $usableHosts usable hosts. Only the first $MaxHosts will be scanned.")
    }

    $addresses = New-Object System.Collections.Generic.List[string]
    for ($offset = 1; $offset -le $scanHostCount; $offset++) {
        $addresses.Add((ConvertFrom-IPv4Integer -Value ([uint32]($networkInt + $offset))))
    }

    return [pscustomobject]@{
        RequestedCidr = $RequestedCidr
        EffectiveCidr = "{0}/{1}" -f (ConvertFrom-IPv4Integer -Value $networkInt), $prefixLength
        Addresses     = @($addresses.ToArray())
        TotalHosts    = $usableHosts
        Notes         = @($notes.ToArray())
    }
}

function Invoke-PingSweep {
    param(
        [Parameter(Mandatory)]
        [string[]]$Addresses,

        [int]$TimeoutMs = 220,

        [int]$BatchSize = 64
    )

    $alive = New-Object System.Collections.Generic.List[object]
    $buffer = [System.Text.Encoding]::ASCII.GetBytes("mav")
    $pingOptions = [System.Net.NetworkInformation.PingOptions]::new(64, $false)

    for ($start = 0; $start -lt $Addresses.Count; $start += $BatchSize) {
        $end = [int][math]::Min($start + $BatchSize - 1, $Addresses.Count - 1)
        $batch = @($Addresses[$start..$end])
        $entries = foreach ($address in $batch) {
            $ping = [System.Net.NetworkInformation.Ping]::new()
            [pscustomobject]@{
                Address = $address
                Ping    = $ping
                Task    = $ping.SendPingAsync($address, $TimeoutMs, $buffer, $pingOptions)
            }
        }

        Start-Sleep -Milliseconds ($TimeoutMs + 120)

        foreach ($entry in $entries) {
            try {
                if (-not $entry.Task.IsCompleted) {
                    continue
                }

                $reply = $entry.Task.GetAwaiter().GetResult()
                if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $alive.Add([pscustomobject]@{
                            Address    = $entry.Address
                            RoundtripMs = [int]$reply.RoundtripTime
                        })
                }
            }
            catch {
            }
            finally {
                $entry.Ping.Dispose()
            }
        }
    }

    return @($alive.ToArray())
}

function Get-ArpMap {
    $map = @{}
    $lines = @(arp -a 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+(([0-9a-f]{2}-){5}[0-9a-f]{2})\s+(\w+)\s*$') {
            $map[$Matches[1]] = [pscustomobject]@{
                MacAddress = $Matches[2].ToUpperInvariant()
                EntryType  = $Matches[4]
            }
        }
    }

    return $map
}

function Resolve-HostNameBestEffort {
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )

    try {
        $entry = [System.Net.Dns]::GetHostEntry($Target)
        if ($entry -and -not [string]::IsNullOrWhiteSpace($entry.HostName)) {
            return $entry.HostName
        }
    }
    catch {
    }

    return $null
}

function Test-TcpPortQuick {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$TimeoutMs = 140
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Get-OpenPortsQuick {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int[]]$Ports,

        [int]$TimeoutMs = 140
    )

    $openPorts = New-Object System.Collections.Generic.List[int]
    foreach ($port in @($Ports | Sort-Object -Unique)) {
        if (Test-TcpPortQuick -ComputerName $ComputerName -Port $port -TimeoutMs $TimeoutMs) {
            $openPorts.Add($port)
        }
    }

    return @($openPorts.ToArray())
}

function Get-PortLabels {
    param(
        [Parameter(Mandatory)]
        [int[]]$Ports,

        [Parameter(Mandatory)]
        $Config
    )

    $labels = foreach ($port in @($Ports | Sort-Object -Unique)) {
        $match = @($Config.ports | Where-Object { [int]$_.port -eq $port }) | Select-Object -First 1
        if ($match) {
            [pscustomobject]@{
                Port  = $port
                Label = [string]$match.label
            }
        }
        else {
            [pscustomobject]@{
                Port  = $port
                Label = "TCP"
            }
        }
    }

    return @($labels)
}

function Get-RolePorts {
    param(
        [string]$RoleId,

        [Parameter(Mandatory)]
        $Config
    )

    $hint = @($Config.roleHints | Where-Object { $_.id -eq $RoleId }) | Select-Object -First 1
    if (-not $hint) {
        return @()
    }

    return @(@($hint.requiredAnyPorts) + @($hint.preferredAnyPorts) | Sort-Object -Unique)
}

function Test-HostPatternMatch {
    param(
        [string]$Text,

        [string[]]$Patterns
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $lowerText = $Text.ToLowerInvariant()
    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            continue
        }

        if ($lowerText.Contains(([string]$pattern).ToLowerInvariant())) {
            return $true
        }
    }

    return $false
}

function Get-DeviceClassification {
    param(
        [string]$HostName,

        [int[]]$OpenPorts,

        [Parameter(Mandatory)]
        $Config
    )

    $best = $null
    $bestScore = -1

    foreach ($hint in $Config.roleHints) {
        $score = 0
        $reasons = New-Object System.Collections.Generic.List[string]
        $required = @($hint.requiredAnyPorts | ForEach-Object { [int]$_ })
        $preferred = @($hint.preferredAnyPorts | ForEach-Object { [int]$_ })
        $requiredMatches = @($OpenPorts | Where-Object { $required -contains $_ })
        $preferredMatches = @($OpenPorts | Where-Object { $preferred -contains $_ })

        if ($requiredMatches.Count -gt 0) {
            $score += 5
            $reasons.Add("Matched key ports: $($requiredMatches -join ', ')")
        }

        if ($preferredMatches.Count -gt 0) {
            $score += [math]::Min(4, $preferredMatches.Count * 2)
            $reasons.Add("Matched helper ports: $($preferredMatches -join ', ')")
        }

        if (Test-HostPatternMatch -Text $HostName -Patterns @($hint.hostnamePatterns)) {
            $score += 3
            $reasons.Add("Hostname looks like $($hint.label.ToLowerInvariant()).")
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = [pscustomobject]@{
                RoleId     = [string]$hint.id
                Label      = [string]$hint.label
                Score      = $score
                Confidence = if ($score -ge 8) { "high" } elseif ($score -ge 4) { "medium" } else { "low" }
                Reasons    = @($reasons.ToArray())
            }
        }
    }

    if (-not $best -or $best.Score -le 0) {
        return [pscustomobject]@{
            RoleId     = "generic"
            Label      = if ($OpenPorts.Count -gt 0) { "Reachable network device" } else { "Unknown device" }
            Score      = 0
            Confidence = "low"
            Reasons    = if ($OpenPorts.Count -gt 0) { @("The host answered on one or more common management ports.") } else { @("No identifying service ports were found.") }
        }
    }

    return $best
}

function Test-PingQuick {
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [int]$TimeoutMs = 220
    )

    $ping = [System.Net.NetworkInformation.Ping]::new()
    try {
        $reply = $ping.Send($Target, $TimeoutMs)
        if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return [pscustomobject]@{
                Reachable  = $true
                RoundtripMs = [int]$reply.RoundtripTime
            }
        }
    }
    catch {
    }
    finally {
        $ping.Dispose()
    }

    return [pscustomobject]@{
        Reachable  = $false
        RoundtripMs = $null
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SetupAction {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [bool]$IsAdministrator,

        [switch]$DryRun
    )

    if (-not $IsAdministrator) {
        return [pscustomobject]@{
            Name   = $Name
            State  = "needs-admin"
            Detail = "Run the dashboard as administrator for this step."
        }
    }

    if ($DryRun) {
        return [pscustomobject]@{
            Name   = $Name
            State  = "dry-run"
            Detail = "Dry run only. No change was applied."
        }
    }

    try {
        & $Action
        return [pscustomobject]@{
            Name   = $Name
            State  = "success"
            Detail = "Applied."
        }
    }
    catch {
        return [pscustomobject]@{
            Name   = $Name
            State  = "error"
            Detail = $_.Exception.Message
        }
    }
}

$config = Get-NetworkHelperConfig
$activeNetworks = @(Get-ActiveNetworkSummaries)

if ($Mode -eq "Discover") {
    $scanRange = Resolve-ScanRange -RequestedCidr $Cidr -MaxHosts ([int]$config.maxHostsPerScan) -ActiveNetworks $activeNetworks
    $aliveHosts = if (@($scanRange.Addresses).Count -gt 0) {
        @(Invoke-PingSweep -Addresses $scanRange.Addresses -TimeoutMs ([int]$config.pingTimeoutMs))
    }
    else {
        @()
    }

    $arpMap = Get-ArpMap
    $portsToProbe = @($config.ports | ForEach-Object { [int]$_.port })
    $probeLimit = [math]::Min([int]$config.maxPortProbeHosts, @($aliveHosts).Count)
    $probeTargets = @($aliveHosts | Sort-Object Address | Select-Object -First $probeLimit)
    $portLookup = @{}

    foreach ($aliveTarget in $probeTargets) {
        $portLookup[$aliveTarget.Address] = @(Get-OpenPortsQuick -ComputerName $aliveTarget.Address -Ports $portsToProbe -TimeoutMs ([int]$config.portTimeoutMs))
    }

    $devices = foreach ($aliveTarget in @($aliveHosts | Sort-Object { ConvertTo-IPv4Integer -Address $_.Address })) {
        $openPorts = if ($portLookup.ContainsKey($aliveTarget.Address)) { @($portLookup[$aliveTarget.Address]) } else { @() }
        $hostName = Resolve-HostNameBestEffort -Target $aliveTarget.Address
        $classification = Get-DeviceClassification -HostName $hostName -OpenPorts $openPorts -Config $config
        $arpEntry = if ($arpMap.ContainsKey($aliveTarget.Address)) { $arpMap[$aliveTarget.Address] } else { $null }

        [pscustomobject]@{
            IpAddress      = $aliveTarget.Address
            HostName       = $hostName
            Reachable      = $true
            RoundtripMs    = $aliveTarget.RoundtripMs
            MacAddress     = if ($arpEntry) { $arpEntry.MacAddress } else { $null }
            OpenPorts      = @($openPorts)
            PortLabels     = @(Get-PortLabels -Ports $openPorts -Config $config)
            LikelyRoleId   = $classification.RoleId
            LikelyRole     = $classification.Label
            Confidence     = $classification.Confidence
            Reasons        = @($classification.Reasons)
        }
    }

    $notes = New-Object System.Collections.Generic.List[string]
    foreach ($note in $scanRange.Notes) {
        $notes.Add($note)
    }
    if (@($aliveHosts).Count -gt $probeLimit) {
        $notes.Add("Open-port classification ran on the first $probeLimit reachable hosts only. Remaining hosts are listed as reachable without port detail.")
    }

    $result = [ordered]@{
        Script         = "Invoke-NetworkHelper.ps1"
        Mode           = "Discover"
        RanAt          = (Get-Date).ToString("s")
        ActiveNetworks = @($activeNetworks)
        Scan           = @{
            RequestedCidr = $scanRange.RequestedCidr
            EffectiveCidr = $scanRange.EffectiveCidr
            TotalHosts    = $scanRange.TotalHosts
            ScannedHosts  = @($scanRange.Addresses).Count
            AliveHosts    = @($aliveHosts).Count
            Notes         = @($notes.ToArray())
        }
        Devices        = @($devices)
    }

    $result | ConvertTo-Json -Depth 8
    exit 0
}

if ($Mode -eq "Probe") {
    $payload = if ($InputPath -and (Test-Path -LiteralPath $InputPath)) {
        Read-ToolkitJson -Path $InputPath
    }
    else {
        [pscustomobject]@{ targets = @() }
    }

    $targetsProperty = $payload.PSObject.Properties["targets"]
    $targets = if ($targetsProperty) { @($targetsProperty.Value) } else { @() }

    $results = foreach ($target in $targets) {
        $probeTarget = [string]$target.target
        if ([string]::IsNullOrWhiteSpace($probeTarget)) {
            continue
        }

        $roleId = [string]$target.roleId
        $expectedPorts = @($target.expectedPorts | ForEach-Object { [int]$_ })
        if (@($expectedPorts).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($roleId)) {
            $expectedPorts = @(Get-RolePorts -RoleId $roleId -Config $config)
        }
        if (@($expectedPorts).Count -eq 0) {
            $expectedPorts = @(22, 80, 443, 445, 554, 4352, 10023, 3389)
        }

        $ping = Test-PingQuick -Target $probeTarget -TimeoutMs ([int]$config.pingTimeoutMs)
        $openPorts = @(Get-OpenPortsQuick -ComputerName $probeTarget -Ports $expectedPorts -TimeoutMs ([int]$config.portTimeoutMs))
        $isUp = $ping.Reachable -or @($openPorts).Count -gt 0
        $hostName = Resolve-HostNameBestEffort -Target $probeTarget
        $classification = Get-DeviceClassification -HostName $hostName -OpenPorts $openPorts -Config $config
        $notes = New-Object System.Collections.Generic.List[string]

        if (-not $ping.Reachable -and @($openPorts).Count -gt 0) {
            $notes.Add("Ping may be blocked. The device still answered on one or more expected ports.")
        }

        [pscustomobject]@{
            Id            = [string]$target.id
            Name          = [string]$target.name
            Target        = $probeTarget
            Status        = if ($isUp) { "up" } else { "down" }
            Reachable     = $isUp
            RoundtripMs   = $ping.RoundtripMs
            HostName      = $hostName
            OpenPorts     = @($openPorts)
            PortLabels    = @(Get-PortLabels -Ports $openPorts -Config $config)
            LikelyRoleId  = $classification.RoleId
            LikelyRole    = $classification.Label
            Confidence    = $classification.Confidence
            CheckedAt     = (Get-Date).ToString("s")
            Notes         = @(@($notes.ToArray()) + @($classification.Reasons))
        }
    }

    $result = [ordered]@{
        Script  = "Invoke-NetworkHelper.ps1"
        Mode    = "Probe"
        RanAt   = (Get-Date).ToString("s")
        Summary = @{
            TargetCount = @($results).Count
            UpCount     = @(@($results) | Where-Object { $_.Status -eq "up" }).Count
            DownCount   = @(@($results) | Where-Object { $_.Status -eq "down" }).Count
        }
        Results = @($results)
    }

    $result | ConvertTo-Json -Depth 8
    exit 0
}

$isAdministrator = Test-IsAdministrator
$setupResults = New-Object System.Collections.Generic.List[object]
$networkProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity)

if ($PreferPrivateNetworkProfile) {
    $setupResults.Add((Invoke-SetupAction -Name "Prefer private network profile on active adapters" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                foreach ($profile in Get-NetConnectionProfile -ErrorAction Stop) {
                    if ($profile.NetworkCategory -eq "Public" -and $profile.IPv4Connectivity -ne "Disconnected") {
                        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                    }
                }
            }))
}

if ($EnableNetworkDiscovery) {
    $setupResults.Add((Invoke-SetupAction -Name "Enable Network Discovery firewall rules" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Get-NetFirewallRule -DisplayGroup "Network Discovery" -ErrorAction Stop | Set-NetFirewallRule -Enabled True -ErrorAction Stop
            }))
    $setupResults.Add((Invoke-SetupAction -Name "Start Function Discovery Provider Host" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Set-Service -Name fdPHost -StartupType Manual -ErrorAction Stop
                Start-Service -Name fdPHost -ErrorAction Stop
            }))
    $setupResults.Add((Invoke-SetupAction -Name "Start Function Discovery Resource Publication" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Set-Service -Name FDResPub -StartupType Automatic -ErrorAction Stop
                Start-Service -Name FDResPub -ErrorAction Stop
            }))
}

if ($EnableFileSharing) {
    $setupResults.Add((Invoke-SetupAction -Name "Enable File and Printer Sharing firewall rules" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction Stop | Set-NetFirewallRule -Enabled True -ErrorAction Stop
            }))
    $setupResults.Add((Invoke-SetupAction -Name "Start the Windows Server service" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Set-Service -Name LanmanServer -StartupType Automatic -ErrorAction Stop
                Start-Service -Name LanmanServer -ErrorAction Stop
            }))
}

if ($EnableSshServer) {
    $setupResults.Add((Invoke-SetupAction -Name "Install OpenSSH Server if needed" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                $capability = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like "OpenSSH.Server*" }) | Select-Object -First 1
                if (-not $capability) {
                    throw "OpenSSH Server capability was not found on this Windows image."
                }

                if ($capability.State -ne "Installed") {
                    Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
                }
            }))
    $setupResults.Add((Invoke-SetupAction -Name "Enable and start sshd" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
                Start-Service -Name sshd -ErrorAction Stop
            }))
    $setupResults.Add((Invoke-SetupAction -Name "Enable OpenSSH firewall rule" -IsAdministrator $isAdministrator -DryRun:$DryRun -Action {
                Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction Stop | Set-NetFirewallRule -Enabled True -ErrorAction Stop
            }))
}

$result = [ordered]@{
    Script          = "Invoke-NetworkHelper.ps1"
    Mode            = "Setup"
    RanAt           = (Get-Date).ToString("s")
    DryRun          = [bool]$DryRun
    IsAdministrator = [bool]$isAdministrator
    ComputerName    = $env:COMPUTERNAME
    UserName        = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    ActiveNetworks  = @($activeNetworks)
    NetworkProfiles = @($networkProfiles)
    Results         = @($setupResults.ToArray())
    Summary         = @{
        SuccessCount    = @(@($setupResults.ToArray()) | Where-Object { $_.State -eq "success" }).Count
        DryRunCount     = @(@($setupResults.ToArray()) | Where-Object { $_.State -eq "dry-run" }).Count
        NeedsAdminCount = @(@($setupResults.ToArray()) | Where-Object { $_.State -eq "needs-admin" }).Count
        ErrorCount      = @(@($setupResults.ToArray()) | Where-Object { $_.State -eq "error" }).Count
    }
    Notes           = @(
        "This setup only prepares the current Windows laptop. It does not log into or reconfigure peer devices on the LAN.",
        "File sharing setup enables discovery/firewall/service prerequisites only. It does not create or publish SMB shares for specific folders."
    )
}

$result | ConvertTo-Json -Depth 8
