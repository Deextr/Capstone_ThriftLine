# Writes web/admin_config.json from .env for admin Flutter Web (local + deploy).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path '.env')) {
  throw 'Missing .env in project root. Copy .env.example and fill in values.'
}

$allowedKeys = @(
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'GOOGLE_WEB_CLIENT_ID',
  'TURNSTILE_SITE_KEY',
  'TURNSTILE_BASE_URL'
)

$config = [ordered]@{}
foreach ($line in Get-Content '.env') {
  $trimmed = $line.Trim()
  if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
  $eq = $trimmed.IndexOf('=')
  if ($eq -lt 1) { continue }
  $key = $trimmed.Substring(0, $eq).Trim()
  if ($allowedKeys -notcontains $key) { continue }
  $value = $trimmed.Substring($eq + 1).Trim()
  $config[$key] = $value
}

foreach ($required in @('SUPABASE_URL', 'SUPABASE_ANON_KEY')) {
  if (-not $config.Contains($required) -or [string]::IsNullOrWhiteSpace($config[$required])) {
    throw ".env is missing required key: $required"
  }
}

$json = $config | ConvertTo-Json -Compress
$utf8 = [System.Text.UTF8Encoding]::new($false)
$webPath = Join-Path $root 'web\admin_config.json'
$assetDir = Join-Path $root 'assets\config'
if (-not (Test-Path $assetDir)) {
  New-Item -ItemType Directory -Path $assetDir | Out-Null
}
$assetPath = Join-Path $assetDir 'admin_config.json'
[System.IO.File]::WriteAllText($webPath, $json, $utf8)
[System.IO.File]::WriteAllText($assetPath, $json, $utf8)
Write-Host "Wrote $webPath"
Write-Host "Wrote $assetPath"
