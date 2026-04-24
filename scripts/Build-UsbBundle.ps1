[CmdletBinding()]
param(
    [string]$Root = "",

    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $Root "MAV-Tech-Assist-USB.zip"
}

$itemsToCopy = @(
    "launchers",
    "scripts",
    "config",
    "docs",
    "tools",
    "web"
)

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mav-toolkit-usb-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $stagingRoot -Force

try {
    foreach ($item in $itemsToCopy) {
        $sourcePath = Join-Path $Root $item
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Missing bundle item: $item"
        }

        $destinationPath = Join-Path $stagingRoot $item
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
    }

    $bundleZipInWeb = Join-Path $stagingRoot "web\MAV-Tech-Assist-USB.zip"
    if (Test-Path -LiteralPath $bundleZipInWeb) {
        Remove-Item -LiteralPath $bundleZipInWeb -Force
    }

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    $archiveSource = Join-Path $stagingRoot "*"
    Compress-Archive -Path $archiveSource -DestinationPath $OutputPath -CompressionLevel Optimal -Force
    Write-Host "Built USB bundle: $OutputPath" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
