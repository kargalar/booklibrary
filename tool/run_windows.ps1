$projectRoot = Split-Path -Parent $PSScriptRoot
$definesFile = Join-Path $projectRoot '.dart_defines.local.json'

if (-not (Test-Path -LiteralPath $definesFile)) {
  throw "Eksik dosya: $definesFile"
}

Set-Location $projectRoot
flutter run -d windows --dart-define-from-file=$definesFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
