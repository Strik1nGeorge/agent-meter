param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskRust = @('rust\bin\agent-meter.exe', 'rust\target\release\agent-meter.exe') | ForEach-Object { Join-Path $taskRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$taskBackend = if ($env:AGENT_METER_BACKEND) { $env:AGENT_METER_BACKEND } else { 'auto' }
if ($taskBackend -eq 'auto') { $taskBackend = if ($taskRust) { 'rust' } else { 'node' } }
if ($taskBackend -eq 'rust') {
  if (-not $taskRust) { throw 'Build Rust with cargo build --release --manifest-path rust/Cargo.toml.' }
  $taskExecutable = $taskRust
  $taskArguments = @('serve')
} elseif ($taskBackend -eq 'node') {
  $taskNode = Get-Command node -ErrorAction SilentlyContinue
  $taskExecutable = if ($taskNode) { $taskNode.Source } else {
    Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
  }
  if (-not (Test-Path -LiteralPath $taskExecutable)) { throw 'Node.js 22 or newer is required.' }
  $taskArguments = @(('"' + (Join-Path $taskRoot 'server.mjs') + '"'))
} else { throw 'AGENT_METER_BACKEND must be auto, rust, or node.' }
$taskPort = if ($env:PORT) { $env:PORT } else { '4318' }
$taskUrl = "http://127.0.0.1:$taskPort"
function Test-TaskBackend($health) {
  return $health.ok -and (($health.backend -eq 'rust') -eq ($taskBackend -eq 'rust'))
}
$taskHealth = $null
try { $taskHealth = Invoke-RestMethod -Uri "$taskUrl/api/health" -TimeoutSec 2 } catch {}
$taskHealthy = Test-TaskBackend $taskHealth
if ($taskHealth.ok -and -not $taskHealthy) { throw "A different Agent Meter backend is using port $taskPort. Set PORT to run alongside it." }
if (-not $taskHealthy) {
  $taskData = Join-Path $taskRoot '.data'
  New-Item -ItemType Directory -Force -Path $taskData | Out-Null
  $taskProcess = Start-Process -FilePath $taskExecutable -ArgumentList $taskArguments -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskData 'server.log') -RedirectStandardError (Join-Path $taskData 'server-error.log')
  Set-Content -LiteralPath (Join-Path $taskData 'server.pid') -Value $taskProcess.Id
  for ($taskAttempt = 0; $taskAttempt -lt 30; $taskAttempt++) {
    Start-Sleep -Milliseconds 300
    try { $taskHealthy = Test-TaskBackend (Invoke-RestMethod -Uri "$taskUrl/api/health" -TimeoutSec 1); if ($taskHealthy) { break } } catch {}
  }
}
if ($taskHealthy) { if (-not $NoBrowser) { Start-Process $taskUrl }; Write-Host "Agent Meter ($taskBackend): $taskUrl" }
else { throw 'Startup failed. Check .data/server-error.log.' }
