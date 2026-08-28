param(
  [int]$StepTimeoutSeconds = 600,
  [string]$ReportPath = 'docs/evidence/local/rel01_quality_gate_latest.json',
  [string]$FlutterSdkPath = 'C:\Dev\FlutterSDK'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedReport = Join-Path $repoRoot $ReportPath
$reportDirectory = Split-Path -Parent $resolvedReport
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$logDirectory = Join-Path $reportDirectory 'rel01-logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$dartExecutable = Join-Path $FlutterSdkPath 'bin\cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = Join-Path $FlutterSdkPath 'bin\cache\flutter_tools.snapshot'
if (-not (Test-Path -LiteralPath $dartExecutable)) { throw "Dart executable not found: $dartExecutable" }
if (-not (Test-Path -LiteralPath $flutterSnapshot)) { throw "Flutter tools snapshot not found: $flutterSnapshot" }

function Invoke-GateStep {
  param(
    [string]$Name,
    [string]$Executable,
    [string[]]$Arguments,
    [string]$WorkingDirectory
  )

  $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
  $stdoutPath = Join-Path $logDirectory "$slug.stdout.log"
  $stderrPath = Join-Path $logDirectory "$slug.stderr.log"
  $startedAt = Get-Date
  $process = Start-Process -FilePath $Executable -ArgumentList $Arguments `
    -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  $completed = $process.WaitForExit($StepTimeoutSeconds * 1000)
  if (-not $completed) {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
      & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
    } else {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }
  $finishedAt = Get-Date
  $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
  $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
  $exitCode = if ($completed) { $process.ExitCode } else { $null }
  [pscustomobject]@{
    name = $Name
    command = "$Executable $($Arguments -join ' ')"
    status = if (-not $completed) { 'timeout' } elseif ($exitCode -eq 0) { 'passed' } else { 'failed' }
    exit_code = $exitCode
    process_id = $process.Id
    duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)
    stdout_log = $stdoutPath.Substring($repoRoot.Length + 1).Replace('\', '/')
    stderr_log = $stderrPath.Substring($repoRoot.Length + 1).Replace('\', '/')
    summary = (($stdout + "`n" + $stderr).Trim() -split "`r?`n" | Select-Object -Last 8) -join "`n"
  }
}

$steps = @(
  @{ Name = 'Dart format'; Executable = $dartExecutable; Arguments = @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test'); Directory = $repoRoot },
  @{ Name = 'Flutter analyze'; Executable = $dartExecutable; Arguments = @($flutterSnapshot, '--suppress-analytics', 'analyze'); Directory = $repoRoot },
  @{ Name = 'Flutter test'; Executable = $dartExecutable; Arguments = @($flutterSnapshot, '--suppress-analytics', 'test'); Directory = $repoRoot },
  @{ Name = 'Flutter web build'; Executable = $dartExecutable; Arguments = @($flutterSnapshot, '--suppress-analytics', 'build', 'web'); Directory = $repoRoot },
  @{ Name = 'Flutter debug APK'; Executable = $dartExecutable; Arguments = @($flutterSnapshot, '--suppress-analytics', 'build', 'apk', '--debug'); Directory = $repoRoot },
  @{ Name = 'Public site tests'; Executable = 'npm.cmd'; Arguments = @('test'); Directory = (Join-Path $repoRoot 'public-site') },
  @{ Name = 'Public site typecheck'; Executable = 'npm.cmd'; Arguments = @('run', 'lint'); Directory = (Join-Path $repoRoot 'public-site') },
  @{ Name = 'Public site build'; Executable = 'npm.cmd'; Arguments = @('run', 'build'); Directory = (Join-Path $repoRoot 'public-site') },
  @{ Name = 'Security contracts'; Executable = $dartExecutable; Arguments = @($flutterSnapshot, '--suppress-analytics', 'test', 'test/xqa_repository_contract_test.dart', 'test/xobs_xops_contract_test.dart', 'test/s01_contract_test.dart'); Directory = $repoRoot }
)

$results = foreach ($step in $steps) {
  Write-Host "REL-01: $($step.Name)"
  Invoke-GateStep -Name $step.Name -Executable $step.Executable `
    -Arguments $step.Arguments -WorkingDirectory $step.Directory
}

$passed = @($results | Where-Object status -eq 'passed').Count
$report = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  repository = $repoRoot
  status = if ($passed -eq $results.Count) { 'passed' } else { 'blocked' }
  passed = $passed
  total = $results.Count
  constraints = @(
    'No Supabase live mutation',
    'No production provisioning',
    'No webtools or workspaces'
  )
  results = $results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReport -Encoding utf8
Write-Host "REL-01 report: $resolvedReport"
if ($report.status -ne 'passed') { exit 1 }
