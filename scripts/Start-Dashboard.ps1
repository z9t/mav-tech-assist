[CmdletBinding()]
param(
    [int]$Port = 8787,

    [switch]$NoBrowser,

    [string]$Page = ""
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

function New-RunId {
    return "{0}-{1}" -f (Get-ToolkitTimestamp), ([guid]::NewGuid().ToString("N").Substring(0, 8))
}

function ConvertTo-UrlDecodedString {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return [System.Uri]::UnescapeDataString(($Value -replace "\+", " "))
}

function ConvertFrom-QueryString {
    param(
        [string]$Query
    )

    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Query)) {
        return $result
    }

    foreach ($pair in $Query.TrimStart("?").Split("&")) {
        if ([string]::IsNullOrWhiteSpace($pair)) {
            continue
        }

        $parts = $pair.Split("=", 2)
        $key = ConvertTo-UrlDecodedString -Value $parts[0]
        $value = if ($parts.Count -gt 1) { ConvertTo-UrlDecodedString -Value $parts[1] } else { "" }
        $result[$key] = $value
    }

    return $result
}

function Send-HttpResponse {
    param(
        [Parameter(Mandatory)]
        [System.Net.Sockets.NetworkStream]$Stream,

        [int]$StatusCode = 200,

        [string]$StatusText = "OK",

        [string]$ContentType = "application/json; charset=utf-8",

        [string]$Body = ""
    )

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $header = "HTTP/1.1 $StatusCode $StatusText`r`n" +
        "Content-Type: $ContentType`r`n" +
        "Content-Length: $($bodyBytes.Length)`r`n" +
        "Cache-Control: no-store`r`n" +
        "Connection: close`r`n" +
        "Access-Control-Allow-Methods: GET,POST,OPTIONS`r`n" +
        "Access-Control-Allow-Headers: Content-Type`r`n" +
        "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
}

