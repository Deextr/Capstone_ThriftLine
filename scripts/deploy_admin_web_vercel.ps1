# Build admin Flutter Web and deploy to Vercel project thriftline-admin.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& (Join-Path $PSScriptRoot 'build_admin_web.ps1')

$webOut = Join-Path $root 'build\web'
Set-Location $webOut

Write-Host ''
Write-Host 'Deploying to Vercel production (thriftline-admin)...' -ForegroundColor Green
npx vercel --prod --yes
if ($LASTEXITCODE -ne 0) {
  throw 'vercel --prod failed.'
}

Write-Host ''
Write-Host 'Production URL:' -ForegroundColor Cyan
Write-Host '  https://thriftline-admin.vercel.app/admin/login'
