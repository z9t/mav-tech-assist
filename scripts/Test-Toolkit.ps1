[CmdletBinding()]
param(
    [string]$Root = "",

    [switch]$StartDashboard,

    [switch]$CheckBundle,

    [switch]$CheckHostedSite,

    [string]$HostedBaseUrl = "https://showtime.mav.z9t.me",

    [int]$Port = 8797
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:failures.Add($Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Add-Pass {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Add-Info {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Test-PowerShellSyntax {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Include "*.ps1", "*.psm1" -Recurse -File)
    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            foreach ($parseError in $parseErrors) {
                Add-Failure "$($file.Name): $($parseError.Message)"
            }
        }
        else {
            Add-Pass "PowerShell syntax: $($file.Name)"
        }
    }
}

function Test-JsonConfig {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root "config") -Filter "*.json" -File)
    foreach ($file in $files) {
        try {
            $null = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            Add-Pass "JSON config: $($file.Name)"
        }
        catch {
            Add-Failure "$($file.Name): $($_.Exception.Message)"
        }
    }
}

function Test-StaticSiteFiles {
    $checks = @(
        @{
            Path = "web\index.html"
            Text = "MAV Tech Assist"
        },
        @{
            Path = "web\index.html"
            Text = "MAV_LOCAL_HELPER"
        },
        @{
            Path = "web\index.html"
            Text = "laptop-desktop"
        },
        @{
            Path = "web\index.html"
            Text = "Download USB zip"
        },
        @{
            Path = "web\event-timer.html"
            Text = "Event Timer"
        },
        @{
            Path = "web\event-timer.html"
            Text = "timerMode"
        },
        @{
            Path = "web\desktop-generator.html"
            Text = "Desktop Generator"
        },
        @{
            Path = "web\desktop-generator.html"
            Text = "backgroundStyle"
        },
        @{
            Path = "web\assets\mav-logo.png"
            Text = ""
        },
        @{
            Path = "web\test-pattern-generator.html"
            Text = "Test Pattern Generator"
        },
        @{
            Path = "web\test-pattern-generator.html"
            Text = "patternMode"
        },
        @{
            Path = "web\led-wall-test-generator.html"
            Text = "LED Wall Test Generator"
        },
        @{
            Path = "web\led-wall-test-generator.html"
            Text = "panelWidth"
        },
        @{
            Path = "web\network-helper.html"
            Text = "Local Network Helper"
        },
        @{
            Path = "web\network-helper.html"
            Text = "Start monitoring"
        },
        @{
            Path = "docs\daily-use.html"
            Text = "Daily Use Guide"
        },
        @{
            Path = "docs\troubleshooting.html"
            Text = "Troubleshooting Guide"
        },
        @{
            Path = "docs\deployment-and-qa.html"
            Text = "Deployment And QA Guide"
        }
    )

    foreach ($check in $checks) {
        $path = Join-Path $Root $check.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Missing static file: $($check.Path)"
            continue
        }

        if ([string]::IsNullOrEmpty($check.Text)) {
            Add-Pass "Static file present: $($check.Path)"
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content -notlike "*$($check.Text)*") {
            Add-Failure "$($check.Path) does not contain expected marker: $($check.Text)"
            continue
        }

        Add-Pass "Static marker: $($check.Path) -> $($check.Text)"
    }
}

function Test-DocumentationFiles {
    $checks = @(
        @{
            Path = "README.md"
            Text = "# MAV Tech Assist"
        },
        @{
            Path = "docs\README.md"
            Text = "# MAV Tech Assist"
        },
        @{
            Path = "docs\DAILY_USE_GUIDE.md"
            Text = "# Daily Use Guide"
        },
        @{
            Path = "docs\TROUBLESHOOTING_GUIDE.md"
            Text = "# Troubleshooting Guide"
        },
        @{
            Path = "docs\DEPLOYMENT_AND_QA_GUIDE.md"
            Text = "# Deployment And QA Guide"
        },
        @{
            Path = "docs\LOCAL_NETWORK_HELPER.md"
            Text = "# Local Network Helper"
        },
        @{
            Path = "docs\SELF_HOSTED_INSTALL.md"
            Text = "# Self-Hosted Install"
        },
        @{
            Path = "docs\MAV_Z9T_INSTALL_AND_USAGE.md"
            Text = "# MAV.Z9T.ME Install And Usage"
        }
    )

    foreach ($check in $checks) {
        $path = Join-Path $Root $check.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Missing documentation file: $($check.Path)"
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content -notlike "*$($check.Text)*") {
            Add-Failure "$($check.Path) does not contain expected marker: $($check.Text)"
            continue
        }

        Add-Pass "Documentation marker: $($check.Path) -> $($check.Text)"
    }
}

