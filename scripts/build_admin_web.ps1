# Builds ThriftLine admin Flutter Web for Cloudflare Pages (Direct Upload).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& (Join-Path $PSScriptRoot 'sync_admin_web_config.ps1')

flutter pub get
# Use Google CDN for CanvasKit. Local .wasm often fails to upload / is cached
# as HTML on Cloudflare Pages, which leaves a blank white screen.
flutter build web -t lib/main_admin.dart --release --base-href / --no-wasm-dry-run --pwa-strategy=none --web-resources-cdn
if ($LASTEXITCODE -ne 0) {
  throw 'flutter build web failed.'
}
Remove-Item -Force '.\build\web\404.html' -ErrorAction SilentlyContinue

$bootstrap = Join-Path $root 'build\web\flutter_bootstrap.js'
if (Test-Path $bootstrap) {
  $text = [System.IO.File]::ReadAllText($bootstrap)
  $text = $text.Replace('"useLocalCanvasKit":true', '"useLocalCanvasKit":false')
  if ($text -notmatch '"useLocalCanvasKit"') {
    $text = $text.Replace(
      '"mainJsPath":"main.dart.js"}]',
      '"mainJsPath":"main.dart.js"}],"useLocalCanvasKit":false'
    )
  }
  [System.IO.File]::WriteAllText($bootstrap, $text)
}

$sourceConfig = Join-Path $root 'web\admin_config.json'
$configOut = Join-Path $root 'build\web\admin_config.json'
if (-not (Test-Path $sourceConfig)) {
  throw "Missing $sourceConfig after sync."
}
Copy-Item $sourceConfig $configOut -Force

$assetConfig = Join-Path $root 'build\web\assets\assets\config\admin_config.json'
if (-not (Test-Path $assetConfig)) {
  throw "Build output missing bundled $assetConfig"
}

$zipPath = Join-Path $root 'build\thriftline-admin-deploy.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  (Join-Path $root 'build\web'),
  $zipPath,
  [System.IO.Compression.CompressionLevel]::Fastest,
  $false
)

$bootstrapText = [System.IO.File]::ReadAllText($bootstrap)
if ($bootstrapText -match '"useLocalCanvasKit":true') {
  throw 'flutter_bootstrap.js still wants local CanvasKit.'
}

Write-Host ''
Write-Host 'Deploy this ZIP to Cloudflare Pages Production:' -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host ''
Write-Host 'Then open an Incognito window:' -ForegroundColor Cyan
Write-Host '  https://thriftline-admin.pages.dev/admin/login'
