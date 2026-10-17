-- Server-side rate limits for the test-unisms-sms Edge Function.
-- Callable only with the service role. Actor must be validated in the function
-- before calling claim_unisms_test_sms_send (uses _assert_super_admin_actor).

CREATE TABLE IF NOT EXISTS public.unisms_test_sms_usage (
  scope_key text PRIMARY KEY,
  day_started date NOT NULL DEFAULT (timezone('utc', now()))::date,
  send_count integer NOT NULL DEFAULT 0,
  last_send_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unisms_test_sms_usage_count_nonnegative CHECK (send_count >= 0)
);

ALTER TABLE public.unisms_test_sms_usage ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.unisms_test_sms_usage FROM PUBLIC;
REVOKE ALL ON TABLE public.unisms_test_sms_usage FROM anon;
REVOKE ALL ON TABLE public.unisms_test_sms_usage FROM authenticated;

COMMENT ON TABLE public.unisms_test_sms_usage IS
  'Daily and per-user counters for Super Admin UniSMS connectivity tests. No client access.';

-- Per Super Admin: 5 sends per UTC day, 60s cooldown.
-- Global: 20 sends per UTC day across all Super Admins.
CREATE OR REPLACE FUNCTION public.claim_unisms_test_sms_send(p_actor uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_today date := (timezone('utc', v_now))::date;
  v_user_key text := 'user:' || p_actor::text;
  v_global_key text := 'global';
  v_user_day date;
  v_user_count integer;
  v_user_last timestamptz;
  v_global_day date;
  v_global_count integer;
  v_user_daily_limit constant integer := 5;
  v_global_daily_limit constant integer := 20;
  v_cooldown_seconds constant integer := 60;
BEGIN
  PERFORM public._assert_super_admin_actor(p_actor);

  SELECT day_started, send_count, last_send_at
    INTO v_user_day, v_user_count, v_user_last
  FROM public.unisms_test_sms_usage
  WHERE scope_key = v_user_key
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.unisms_test_sms_usage (scope_key, day_started, send_count, last_send_at)
    VALUES (v_user_key, v_today, 0, v_now - interval '2 minutes');
    v_user_day := v_today;
    v_user_count := 0;
    v_user_last := v_now - interval '2 minutes';
  END IF;

  IF v_user_day IS DISTINCT FROM v_today THEN
    v_user_day := v_today;
    v_user_count := 0;
  END IF;

  IF v_user_last > v_now - make_interval(secs => v_cooldown_seconds) THEN
    RETURN 'cooldown';
  END IF;

  IF v_user_count >= v_user_daily_limit THEN
    RETURN 'user_daily';
  END IF;

  SELECT day_started, send_count
    INTO v_global_day, v_global_count
  FROM public.unisms_test_sms_usage
  WHERE scope_key = v_global_key
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.unisms_test_sms_usage (scope_key, day_started, send_count, last_send_at)
    VALUES (v_global_key, v_today, 0, v_now);
    v_global_day := v_today;
    v_global_count := 0;
  END IF;

  IF v_global_day IS DISTINCT FROM v_today THEN
    v_global_day := v_today;
    v_global_count := 0;
  END IF;

  IF v_global_count >= v_global_daily_limit THEN
    RETURN 'global_daily';
  END IF;

  INSERT INTO public.unisms_test_sms_usage (scope_key, day_started, send_count, last_send_at)
  VALUES (v_user_key, v_today, 1, v_now)
  ON CONFLICT (scope_key) DO UPDATE
    SET day_started = v_today,
        send_count = CASE
          WHEN public.unisms_test_sms_usage.day_started = v_today
            THEN public.unisms_test_sms_usage.send_count + 1
          ELSE 1
        END,
        last_send_at = v_now;

  INSERT INTO public.unisms_test_sms_usage (scope_key, day_started, send_count, last_send_at)
  VALUES (v_global_key, v_today, 1, v_now)
  ON CONFLICT (scope_key) DO UPDATE
    SET day_started = v_today,
        send_count = CASE
          WHEN public.unisms_test_sms_usage.day_started = v_today
            THEN public.unisms_test_sms_usage.send_count + 1
          ELSE 1
        END,
        last_send_at = v_now;

  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.claim_unisms_test_sms_send(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_unisms_test_sms_send(uuid)
  TO service_role;

COMMENT ON FUNCTION public.claim_unisms_test_sms_send(uuid) IS
  'Service-role only. Returns ok, cooldown, user_daily, or global_daily. Caller must authenticate the Super Admin JWT separately.';