function Test-RepositoryFiles {
    $checks = @(
        @{
            Path = ".gitignore"
            Text = "MAV-Tech-Assist-USB.zip"
        },
        @{
            Path = "requirements.txt"
            Text = "no required Python packages"
        }
    )

    foreach ($check in $checks) {
        $path = Join-Path $Root $check.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Missing repository file: $($check.Path)"
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content -notlike "*$($check.Text)*") {
            Add-Failure "$($check.Path) does not contain expected marker: $($check.Text)"
            continue
        }

        Add-Pass "Repository marker: $($check.Path) -> $($check.Text)"
    }
}

function Test-BundledTools {
    $checks = @(
        "tools\iperf3.exe",
        "tools\cygcrypto-3.dll",
        "tools\cygwin1.dll",
        "tools\cygz.dll",
        "tools\iperf3-source.txt"
    )

    foreach ($relativePath in $checks) {
        $path = Join-Path $Root $relativePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Add-Pass "Bundled tool present: $relativePath"
        }
        else {
            Add-Failure "Missing bundled tool file: $relativePath"
        }
    }
}

function Test-UsbBundle {
    $bundlePath = Join-Path $Root "MAV-Tech-Assist-USB.zip"
    if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
        Add-Failure "Missing USB bundle: MAV-Tech-Assist-USB.zip"
        return
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($bundlePath)
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $expectedEntries = @(
            "launchers/0-Dashboard.cmd",
            "launchers/0-Offline-Browser-Portal.cmd",
            "launchers/1-Declientify.cmd",
            "launchers/2-Network-Test.cmd",
            "launchers/3-Pre-Hire-Prep.cmd",
            "launchers/4-Baseline-Audit.cmd",
            "launchers/5-LED-Wall-Test-Generator.cmd",
            "launchers/6-Local-Network-Helper.cmd",
            "launchers/7-Desktop-Generator.cmd",
            "launchers/8-Test-Pattern-Generator.cmd",
            "launchers/9-Event-Timer.cmd",
            "scripts/Test-Toolkit.ps1",
            "scripts/Build-UsbBundle.ps1",
            "config/baseline-programs.json",
            "config/network-servers.json",
            "docs/README.md",
            "docs/DAILY_USE_GUIDE.md",
            "docs/TROUBLESHOOTING_GUIDE.md",
            "docs/DEPLOYMENT_AND_QA_GUIDE.md",
            "docs/LOCAL_NETWORK_HELPER.md",
            "docs/SELF_HOSTED_INSTALL.md",
            "docs/MAV_Z9T_INSTALL_AND_USAGE.md",
            "docs/handbook.css",
            "docs/daily-use.html",
            "docs/troubleshooting.html",
            "docs/deployment-and-qa.html",
            "tools/iperf3.exe",
            "tools/cygcrypto-3.dll",
            "tools/cygwin1.dll",
            "tools/cygz.dll",
            "tools/iperf3-source.txt",
            "web/index.html",
            "web/desktop-generator.html",
            "web/test-pattern-generator.html",
            "web/event-timer.html",
            "web/led-wall-test-generator.html",
            "web/network-helper.html",
            "web/assets/mav-logo.png"
        )

        foreach ($entry in $expectedEntries) {
            if ($entryNames -contains $entry) {
                Add-Pass "USB bundle entry: $entry"
            }
            else {
                Add-Failure "USB bundle missing expected entry: $entry"
            }
        }

        if ($entryNames -contains "web/MAV-Tech-Assist-USB.zip") {
            Add-Failure "USB bundle incorrectly contains a nested web/MAV-Tech-Assist-USB.zip"
        }
        else {
            Add-Pass "USB bundle does not contain a nested zip copy."
        }
    }
    catch {
        Add-Failure "Could not read USB bundle: $($_.Exception.Message)"
    }
    finally {
        if ($archive) {
            $archive.Dispose()
        }
    }
}

