[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskId,

    [Parameter(Mandatory)]
    [string]$RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "HireToolkit.Common.psm1") -Force -DisableNameChecking

function ConvertTo-CommandLine {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    return ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '"', '\"') + '"'
            }
            else {
                $_
            }
        }) -join " "
}

function Save-RunStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Status
    )

    $Status["UpdatedAt"] = (Get-Date).ToString("s")
    Save-ToolkitJson -Path $Path -Data $Status
}

$toolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$tasksConfigPath = Join-Path $toolkitRoot "config\dashboard-tasks.json"
$tasksConfig = Read-ToolkitJson -Path $tasksConfigPath
$task = @($tasksConfig.tasks | Where-Object { $_.id -eq $TaskId }) | Select-Object -First 1

if (-not $task) {
    throw "Unknown dashboard task: $TaskId"
}

$runRoot = Ensure-ToolkitDirectory -Path (Join-Path $toolkitRoot "reports\dashboard-runs\$RunId")
$statusPath = Join-Path $runRoot "status.json"
$powerShellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($powerShellCommand) {
    $powerShellExe = $powerShellCommand.Source
}
else {
    $powerShellExe = Join-Path $PSHOME "powershell.exe"
}

$steps = @($task.steps | ForEach-Object {
        [ordered]@{
            Name      = $_.name
            Script    = $_.script
            State     = "pending"
            ExitCode  = $null
            StartedAt = $null
            FinishedAt = $null
            LogPath   = $null
            ErrorPath = $null
        }
    })

$status = @{
    RunId               = $RunId
    TaskId              = $TaskId
    Name                = $task.name
    Description         = $task.description
    State               = "running"
    Percent             = 0
    StartedAt           = (Get-Date).ToString("s")
    UpdatedAt           = (Get-Date).ToString("s")
    FinishedAt          = $null
    Help                = $task.help
    RecommendedNextTask = $task.recommendedNextTask
    Steps               = $steps
}

Save-RunStatus -Path $statusPath -Status $status

for ($index = 0; $index -lt $steps.Count; $index++) {
    $step = $steps[$index]
    $scriptPath = Join-Path $PSScriptRoot $step["Script"]
    $step["State"] = "running"
    $step["StartedAt"] = (Get-Date).ToString("s")
    $step["LogPath"] = Join-Path $runRoot ("{0}-{1}.stdout.log" -f ($index + 1), ($step["Name"] -replace "[^A-Za-z0-9]+", "-"))
    $step["ErrorPath"] = Join-Path $runRoot ("{0}-{1}.stderr.log" -f ($index + 1), ($step["Name"] -replace "[^A-Za-z0-9]+", "-"))
    $status["Percent"] = [int](($index / $steps.Count) * 100)
    Save-RunStatus -Path $statusPath -Status $status

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $step["State"] = "error"
        $step["ExitCode"] = 9009
        $step["FinishedAt"] = (Get-Date).ToString("s")
        "Script not found: $scriptPath" | Set-Content -LiteralPath $step["ErrorPath"] -Encoding UTF8
        $status["State"] = "failed"
        $status["Percent"] = [int](($index / $steps.Count) * 100)
        $status["FinishedAt"] = (Get-Date).ToString("s")
        Save-RunStatus -Path $statusPath -Status $status
        exit 1
    }

    $arguments = ConvertTo-CommandLine -Arguments @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $scriptPath
    )

    $process = Start-Process `
        -FilePath $powerShellExe `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $step["LogPath"] `
        -RedirectStandardError $step["ErrorPath"]

    $step["ExitCode"] = $process.ExitCode
    $step["FinishedAt"] = (Get-Date).ToString("s")

    if ($process.ExitCode -eq 0) {
        $step["State"] = "success"
        $status["Percent"] = [int]((($index + 1) / $steps.Count) * 100)
        Save-RunStatus -Path $statusPath -Status $status
        continue
    }

    $step["State"] = "error"
    $status["State"] = "failed"
    $status["Percent"] = [int]((($index + 1) / $steps.Count) * 100)
    $status["FinishedAt"] = (Get-Date).ToString("s")
    Save-RunStatus -Path $statusPath -Status $status
    exit $process.ExitCode
}

$status["State"] = "success"
$status["Percent"] = 100
$status["FinishedAt"] = (Get-Date).ToString("s")
Save-RunStatus -Path $statusPath -Status $status
