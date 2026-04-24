Set-StrictMode -Version Latest

function Get-ToolkitRoot {
    param(
        [string]$ScriptRoot = $PSScriptRoot
    )

    return (Resolve-Path (Join-Path $ScriptRoot "..")).Path
}

function Get-ToolkitTimestamp {
    return (Get-Date).ToString("yyyyMMdd-HHmmss")
}

function Ensure-ToolkitDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

function Write-ToolkitStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Warn", "Error", "Success")]
        [string]$Level = "Info"
    )

    $prefix = "[MAV]"
    $color = switch ($Level) {
        "Warn" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
        default { "Cyan" }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Read-ToolkitJson {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Save-ToolkitJson {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Data
    )

    $parent = Split-Path -Parent $Path
    Ensure-ToolkitDirectory -Path $parent | Out-Null
    $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-ToolkitReportPath {
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [string]$ToolkitRoot = (Get-ToolkitRoot)
    )

    $reportRoot = Ensure-ToolkitDirectory -Path (Join-Path $ToolkitRoot "reports")
    $fileName = "{0}-{1}.json" -f $Category, (Get-ToolkitTimestamp)
    return Join-Path $reportRoot $fileName
}

function Find-Executable {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,

        [string[]]$AdditionalDirectories = @()
    )

    foreach ($directory in $AdditionalDirectories) {
        foreach ($name in $Names) {
            $candidate = Join-Path $directory $name
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path $candidate).Path
            }
        }
    }

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    return $null
}

function Stop-ToolkitProcesses {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            try {
                if ($process.MainWindowHandle -ne 0) {
                    $null = $process.CloseMainWindow()
                    Start-Sleep -Milliseconds 500
                }

                if (-not $process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                }
            }
            catch {
                Write-ToolkitStatus "Could not stop process '$name' cleanly: $($_.Exception.Message)" -Level Warn
            }
        }
    }
}

function Get-Microsoft365State {
    $officeRoots = @(
        "C:\Program Files\Microsoft Office\Office16",
        "C:\Program Files (x86)\Microsoft Office\Office16"
    )

    $state = [ordered]@{
        CheckedAt        = (Get-Date).ToString("s")
        Detected         = $false
        IsLicensed       = $false
        Method           = $null
        OfficePath       = $null
        Emails           = @()
        RegistryLicensed = $false
        LicenseFilesSeen = 0
        Notes            = @()
    }

    $emailSet = New-Object System.Collections.Generic.HashSet[string]

    $identityPath = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity\Identities"
    if (Test-Path -LiteralPath $identityPath) {
        foreach ($item in Get-ChildItem -LiteralPath $identityPath -ErrorAction SilentlyContinue) {
            try {
                $props = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction Stop
                foreach ($propertyName in @("EmailAddress", "UserName", "SignInName")) {
                    $value = $props.$propertyName
                    if ($value -and $value -match "@") {
                        $null = $emailSet.Add($value.Trim())
                    }
                }
            }
            catch {
            }
        }
    }

    $licensingPath = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Licensing\LicensingNext"
    if (Test-Path -LiteralPath $licensingPath) {
        try {
            $properties = Get-ItemProperty -LiteralPath $licensingPath -ErrorAction Stop
            foreach ($property in $properties.PSObject.Properties) {
                if ($property.Name -notlike "PS*") {
                    if ([int]$property.Value -eq 2) {
                        $state.RegistryLicensed = $true
                    }
                }
            }
        }
        catch {
            $state.Notes += "LicensingNext registry path exists but could not be parsed."
        }
    }

    $licenseFolder = Join-Path $env:LOCALAPPDATA "Microsoft\Office\Licenses"
    if (Test-Path -LiteralPath $licenseFolder) {
        $licenseFiles = Get-ChildItem -LiteralPath $licenseFolder -Recurse -File -ErrorAction SilentlyContinue
        $state.LicenseFilesSeen = @($licenseFiles).Count
    }

    foreach ($officeRoot in $officeRoots) {
        $diagPath = Join-Path $officeRoot "vnextdiag.ps1"
        if (-not (Test-Path -LiteralPath $diagPath)) {
            continue
        }

        $state.Detected = $true
        $state.OfficePath = $officeRoot

        try {
            $raw = & $diagPath -action list 2>&1 | Out-String
            $licenseStateMatches = [regex]::Matches(
                $raw,
                "(?im)^\s*(?:State of the license|License State|State)\s*:\s*(.+?)\s*$"
            )

            foreach ($match in [regex]::Matches(
                $raw,
                "(?im)^\s*(?:Email of the user that activated the product|Email)\s*:\s*(.+?)\s*$"
            )) {
                if ($match.Groups[1].Value -match "@") {
                    $null = $emailSet.Add($match.Groups[1].Value.Trim())
                }
            }

            $state.IsLicensed = @($licenseStateMatches | Where-Object {
                    $_.Groups[1].Value -match "Licensed"
                }).Count -gt 0
            $state.Method = "vnextdiag"
            break
        }
        catch {
            $state.Notes += "vnextdiag.ps1 was found but could not be run at $officeRoot."
        }
    }

    if (-not $state.Detected) {
        foreach ($officeRoot in $officeRoots) {
            if (Test-Path -LiteralPath $officeRoot) {
                $state.Detected = $true
                $state.OfficePath = $officeRoot
                break
            }
        }
    }

    if (-not $state.IsLicensed -and ($state.RegistryLicensed -or $state.LicenseFilesSeen -gt 0)) {
        $state.IsLicensed = $true
        if (-not $state.Method) {
            $state.Method = "registry+license-files"
        }
    }

    $state.Emails = @($emailSet | Sort-Object)
    return [pscustomobject]$state
}