function Test-HostedSite {
    $baseUrl = $HostedBaseUrl.TrimEnd('/')
    $pageChecks = @(
        @{
            Path = "/"
            Text = "MAV Tech Assist"
        },
        @{
            Path = "/"
            Text = "Run Online"
        },
        @{
            Path = "/"
            Text = "Or from USB"
        },
        @{
            Path = "/desktop-generator.html"
            Text = "Desktop Generator"
        },
        @{
            Path = "/test-pattern-generator.html"
            Text = "Test Pattern Generator"
        },
        @{
            Path = "/event-timer.html"
            Text = "Event Timer"
        },
        @{
            Path = "/led-wall-test-generator.html"
            Text = "LED Wall Test Generator"
        },
        @{
            Path = "/network-helper.html"
            Text = "Local Network Helper"
        },
        @{
            Path = "/docs/daily-use.html"
            Text = "Daily Use Guide"
        },
        @{
            Path = "/docs/troubleshooting.html"
            Text = "Troubleshooting Guide"
        },
        @{
            Path = "/docs/deployment-and-qa.html"
            Text = "Deployment And QA Guide"
        }
    )

    foreach ($check in $pageChecks) {
        $uri = "$baseUrl$($check.Path)"

        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 8
        }
        catch {
            Add-Failure "Hosted site request failed for ${uri}: $($_.Exception.Message)"
            continue
        }

        if ($response.Content -notlike "*$($check.Text)*") {
            Add-Failure "Hosted site marker missing for ${uri}: $($check.Text)"
            continue
        }

        Add-Pass "Hosted site marker: $uri -> $($check.Text)"
    }

    $zipUri = "$baseUrl/MAV-Tech-Assist-USB.zip"
    $zipTempPath = Join-Path $env:TEMP "mav-tech-assist-smoke.zip"
    Remove-Item -LiteralPath $zipTempPath -Force -ErrorAction SilentlyContinue

    try {
        $zipResponse = Invoke-WebRequest -Uri $zipUri -UseBasicParsing -TimeoutSec 15 -OutFile $zipTempPath
        $zipInfo = Get-Item -LiteralPath $zipTempPath -ErrorAction Stop

        if ($zipInfo.Length -gt 0) {
            Add-Pass "Hosted USB bundle download: $zipUri ($($zipInfo.Length) bytes)"
        }
        else {
            Add-Failure "Hosted USB bundle download was empty: $zipUri"
        }
    }
    catch {
        Add-Failure "Hosted USB bundle download failed for ${zipUri}: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $zipTempPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-DashboardServer {
    $dashboard = Join-Path $Root "scripts\Start-Dashboard.ps1"
    $stdout = Join-Path $env:TEMP "mav-dashboard-test.stdout.log"
    $stderr = Join-Path $env:TEMP "mav-dashboard-test.stderr.log"

    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$dashboard`" -Port $Port -NoBrowser"
    $process = $null

    try {
        $process = Start-Process `
            -FilePath $powershell `
            -ArgumentList $arguments `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $indexResponse = $null
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            try {
                $indexResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 2
                break
            }
            catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if (-not $indexResponse) {
            Add-Failure "Dashboard server did not respond on port $Port."
            if (Test-Path -LiteralPath $stderr) {
                Add-Info (Get-Content -LiteralPath $stderr -Raw)
            }
            return
        }

        $dashboardToken = $null
        if ($indexResponse.Content -match "MAV_LOCAL_HELPER") {
            Add-Pass "Dashboard injects local helper config."
            $tokenMatch = [regex]::Match($indexResponse.Content, "token:'([A-Za-z0-9]+)'")
            if ($tokenMatch.Success) {
                $dashboardToken = $tokenMatch.Groups[1].Value
            }
        }
        else {
            Add-Failure "Dashboard index did not include local helper config."
        }

        $ledResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/led-wall-test-generator.html" -UseBasicParsing -TimeoutSec 4
        if ($ledResponse.Content -match "LED Wall Test Generator") {
            Add-Pass "Dashboard serves LED wall page."
        }
        else {
            Add-Failure "Dashboard LED wall page response was unexpected."
        }

        $desktopResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/desktop-generator.html" -UseBasicParsing -TimeoutSec 4
        if ($desktopResponse.Content -match "Desktop Generator") {
            Add-Pass "Dashboard serves desktop generator page."
        }
        else {
            Add-Failure "Dashboard desktop generator page response was unexpected."
        }

        $patternResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/test-pattern-generator.html" -UseBasicParsing -TimeoutSec 4
        if ($patternResponse.Content -match "Test Pattern Generator") {
            Add-Pass "Dashboard serves test pattern generator page."
        }
        else {
            Add-Failure "Dashboard test pattern generator page response was unexpected."
        }

        $timerResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/event-timer.html" -UseBasicParsing -TimeoutSec 4
        if ($timerResponse.Content -match "Event Timer") {
            Add-Pass "Dashboard serves event timer page."
        }
        else {
            Add-Failure "Dashboard event timer page response was unexpected."
        }

        $networkHelperResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/network-helper.html" -UseBasicParsing -TimeoutSec 4
        if ($networkHelperResponse.Content -match "Local Network Helper") {
            Add-Pass "Dashboard serves local network helper page."
        }
        else {
            Add-Failure "Dashboard network helper page response was unexpected."
        }

        $taskResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/tasks" -UseBasicParsing -TimeoutSec 4
        $tasks = $taskResponse.Content | ConvertFrom-Json
        if (@($tasks.tasks).Count -gt 0) {
            Add-Pass "Dashboard task API returned $(@($tasks.tasks).Count) tasks."
        }
        else {
            Add-Failure "Dashboard task API returned no tasks."
        }

        if ($dashboardToken) {
            $discoverBody = "payload=%7B%22cidr%22%3A%22192.0.2.0%2F30%22%7D"
            $discoverResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/network-helper/discover?token=$dashboardToken" -UseBasicParsing -TimeoutSec 12 -Method Post -ContentType "application/x-www-form-urlencoded" -Body $discoverBody
            $discoverData = $discoverResponse.Content | ConvertFrom-Json
            if ($discoverData.Mode -eq "Discover" -and $discoverData.Scan) {
                Add-Pass "Network helper discover API returned a scan payload."
            }
            else {
                Add-Failure "Network helper discover API response was unexpected."
            }

            $probeBody = "payload=%7B%22targets%22%3A%5B%5D%7D"
            $probeResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/network-helper/probe?token=$dashboardToken" -UseBasicParsing -TimeoutSec 8 -Method Post -ContentType "application/x-www-form-urlencoded" -Body $probeBody
            $probeData = $probeResponse.Content | ConvertFrom-Json
            if ($probeData.Mode -eq "Probe" -and $probeData.Summary.TargetCount -eq 0) {
                Add-Pass "Network helper probe API returned an empty watch response."
            }
            else {
                Add-Failure "Network helper probe API response was unexpected."
            }

            $setupBody = "payload=%7B%22enableNetworkDiscovery%22%3Atrue%2C%22dryRun%22%3Atrue%7D"
            $setupResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/network-helper/setup?token=$dashboardToken" -UseBasicParsing -TimeoutSec 15 -Method Post -ContentType "application/x-www-form-urlencoded" -Body $setupBody
            $setupData = $setupResponse.Content | ConvertFrom-Json
            if ($setupData.Mode -eq "Setup" -and $setupData.DryRun -eq $true) {
                Add-Pass "Network helper setup API returned dry-run results."
            }
            else {
                Add-Failure "Network helper setup API response was unexpected."
            }
        }
        else {
            Add-Failure "Could not extract the dashboard helper token from index.html."
        }
    }
    finally {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

Add-Info "Testing toolkit at $Root"
Test-PowerShellSyntax
Test-JsonConfig
Test-StaticSiteFiles
Test-DocumentationFiles
Test-RepositoryFiles
Test-BundledTools

if ($StartDashboard) {
    Test-DashboardServer
}
else {
    Add-Info "Skipping dashboard server smoke test. Pass -StartDashboard to include it."
}

if ($CheckBundle) {
    Test-UsbBundle
}
else {
    Add-Info "Skipping USB bundle smoke test. Pass -CheckBundle to include it."
}

if ($CheckHostedSite) {
    Test-HostedSite
}
else {
    Add-Info "Skipping hosted site smoke test. Pass -CheckHostedSite to include it."
}

if ($failures.Count -gt 0) {
    Write-Host "[RESULT] $($failures.Count) failure(s)." -ForegroundColor Red
    exit 1
}

Write-Host "[RESULT] All tests passed." -ForegroundColor Green
