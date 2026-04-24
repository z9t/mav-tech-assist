[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$reportPath = New-ToolkitReportPath -Category "declientify" -ToolkitRoot $toolkitRoot
$timestamp = Get-ToolkitTimestamp
$archiveRoot = Join-Path $env:PUBLIC "Documents\MAV\ArchivedProfiles\$timestamp"
if (-not $DryRun) {
    $archiveRoot = Ensure-ToolkitDirectory -Path $archiveRoot
}

$browserTargets = @(
    @{
        Name      = "Microsoft Edge"
        Processes = @("msedge")
        Paths     = @(
            (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data")
        )
    },
    @{
        Name      = "Google Chrome"
        Processes = @("chrome")
        Paths     = @(
            (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data")
        )
    },
    @{
        Name      = "Mozilla Firefox"
        Processes = @("firefox")
        Paths     = @(
            (Join-Path $env:APPDATA "Mozilla\Firefox\Profiles")
        )
    },
    @{
        Name      = "Brave"
        Processes = @("brave")
        Paths     = @(
            (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data")
        )
    }
)

$report = [ordered]@{
    Script                = "Invoke-Declientify.ps1"
    RanAt                 = (Get-Date).ToString("s")
    DryRun                = [bool]$DryRun
    ArchiveRoot           = $archiveRoot
    Microsoft365Before    = $null
    Microsoft365After     = $null
    ArchivedBrowserStores = @()
    Notes                 = @(
        "Browser profile stores are moved out of the active path so web logins are cleared without touching Microsoft 365 desktop activation."
    )
}

Write-ToolkitStatus "Checking Microsoft 365 status before browser cleanup..."
$m365Before = Get-Microsoft365State
$report.Microsoft365Before = $m365Before

if ($m365Before.IsLicensed) {
    $emailText = if ($m365Before.Emails.Count -gt 0) { $m365Before.Emails -join ", " } else { "licensed account detected, email not exposed" }
    Write-ToolkitStatus "Microsoft 365 appears licensed: $emailText" -Level Success
}
else {
    Write-ToolkitStatus "Microsoft 365 does not look licensed or signed in. This is worth checking in Word or PowerPoint before handover." -Level Warn
}

if ($DryRun) {
    Write-ToolkitStatus "Dry run: browser processes will not be closed and profiles will not be moved." -Level Warn
}
else {
    $processNames = $browserTargets.Processes | Sort-Object -Unique
    Write-ToolkitStatus "Closing browser processes: $($processNames -join ', ')"
    Stop-ToolkitProcesses -Names $processNames
}

foreach ($target in $browserTargets) {
    foreach ($path in $target.Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $safeName = $target.Name -replace "[^A-Za-z0-9]+", "-"
        $destinationRoot = Join-Path $archiveRoot $safeName
        if (-not $DryRun) {
            $destinationRoot = Ensure-ToolkitDirectory -Path $destinationRoot
        }
        $destinationPath = Join-Path $destinationRoot (Split-Path -Leaf $path)

        if ($DryRun) {
            Write-ToolkitStatus "Dry run: would archive $($target.Name) profile store from $path"
        }
        else {
            Write-ToolkitStatus "Archiving $($target.Name) profile store from $path"
            Move-Item -LiteralPath $path -Destination $destinationPath -Force
        }

        $report.ArchivedBrowserStores += [pscustomobject]@{
            Browser     = $target.Name
            Source      = $path
            Destination = $destinationPath
            Action      = if ($DryRun) { "WouldArchive" } else { "Archived" }
        }
    }
}

if ($DryRun) {
    Write-ToolkitStatus "Dry run: using the pre-check Microsoft 365 state as the after-state."
    $m365After = $m365Before
}
else {
    Write-ToolkitStatus "Re-checking Microsoft 365 status after browser cleanup..."
    $m365After = Get-Microsoft365State
}
$report.Microsoft365After = $m365After

if ($m365After.IsLicensed) {
    Write-ToolkitStatus "Microsoft 365 still appears licensed after declientify." -Level Success
}
else {
    Write-ToolkitStatus "Microsoft 365 could not be confirmed after declientify. Open Word > File > Account to confirm before the next hire." -Level Warn
}

Save-ToolkitJson -Path $reportPath -Data $report
Write-ToolkitStatus "Declientify report saved to $reportPath" -Level Success

if ((-not $DryRun) -and (-not $m365After.IsLicensed)) {
    exit 2
}
