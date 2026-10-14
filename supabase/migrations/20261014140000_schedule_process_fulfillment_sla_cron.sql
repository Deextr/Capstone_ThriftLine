-- Invoke process-fulfillment-sla Edge Function every 10 minutes (72h auto-cancel/refunds).
-- verify_jwt = false on the function; the function uses service_role from its own secrets.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron is not enabled; enable it in Supabase Dashboard → Database → Extensions, then re-run this migration.';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE NOTICE 'pg_net is not enabled; enable it in Supabase Dashboard → Database → Extensions, then re-run this migration.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'thriftline-process-fulfillment-sla') THEN
    PERFORM cron.unschedule('thriftline-process-fulfillment-sla');
  END IF;

  SELECT cron.schedule(
    'thriftline-process-fulfillment-sla',
    '*/10 * * * *',
    $cron$
    SELECT net.http_post(
      url := 'https://zakorrcmmswwzfihmcji.supabase.co/functions/v1/process-fulfillment-sla',
      headers := (
        jsonb_build_object('Content-Type', 'application/json')
        || COALESCE(
          (
            SELECT jsonb_build_object(
              'x-fulfillment-sla-secret',
              ds.decrypted_secret
            )
            FROM vault.decrypted_secrets ds
            WHERE ds.name = 'fulfillment_sla_job_secret'
            LIMIT 1
          ),
          '{}'::jsonb
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $cron$
  )
  INTO v_job_id;

  RAISE NOTICE 'Scheduled thriftline-process-fulfillment-sla (job_id=%)', v_job_id;
EXCEPTION
  WHEN undefined_table OR undefined_object THEN
    RAISE NOTICE 'Could not schedule process-fulfillment-sla: %', SQLERRM;
  WHEN OTHERS THEN
    RAISE WARNING 'Could not schedule process-fulfillment-sla: %', SQLERRM;
END;
$$;
