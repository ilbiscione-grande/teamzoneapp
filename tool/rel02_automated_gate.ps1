param(
  [string]$FlutterSdkPath = 'C:\Dev\FlutterSDK'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dartExecutable = Join-Path $FlutterSdkPath 'bin\cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = Join-Path $FlutterSdkPath 'bin\cache\flutter_tools.snapshot'

if (-not (Test-Path -LiteralPath $dartExecutable)) {
  throw "Dart executable not found: $dartExecutable"
}
if (-not (Test-Path -LiteralPath $flutterSnapshot)) {
  throw "Flutter tools snapshot not found: $flutterSnapshot"
}

$tests = @(
  'test/rel02_automated_release_matrix_test.dart',
  'test/rel02_verification_matrix_contract_test.dart',
  'test/fnd01_fnd03_verification_test.dart',
  'test/fnd02_async_data_controller_test.dart',
  'test/auth02_session_context_test.dart',
  'test/fnd05_accessibility_localization_test.dart',
  'test/ac02_responsive_entry_test.dart'
)

Push-Location $repoRoot
try {
  & $dartExecutable $flutterSnapshot --suppress-analytics test @tests
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

Write-Host 'REL02_AUTOMATED_GATE_OK'