function Read-RequestBody {
    param(
        [Parameter(Mandatory)]
        [System.IO.StreamReader]$Reader,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $lengthHeader = $Headers["content-length"]
    if ([string]::IsNullOrWhiteSpace($lengthHeader)) {
        return ""
    }

    $length = 0
    if (-not [int]::TryParse($lengthHeader, [ref]$length) -or $length -le 0) {
        return ""
    }

    $buffer = New-Object char[] $length
    $offset = 0
    while ($offset -lt $length) {
        $read = $Reader.ReadBlock($buffer, $offset, $length - $offset)
        if ($read -le 0) {
            break
        }

        $offset += $read
    }

    if ($offset -le 0) {
        return ""
    }

    return -join $buffer[0..($offset - 1)]
}

function Get-PostedPayload {
    param(
        [string]$Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return [pscustomobject]@{}
    }

    $form = ConvertFrom-QueryString -Query $Body
    $payloadText = $form["payload"]
    if ([string]::IsNullOrWhiteSpace($payloadText)) {
        return [pscustomobject]@{}
    }

    try {
        return $payloadText | ConvertFrom-Json
    }
    catch {
        throw "Invalid request payload."
    }
}

function Get-PayloadValue {
    param(
        $Payload,

        [Parameter(Mandatory)]
        [string]$Name,

        $Default = $null
    )

    if ($null -eq $Payload) {
        return $Default
    }

    $property = $Payload.PSObject.Properties[$Name]
    if (-not $property) {
        return $Default
    }

    return $property.Value
}

function Get-PayloadSwitch {
    param(
        $Payload,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return [bool](Get-PayloadValue -Payload $Payload -Name $Name -Default $false)
}

function Get-DashboardHtml {
    $html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MAV Tech Assist</title>
  <style>
    :root {
      --bg: #090909;
      --panel: #161616;
      --panel-2: #202020;
      --text: #f7f1df;
      --muted: #b8b09c;
      --brand: #ffd84d;
      --ok: #3fd079;
      --bad: #ff5c5c;
      --warn: #ffbd4a;
      --line: #34312a;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 12% 8%, rgba(255, 216, 77, 0.20), transparent 28rem),
        radial-gradient(circle at 86% 18%, rgba(63, 208, 121, 0.12), transparent 24rem),
        linear-gradient(135deg, #030303, var(--bg) 55%, #151208);
      color: var(--text);
      font-family: Aptos, Segoe UI, Tahoma, sans-serif;
    }

    main {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 32px 0 48px;
    }

    header {
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 24px;
      margin-bottom: 26px;
    }

    h1 {
      margin: 0;
      font-size: clamp(34px, 5vw, 72px);
      letter-spacing: -0.06em;
      line-height: 0.92;
    }

    .tagline {
      margin: 12px 0 0;
      max-width: 720px;
      color: var(--muted);
      font-size: 17px;
    }

    .pill {
      border: 1px solid rgba(255, 216, 77, 0.4);
      border-radius: 999px;
      color: var(--brand);
      padding: 10px 14px;
      white-space: nowrap;
      background: rgba(255, 216, 77, 0.08);
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 14px;
    }

    .card, .status {
      border: 1px solid var(--line);
      background: linear-gradient(180deg, rgba(255,255,255,0.045), rgba(255,255,255,0.015)), var(--panel);
      border-radius: 22px;
      box-shadow: 0 18px 60px rgba(0,0,0,0.28);
    }

    .card {
      padding: 18px;
      min-height: 210px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }

    .card h2 {
      margin: 0 0 8px;
      font-size: 21px;
      letter-spacing: -0.02em;
    }

    .card p {
      margin: 0 0 18px;
      color: var(--muted);
      line-height: 1.45;
    }

    button {
      border: 0;
      border-radius: 14px;
      padding: 12px 14px;
      color: #151100;
      background: var(--brand);
      font-weight: 800;
      cursor: pointer;
      transition: transform 140ms ease, filter 140ms ease;
    }

    button:hover { transform: translateY(-1px); filter: brightness(1.06); }
    button:disabled { opacity: 0.55; cursor: not-allowed; transform: none; }

    .status {
      margin-top: 18px;
      padding: 20px;
    }

    .status-top {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 14px;
    }

    .status h2 {
      margin: 0;
      font-size: 24px;
    }

    .state {
      border-radius: 999px;
      padding: 8px 12px;
      color: var(--muted);
      background: var(--panel-2);
      border: 1px solid var(--line);
    }

    .state.success { color: var(--ok); border-color: rgba(63, 208, 121, 0.45); }
    .state.failed { color: var(--bad); border-color: rgba(255, 92, 92, 0.45); }
    .state.running { color: var(--brand); border-color: rgba(255, 216, 77, 0.45); }

    .progress {
      height: 15px;
      border-radius: 999px;
      overflow: hidden;
      background: #0c0c0c;
      border: 1px solid var(--line);
    }

    .bar {
      width: 0%;
      height: 100%;
      background: linear-gradient(90deg, var(--brand), var(--ok));
      transition: width 260ms ease;
    }

    .steps {
      display: grid;
      gap: 10px;
      margin-top: 16px;
    }

    .step {
      display: grid;
      grid-template-columns: 34px 1fr auto;
      align-items: center;
      gap: 12px;
      padding: 12px;
      border-radius: 15px;
      background: rgba(255,255,255,0.035);
      border: 1px solid rgba(255,255,255,0.06);
    }

    .icon {
      display: grid;
      place-items: center;
      width: 30px;
      height: 30px;
      border-radius: 999px;
      background: var(--panel-2);
      color: var(--muted);
      font-weight: 900;
    }

    .step.success .icon { background: rgba(63, 208, 121, 0.16); color: var(--ok); }
    .step.error .icon { background: rgba(255, 92, 92, 0.16); color: var(--bad); }
    .step.running .icon { background: rgba(255, 216, 77, 0.16); color: var(--brand); }

    .small {
      color: var(--muted);
      font-size: 13px;
    }

    .help {
      display: none;
      margin-top: 16px;
      padding: 15px;
      border-radius: 16px;
      border: 1px solid rgba(255, 92, 92, 0.36);
      background: rgba(255, 92, 92, 0.08);
      color: #ffd8d8;
      line-height: 1.45;
    }

    .help.show { display: block; }

    .logs {
      margin-top: 12px;
      color: var(--muted);
      font-size: 13px;
    }

    @media (max-width: 720px) {
      header { display: block; }
      .pill { display: inline-block; margin-top: 18px; }
      .status-top { display: block; }
      .state { display: inline-block; margin-top: 10px; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>MAV Tech Assist</h1>
        <p class="tagline">Run clean handover checks from the USB. Green continues automatically. Red stops and shows the next useful action.</p>
      </div>
      <div class="pill">Local only: 127.0.0.1</div>
    </header>

    <section class="grid" id="taskGrid"></section>

    <section class="status" id="statusPanel" hidden>
      <div class="status-top">
        <h2 id="runTitle">Ready</h2>
        <span class="state" id="runState">waiting</span>
      </div>
      <div class="progress"><div class="bar" id="progressBar"></div></div>
      <div class="steps" id="steps"></div>
      <div class="help" id="helpBox"></div>
      <div class="logs" id="logHint"></div>
    </section>
  </main>

  <script>
    const dashboardToken = '__DASHBOARD_TOKEN__';
    let tasks = [];
    let pollTimer = null;
    let running = false;

    const grid = document.getElementById('taskGrid');
    const panel = document.getElementById('statusPanel');
    const runTitle = document.getElementById('runTitle');
    const runState = document.getElementById('runState');
    const progressBar = document.getElementById('progressBar');
    const stepsEl = document.getElementById('steps');
    const helpBox = document.getElementById('helpBox');
    const logHint = document.getElementById('logHint');

    function iconFor(state) {
      if (state === 'success') return '\u2713';
      if (state === 'error') return '!';
      if (state === 'running') return '...';
      return '-';
    }

    function renderTasks() {
      grid.innerHTML = '';
      for (const task of tasks) {
        const card = document.createElement('article');
        card.className = 'card';
        card.innerHTML = `
          <div>
            <h2>${task.name}</h2>
            <p>${task.description}</p>
          </div>
          <button data-task="${task.id}">Run</button>
        `;
        grid.appendChild(card);
      }
      grid.addEventListener('click', event => {
        const button = event.target.closest('button[data-task]');
        if (!button || running) return;
        runTask(button.dataset.task);
      });
    }

    function setButtonsDisabled(disabled) {
      document.querySelectorAll('button[data-task]').forEach(button => {
        button.disabled = disabled;
      });
    }

    async function runTask(taskId) {
      running = true;
      setButtonsDisabled(true);
      panel.hidden = false;
      helpBox.className = 'help';
      helpBox.textContent = '';
      logHint.textContent = '';

      const response = await fetch(`/api/run?task=${encodeURIComponent(taskId)}&token=${encodeURIComponent(dashboardToken)}`, { method: 'POST' });
      const data = await response.json();
      if (!response.ok) {
        running = false;
        setButtonsDisabled(false);
        showError(data.error || 'Could not start task.');
        return;
      }

      pollStatus(data.runId);
    }

    async function pollStatus(runId) {
      if (pollTimer) clearTimeout(pollTimer);
      const response = await fetch(`/api/status?runId=${encodeURIComponent(runId)}`);
      const status = await response.json();
      renderStatus(status);
      const state = status.state || status.State;

      if (state === 'running' || state === 'queued') {
        pollTimer = setTimeout(() => pollStatus(runId), 1000);
        return;
      }

      running = false;
      setButtonsDisabled(false);
    }

    function renderStatus(status) {
      const state = status.state || status.State || 'running';
      const percent = status.percent ?? status.Percent ?? 0;
      const steps = status.steps || status.Steps || [];
      const name = status.name || status.Name || 'Running task';
      const help = status.help || status.Help || 'Check the failed step and report.';
      const recommendedNextTask = status.recommendedNextTask || status.RecommendedNextTask;
      const runId = status.runId || status.RunId;

      runTitle.textContent = name;
      runState.textContent = state;
      runState.className = `state ${state}`;
      progressBar.style.width = `${percent}%`;
      stepsEl.innerHTML = '';

      for (const step of steps) {
        const stepState = step.state || step.State || 'pending';
        const stepName = step.name || step.Name || 'Step';
        const stepScript = step.script || step.Script || '';
        const exitCode = step.exitCode ?? step.ExitCode;
        const row = document.createElement('div');
        row.className = `step ${stepState}`;
        row.innerHTML = `
          <span class="icon">${iconFor(stepState)}</span>
          <div>
            <strong>${stepName}</strong>
            <div class="small">${stepScript}</div>
          </div>
          <span class="small">${exitCode === null || exitCode === undefined ? '' : 'exit ' + exitCode}</span>
        `;
        stepsEl.appendChild(row);
      }

      if (state === 'failed') {
        helpBox.className = 'help show';
        helpBox.innerHTML = `${help}`;
        if (recommendedNextTask) {
          const next = tasks.find(task => task.id === recommendedNextTask);
          if (next) {
            const button = document.createElement('button');
            button.textContent = `Run ${next.name}`;
            button.style.marginTop = '12px';
            button.onclick = () => runTask(next.id);
            helpBox.appendChild(document.createElement('br'));
            helpBox.appendChild(button);
          }
        }
      } else if (state === 'success') {
        helpBox.className = 'help';
        helpBox.textContent = '';
      }

      if (runId) {
        logHint.textContent = `Run ID: ${runId}. Detailed logs are in reports\\dashboard-runs\\${runId}.`;
      }
    }

    function showError(message) {
      panel.hidden = false;
      runTitle.textContent = 'Could not start';
      runState.textContent = 'failed';
      runState.className = 'state failed';
      progressBar.style.width = '0%';
      stepsEl.innerHTML = '';
      helpBox.className = 'help show';
      helpBox.textContent = message;
    }

    async function init() {
      const response = await fetch('/api/tasks');
      const data = await response.json();
      tasks = data.tasks || [];
      renderTasks();
    }

    init().catch(error => showError(error.message));
  </script>
</body>
</html>
'@

    return $html.Replace("__DASHBOARD_TOKEN__", $script:DashboardToken)
}

function Get-PowerShellExe {
    $command = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return Join-Path $PSHOME "powershell.exe"
}

function Get-StaticContentType {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".htm" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".md" { return "text/plain; charset=utf-8" }
        ".txt" { return "text/plain; charset=utf-8" }
        ".svg" { return "image/svg+xml" }
        default { return "text/plain; charset=utf-8" }
    }
}

function Get-StaticFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$RequestPath
    )

    $decoded = ConvertTo-UrlDecodedString -Value $RequestPath
    if ($decoded -eq "/") {
        $decoded = "/index.html"
    }

    $relative = $decoded.TrimStart("/")
    $parts = $relative.Split("/", 2)

    if ($parts[0] -eq "docs") {
        $root = Join-Path $script:ToolkitRoot "docs"
        $relativePath = if ($parts.Count -gt 1) { $parts[1] } else { "README.md" }
    }
    else {
        $root = Join-Path $script:ToolkitRoot "web"
        $relativePath = $relative
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
    $rootFull = [System.IO.Path]::GetFullPath($root)

    if (-not $candidate.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        return $null
    }

    return $candidate
}

function Get-StaticFileBody {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $body = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($extension -eq ".html" -or $extension -eq ".htm") {
        $helperScript = "<script>window.MAV_LOCAL_HELPER={baseUrl:window.location.origin,token:'$script:DashboardToken'};</script>"
        $body = $body -replace "<head>", "<head>`n  $helperScript"
    }

    return $body
}

function Invoke-NetworkHelperScript {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Discover", "Probe", "Setup")]
        [string]$Mode,

        $Payload
    )

    $scriptPath = Join-Path $PSScriptRoot "Invoke-NetworkHelper.ps1"
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Network helper script is missing."
    }

    $arguments = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $scriptPath,
        "-Mode",
        $Mode
    )

    $tempInputPath = $null
    try {
        switch ($Mode) {
            "Discover" {
                $cidr = [string](Get-PayloadValue -Payload $Payload -Name "cidr" -Default "")
                if (-not [string]::IsNullOrWhiteSpace($cidr)) {
                    $arguments += @("-Cidr", $cidr)
                }
            }
            "Probe" {
                $tempInputPath = Join-Path $env:TEMP ("mav-network-helper-input-{0}.json" -f (New-RunId))
                Save-ToolkitJson -Path $tempInputPath -Data $Payload
                $arguments += @("-InputPath", $tempInputPath)
            }
            "Setup" {
                if (Get-PayloadSwitch -Payload $Payload -Name "enableSshServer") {
                    $arguments += "-EnableSshServer"
                }
                if (Get-PayloadSwitch -Payload $Payload -Name "enableFileSharing") {
                    $arguments += "-EnableFileSharing"
                }
                if (Get-PayloadSwitch -Payload $Payload -Name "enableNetworkDiscovery") {
                    $arguments += "-EnableNetworkDiscovery"
                }
                if (Get-PayloadSwitch -Payload $Payload -Name "preferPrivateNetworkProfile") {
                    $arguments += "-PreferPrivateNetworkProfile"
                }
                if (Get-PayloadSwitch -Payload $Payload -Name "dryRun") {
                    $arguments += "-DryRun"
                }
            }
        }

        $raw = & (Get-PowerShellExe) @arguments 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Network helper script failed: $raw"
        }

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{}
        }

        try {
            return $raw | ConvertFrom-Json
        }
        catch {
            throw "Network helper script returned invalid JSON."
        }
    }
    finally {
        if ($tempInputPath) {
            Remove-Item -LiteralPath $tempInputPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-DashboardTask {
    param(
        [Parameter(Mandatory)]
        [string]$TaskId
    )

    $task = @($script:TasksConfig.tasks | Where-Object { $_.id -eq $TaskId }) | Select-Object -First 1
    if (-not $task) {
        throw "Unknown task: $TaskId"
    }

    $runId = New-RunId
    $workerPath = Join-Path $PSScriptRoot "Invoke-DashboardTask.ps1"
    $arguments = ConvertTo-CommandLine -Arguments @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $workerPath,
        "-TaskId",
        $TaskId,
        "-RunId",
        $runId
    )

    Start-Process -FilePath (Get-PowerShellExe) -ArgumentList $arguments -WindowStyle Hidden | Out-Null

    return [ordered]@{
        runId = $runId
        taskId = $TaskId
        state = "queued"
    }
}

function Get-RunStatus {
    param(
        [Parameter(Mandatory)]
        [string]$RunId
    )

    if ($RunId -notmatch '^[A-Za-z0-9-]+$') {
        throw "Invalid run ID."
    }

    $statusPath = Join-Path $script:ToolkitRoot "reports\dashboard-runs\$RunId\status.json"
    if (-not (Test-Path -LiteralPath $statusPath)) {
        return [ordered]@{
            runId = $RunId
            state = "queued"
            percent = 0
            steps = @()
        }
    }

    return Read-ToolkitJson -Path $statusPath
}

function Handle-Request {
    param(
        [Parameter(Mandatory)]
        [System.Net.Sockets.TcpClient]$Client
    )

    $stream = $Client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return
    }

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($line)) {
            break
        }

        $parts = $line.Split(":", 2)
        if ($parts.Count -eq 2) {
            $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
        }
    }

    $requestParts = $requestLine.Split(" ")
    $method = $requestParts[0].ToUpperInvariant()
    $target = $requestParts[1]
    $pathAndQuery = $target.Split("?", 2)
    $path = $pathAndQuery[0]
    $query = if ($pathAndQuery.Count -gt 1) { ConvertFrom-QueryString -Query $pathAndQuery[1] } else { @{} }
    $body = Read-RequestBody -Reader $reader -Headers $headers

    if ($method -eq "OPTIONS") {
        Send-HttpResponse -Stream $stream -Body ""
        return
    }

    try {
        switch ($path) {
            "/" {
                $filePath = Get-StaticFilePath -RequestPath $path
                $body = Get-StaticFileBody -FilePath $filePath
                Send-HttpResponse -Stream $stream -ContentType (Get-StaticContentType -Path $filePath) -Body $body
            }
            "/api/tasks" {
                $body = $script:TasksConfig | ConvertTo-Json -Depth 8
                Send-HttpResponse -Stream $stream -Body $body
            }
            "/api/run" {
                if ($method -ne "POST") {
                    Send-HttpResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -Body (@{ error = "Use POST." } | ConvertTo-Json)
                    return
                }

                if ($query["token"] -ne $script:DashboardToken) {
                    Send-HttpResponse -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body (@{ error = "Invalid dashboard token." } | ConvertTo-Json)
                    return
                }

                $taskId = $query["task"]
                $body = Start-DashboardTask -TaskId $taskId | ConvertTo-Json -Depth 8
                Send-HttpResponse -Stream $stream -Body $body
            }
            "/api/status" {
                $runId = $query["runId"]
                $body = Get-RunStatus -RunId $runId | ConvertTo-Json -Depth 10
                Send-HttpResponse -Stream $stream -Body $body
            }
            "/api/network-helper/discover" {
                if ($method -ne "POST") {
                    Send-HttpResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -Body (@{ error = "Use POST." } | ConvertTo-Json)
                    return
                }

                if ($query["token"] -ne $script:DashboardToken) {
                    Send-HttpResponse -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body (@{ error = "Invalid dashboard token." } | ConvertTo-Json)
                    return
                }

                $payload = Get-PostedPayload -Body $body
                $responseBody = Invoke-NetworkHelperScript -Mode "Discover" -Payload $payload | ConvertTo-Json -Depth 10
                Send-HttpResponse -Stream $stream -Body $responseBody
            }
            "/api/network-helper/probe" {
                if ($method -ne "POST") {
                    Send-HttpResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -Body (@{ error = "Use POST." } | ConvertTo-Json)
                    return
                }

                if ($query["token"] -ne $script:DashboardToken) {
                    Send-HttpResponse -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body (@{ error = "Invalid dashboard token." } | ConvertTo-Json)
                    return
                }

                $payload = Get-PostedPayload -Body $body
                $responseBody = Invoke-NetworkHelperScript -Mode "Probe" -Payload $payload | ConvertTo-Json -Depth 10
                Send-HttpResponse -Stream $stream -Body $responseBody
            }
            "/api/network-helper/setup" {
                if ($method -ne "POST") {
                    Send-HttpResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -Body (@{ error = "Use POST." } | ConvertTo-Json)
                    return
                }

                if ($query["token"] -ne $script:DashboardToken) {
                    Send-HttpResponse -Stream $stream -StatusCode 403 -StatusText "Forbidden" -Body (@{ error = "Invalid dashboard token." } | ConvertTo-Json)
                    return
                }

                $payload = Get-PostedPayload -Body $body
                $responseBody = Invoke-NetworkHelperScript -Mode "Setup" -Payload $payload | ConvertTo-Json -Depth 10
                Send-HttpResponse -Stream $stream -Body $responseBody
            }
            default {
                if ($path.StartsWith("/api/")) {
                    Send-HttpResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" -Body (@{ error = "Not found." } | ConvertTo-Json)
                    return
                }

                $filePath = Get-StaticFilePath -RequestPath $path
                if ($filePath) {
                    $body = Get-StaticFileBody -FilePath $filePath
                    Send-HttpResponse -Stream $stream -ContentType (Get-StaticContentType -Path $filePath) -Body $body
                    return
                }

                Send-HttpResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" -Body (@{ error = "Not found." } | ConvertTo-Json)
            }
        }
    }
    catch {
        $body = @{
            error = $_.Exception.Message
        } | ConvertTo-Json
        Send-HttpResponse -Stream $stream -StatusCode 500 -StatusText "Server Error" -Body $body
    }
}

$script:ToolkitRoot = Get-ToolkitRoot -ScriptRoot $PSScriptRoot
$tasksConfigPath = Join-Path $script:ToolkitRoot "config\dashboard-tasks.json"
$script:TasksConfig = Read-ToolkitJson -Path $tasksConfigPath
$script:DashboardToken = [guid]::NewGuid().ToString("N")

$listener = $null
$boundPort = $null
for ($candidate = $Port; $candidate -lt ($Port + 20); $candidate++) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $candidate)
        $listener.Start()
        $boundPort = $candidate
        break
    }
    catch {
        $listener = $null
    }
}

if (-not $listener) {
    throw "Could not start local dashboard on ports $Port-$($Port + 19)."
}

$url = "http://127.0.0.1:$boundPort/"
Write-ToolkitStatus "Dashboard running at $url"
Write-ToolkitStatus "Close this PowerShell window to stop the dashboard."
if (-not $NoBrowser) {
    $pageToOpen = $Page.TrimStart("/")
    $browserUrl = if ([string]::IsNullOrWhiteSpace($pageToOpen)) {
        $url
    }
    else {
        $url + $pageToOpen
    }
    Start-Process $browserUrl
}

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        Handle-Request -Client $client
    }
    finally {
        $client.Close()
    }
}
