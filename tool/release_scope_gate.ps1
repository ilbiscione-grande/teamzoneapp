param(
  [string]$OldProjectPath = 'C:\Dev\TeamZone'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Scope {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { $failures.Add($Message) }
}

$oldStatus = & git -C $OldProjectPath status --porcelain
Assert-Scope ($LASTEXITCODE -eq 0) 'Old TeamZone project is not a readable Git worktree.'
Assert-Scope ([string]::IsNullOrWhiteSpace(($oldStatus -join "`n"))) 'Old TeamZone project has local changes.'

$android = Get-Content (Join-Path $repoRoot 'android/app/build.gradle.kts') -Raw
$ios = Get-Content (Join-Path $repoRoot 'ios/Runner.xcodeproj/project.pbxproj') -Raw
Assert-Scope ($android.Contains('namespace = "com.teamzone.teamzone"')) 'Android namespace changed.'
Assert-Scope ($android.Contains('applicationId = "com.teamzone.teamzone"')) 'Android applicationId changed.'
Assert-Scope ($ios.Contains('PRODUCT_BUNDLE_IDENTIFIER = com.teamzone.teamzone;')) 'iOS bundle identifier changed.'

$environments = Get-Content (Join-Path $repoRoot 'ops/environments.json') -Raw | ConvertFrom-Json
$production = $environments.environments.production
Assert-Scope ($production.status -eq 'not_provisioned') 'Production is marked provisioned.'
Assert-Scope ($null -eq $production.supabaseProjectRef) 'Production has a Supabase project reference.'
Assert-Scope ($null -eq $production.firebaseProject) 'Production has a Firebase project reference.'

foreach ($forbiddenDirectory in @('webtools', 'workspaces')) {
  Assert-Scope (-not (Test-Path (Join-Path $repoRoot $forbiddenDirectory))) "Forbidden directory exists: $forbiddenDirectory"
}

$cardsPath = Join-Path $repoRoot 'docs/implementation/core_app_delivery_cards.md'
$cards = Get-Content $cardsPath
$evidenceNames = Get-ChildItem (Join-Path $repoRoot 'docs/evidence') -File |
  ForEach-Object { $_.BaseName.ToLowerInvariant() }
for ($index = 0; $index -lt $cards.Count; $index++) {
  if ($cards[$index] -notmatch '^### ([A-Z]+-[0-9]+) ') { continue }
  $cardId = $Matches[1]
  $statusLine = $cards[($index + 1)..([Math]::Min($index + 5, $cards.Count - 1))] |
    Where-Object { $_ -match '^\*\*Status:\*\* `\[([^]]+)\]`' } | Select-Object -First 1
  if ($null -eq $statusLine -or $statusLine -notmatch '`\[([^]]+)\]`') { continue }
  if ($Matches[1] -eq ' ') { continue }
  $prefix = $cardId.ToLowerInvariant().Replace('-', '')
  Assert-Scope (($evidenceNames | Where-Object { $_ -like "$prefix*" }).Count -gt 0) "Implemented card lacks evidence: $cardId"
}

$forbiddenCommands = @(
  'supabase db push',
  'supabase functions deploy',
  'firebase deploy',
  'flutterfire configure'
)
$releaseScripts = Get-ChildItem (Join-Path $repoRoot 'tool') -File |
  Where-Object { $_.Name -ne 'release_scope_gate.ps1' } | ForEach-Object {
  Get-Content $_.FullName -Raw
}
foreach ($command in $forbiddenCommands) {
  Assert-Scope (-not (($releaseScripts -join "`n").ToLowerInvariant().Contains($command))) "Release tool contains mutation command: $command"
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  exit 1
}
Write-Output 'REL03_SCOPE_GATE_OK'
