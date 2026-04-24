[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$configPath = Join-Path $toolkitRoot "config\baseline-programs.json"
$reportPath = New-ToolkitReportPath -Category "baseline-audit" -ToolkitRoot $toolkitRoot
$config = Read-ToolkitJson -Path $configPath

Write-ToolkitStatus "Reading installed programs from Windows uninstall registry keys..."
$installedApps = @(Get-InstalledApplications)

$requiredMatches = foreach ($requiredPattern in $config.requiredPatterns) {
    $matches = @($installedApps | Where-Object {
            Test-StringMatchesPattern -Value $_.DisplayName -Patterns @($requiredPattern)
        })

    [pscustomobject]@{
        Pattern = $requiredPattern
        Matches = $matches
        Present = $matches.Count -gt 0
    }
}

$optionalPatterns = @($config.optionalPatterns)
$ignorePatterns = @($config.ignorePatterns)
$allKnownPatterns = @($config.requiredPatterns) + $optionalPatterns + $ignorePatterns

$unexpectedApps = @($installedApps | Where-Object {
        -not (Test-StringMatchesPattern -Value $_.DisplayName -Patterns $allKnownPatterns)
    })

$missingRequired = @($requiredMatches | Where-Object { -not $_.Present })

$report = [ordered]@{
    Script             = "Invoke-BaselineAudit.ps1"
    RanAt              = (Get-Date).ToString("s")
    ConfigPath         = $configPath
    InstalledCount     = $installedApps.Count
    MissingRequired    = @($missingRequired | Select-Object Pattern)
    UnexpectedPrograms = @($unexpectedApps | Select-Object DisplayName, DisplayVersion, Publisher)
    RequiredMatches    = @($requiredMatches | Select-Object Pattern, Present, @{ Name = "Matches"; Expression = { @($_.Matches | Select-Object DisplayName, DisplayVersion, Publisher) } })
}

if ($missingRequired.Count -eq 0) {
    Write-ToolkitStatus "Baseline required software looks present." -Level Success
}
else {
    Write-ToolkitStatus "Missing baseline apps: $($missingRequired.Pattern -join ', ')" -Level Warn
}

if ($unexpectedApps.Count -gt 0) {
    Write-ToolkitStatus "Unexpected apps found: $($unexpectedApps.Count). Check the report for details." -Level Warn
}
else {
    Write-ToolkitStatus "No unexpected apps were found outside the configured baseline." -Level Success
}

Save-ToolkitJson -Path $reportPath -Data $report
Write-ToolkitStatus "Baseline report saved to $reportPath" -Level Success

if ($missingRequired.Count -gt 0) {
    exit 2
}
