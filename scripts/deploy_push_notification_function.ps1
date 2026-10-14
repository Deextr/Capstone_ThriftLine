# Deploy send-push-notification Edge Function (run after Firebase service account is ready).
# Prerequisites: supabase CLI logged in (`supabase login`)
#
# Then set secrets in Dashboard → Edge Functions → send-push-notification:
#   FCM_SERVICE_ACCOUNT_JSON = minified Firebase service account JSON
#   PUSH_DISPATCH_SECRET     = optional; match Vault secret push_dispatch_secret

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Deploying send-push-notification..."
supabase functions deploy send-push-notification --project-ref zakorrcmmswwzfihmcji

Write-Host ""
Write-Host "Next: Supabase Dashboard → Edge Functions → send-push-notification → Secrets"
Write-Host "  FCM_SERVICE_ACCOUNT_JSON"
Write-Host "  PUSH_DISPATCH_SECRET (optional)"
Write-Host ""
Write-Host "Enable pg_net in Database → Extensions if not already enabled."