function Move-LooseItemsToArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [string[]]$KeepNames = @(),

        [string[]]$KeepExtensions = @(),

        [switch]$WhatIfOnly
    )

    if (-not $WhatIfOnly) {
        Ensure-ToolkitDirectory -Path $ArchivePath | Out-Null
    }
    $keepNameSet = $KeepNames | ForEach-Object { $_.ToLowerInvariant() }
    $keepExtensionSet = $KeepExtensions | ForEach-Object { $_.ToLowerInvariant() }

    $moved = New-Object System.Collections.Generic.List[object]

    foreach ($item in Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue) {
        $nameLower = $item.Name.ToLowerInvariant()
        $extensionLower = $item.Extension.ToLowerInvariant()

        if ($keepNameSet -contains $nameLower) {
            continue
        }

        if (-not $item.PSIsContainer -and $keepExtensionSet -contains $extensionLower) {
            continue
        }

        $destination = Join-Path $ArchivePath $item.Name
        $suffix = 1
        while (Test-Path -LiteralPath $destination) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
            $extension = [System.IO.Path]::GetExtension($item.Name)
            $destination = Join-Path $ArchivePath ("{0}-{1}{2}" -f $baseName, $suffix, $extension)
            $suffix += 1
        }

        if (-not $WhatIfOnly) {
            Move-Item -LiteralPath $item.FullName -Destination $destination -Force
        }

        $moved.Add([pscustomobject]@{
                Name        = $item.Name
                Source      = $item.FullName
                Destination = $destination
                IsDirectory = $item.PSIsContainer
                Action      = if ($WhatIfOnly) { "WouldMove" } else { "Moved" }
            })
    }

    return $moved
}

function Get-LargeFiles {
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [long]$MinimumBytes = 1GB,

        [int]$Limit = 20
    )

    $results = foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge $MinimumBytes } |
            Select-Object FullName, Length, LastWriteTime
    }

    return $results | Sort-Object Length -Descending | Select-Object -First $Limit
}

function Get-DiskSpaceHealth {
    param(
        [long]$LowSpaceBytes = 20GB,
        [double]$LowSpacePercent = 15
    )

    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"
    $results = foreach ($drive in $drives) {
        $freePercent = if ($drive.Size -gt 0) {
            [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 2)
        }
        else {
            0
        }

        [pscustomobject]@{
            Drive        = $drive.DeviceID
            SizeBytes    = [int64]$drive.Size
            FreeBytes    = [int64]$drive.FreeSpace
            FreePercent  = $freePercent
            IsLowSpace   = ($drive.FreeSpace -lt $LowSpaceBytes) -or ($freePercent -lt $LowSpacePercent)
            VolumeName   = $drive.VolumeName
            FileSystem   = $drive.FileSystem
        }
    }

    return $results
}

function Get-InstalledApplications {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($path in $registryPaths) {
        foreach ($entry in Get-ItemProperty -Path $path -ErrorAction SilentlyContinue) {
            $displayNameProperty = $entry.PSObject.Properties["DisplayName"]
            if (-not $displayNameProperty) {
                continue
            }

            $displayName = [string]$displayNameProperty.Value
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }

            $displayVersionProperty = $entry.PSObject.Properties["DisplayVersion"]
            $publisherProperty = $entry.PSObject.Properties["Publisher"]
            $installDateProperty = $entry.PSObject.Properties["InstallDate"]
            $psPathProperty = $entry.PSObject.Properties["PSPath"]

            [pscustomobject]@{
                DisplayName    = $displayName.Trim()
                DisplayVersion = if ($displayVersionProperty) { [string]$displayVersionProperty.Value } else { $null }
                Publisher      = if ($publisherProperty) { [string]$publisherProperty.Value } else { $null }
                InstallDate    = if ($installDateProperty) { [string]$installDateProperty.Value } else { $null }
                PSPath         = if ($psPathProperty) { [string]$psPathProperty.Value } else { $null }
            }
        }
    }

    return $apps |
        Sort-Object DisplayName, DisplayVersion -Unique
}

function Test-StringMatchesPattern {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [string[]]$Patterns = @()
    )

    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        if ($Value -like "*$pattern*") {
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function *-Toolkit*, Read-ToolkitJson, Save-ToolkitJson, Find-Executable, Stop-ToolkitProcesses, Get-Microsoft365State, Move-LooseItemsToArchive, Get-LargeFiles, Get-DiskSpaceHealth, Get-InstalledApplications, Test-StringMatchesPattern
