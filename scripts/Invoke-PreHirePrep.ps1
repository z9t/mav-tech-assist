[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

function Set-DesktopWallpaper {
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    Add-Type @"
using System.Runtime.InteropServices;
public class WallpaperSetter {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(int action, int param, string vparam, int init);
}
"@

    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
    [void][WallpaperSetter]::SystemParametersInfo(20, 0, $ImagePath, 3)
}

function New-MavWallpaper {
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$LogoUri
    )

    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.Clear([System.Drawing.Color]::Black)

    $response = Invoke-WebRequest -Uri $LogoUri -UseBasicParsing
    $memoryStream = [System.IO.MemoryStream]::new($response.Content)
    $logo = [System.Drawing.Image]::FromStream($memoryStream)

    $maxWidth = [int]($screen.Width * 0.50)
    $maxHeight = [int]($screen.Height * 0.50)
    $scale = [math]::Min($maxWidth / $logo.Width, $maxHeight / $logo.Height)
    $targetWidth = [int]($logo.Width * $scale)
    $targetHeight = [int]($logo.Height * $scale)
    $x = [int](($screen.Width - $targetWidth) / 2)
    $y = [int](($screen.Height - $targetHeight) / 2)

    $graphics.DrawImage($logo, $x, $y, $targetWidth, $targetHeight)

    $parent = Split-Path -Parent $OutputPath
    Ensure-ToolkitDirectory -Path $parent | Out-Null
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Bmp)

    $logo.Dispose()
    $memoryStream.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$reportPath = New-ToolkitReportPath -Category "pre-hire-prep" -ToolkitRoot $toolkitRoot
$configPath = Join-Path $toolkitRoot "config\prep-settings.json"
$config = Read-ToolkitJson -Path $configPath
$timestamp = Get-ToolkitTimestamp

$oldRoot = Join-Path $env:USERPROFILE "Old\$timestamp"
if (-not $DryRun) {
    $oldRoot = Ensure-ToolkitDirectory -Path $oldRoot
}
$desktopPath = [Environment]::GetFolderPath("Desktop")
$downloadsPath = Join-Path $env:USERPROFILE "Downloads"
$desktopArchive = Join-Path $oldRoot "Desktop"
$downloadsArchive = Join-Path $oldRoot "Downloads"

Write-ToolkitStatus "Checking large files in Desktop and Downloads before cleanup..."
$largeFiles = @(Get-LargeFiles -Paths @($desktopPath, $downloadsPath) -MinimumBytes ([int64]$config.largeFileThresholdBytes) -Limit 20)

Write-ToolkitStatus "Tidying Desktop into $desktopArchive"
$desktopMoved = Move-LooseItemsToArchive -SourcePath $desktopPath -ArchivePath $desktopArchive -KeepNames @("desktop.ini", "Old") -KeepExtensions @(".lnk", ".url", ".ini") -WhatIfOnly:$DryRun

Write-ToolkitStatus "Tidying Downloads into $downloadsArchive"
$downloadsMoved = Move-LooseItemsToArchive -SourcePath $downloadsPath -ArchivePath $downloadsArchive -KeepNames @("desktop.ini", "Old") -WhatIfOnly:$DryRun

Write-ToolkitStatus "Checking disk space..."
$diskHealth = @(Get-DiskSpaceHealth -LowSpaceBytes ([int64]$config.lowSpaceBytes) -LowSpacePercent ([double]$config.lowSpacePercent))

Write-ToolkitStatus "Checking Microsoft 365 state..."
$m365State = Get-Microsoft365State

$wallpaperPath = Join-Path $env:PUBLIC "Pictures\MAV\mav-branding-wallpaper.bmp"
if ($DryRun) {
    Write-ToolkitStatus "Dry run: wallpaper will not be generated or set." -Level Warn
}
else {
    Write-ToolkitStatus "Building MAV wallpaper from live logo asset..."
    New-MavWallpaper -OutputPath $wallpaperPath -LogoUri $config.logoUri
    Set-DesktopWallpaper -ImagePath $wallpaperPath
    Write-ToolkitStatus "Wallpaper set to $wallpaperPath" -Level Success
}

$report = [ordered]@{
    Script               = "Invoke-PreHirePrep.ps1"
    RanAt                = (Get-Date).ToString("s")
    DryRun               = [bool]$DryRun
    OldRoot              = $oldRoot
    LargeFiles           = @($largeFiles | Select-Object FullName, Length, LastWriteTime)
    DesktopMoved         = @($desktopMoved)
    DownloadsMoved       = @($downloadsMoved)
    DiskHealth           = @($diskHealth)
    Microsoft365State    = $m365State
    WallpaperPath        = $wallpaperPath
    LogoUri              = $config.logoUri
}

if (@($diskHealth | Where-Object { $_.IsLowSpace }).Count -gt 0) {
    $lowDrives = @($diskHealth | Where-Object { $_.IsLowSpace } | ForEach-Object { $_.Drive })
    Write-ToolkitStatus "Low disk space detected on: $($lowDrives -join ', ')" -Level Warn
}
else {
    Write-ToolkitStatus "Disk space looks healthy." -Level Success
}

if ($largeFiles.Count -gt 0) {
    Write-ToolkitStatus "Large files were found before cleanup. Review the report if you want to check what was archived." -Level Warn
}
else {
    Write-ToolkitStatus "No large files were found in Desktop or Downloads." -Level Success
}

if ($m365State.IsLicensed) {
    Write-ToolkitStatus "Microsoft 365 appears licensed for the next hire." -Level Success
}
else {
    Write-ToolkitStatus "Microsoft 365 could not be confirmed. Open Word or PowerPoint and check File > Account." -Level Warn
}

Save-ToolkitJson -Path $reportPath -Data $report
Write-ToolkitStatus "Pre-hire prep report saved to $reportPath" -Level Success

if ((-not $DryRun) -and (((@($diskHealth | Where-Object { $_.IsLowSpace }).Count -gt 0) -or (-not $m365State.IsLicensed)))) {
    exit 2
}
