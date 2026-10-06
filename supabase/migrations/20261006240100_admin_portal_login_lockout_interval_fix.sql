-- Fix lockout duration if 20261006240000 was applied with make_interval(mins => ...).

CREATE OR REPLACE FUNCTION public.record_admin_portal_login_failure(p_email_hash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_failed integer;
  v_locked_until timestamptz;
  v_retry integer;
  v_max_attempts constant integer := 5;
  v_lock_minutes constant integer := 5;
BEGIN
  IF p_email_hash IS NULL OR length(trim(p_email_hash)) < 32 THEN
    RAISE EXCEPTION 'invalid admin login scope' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.admin_portal_login_lockout (email_hash, failed_attempts, updated_at)
  VALUES (trim(p_email_hash), 0, v_now)
  ON CONFLICT (email_hash) DO NOTHING;

  SELECT failed_attempts, locked_until
    INTO v_failed, v_locked_until
  FROM public.admin_portal_login_lockout
  WHERE email_hash = trim(p_email_hash)
  FOR UPDATE;

  IF v_locked_until IS NOT NULL AND v_locked_until > v_now THEN
    v_retry := GREATEST(1, ceil(extract(epoch FROM (v_locked_until - v_now)))::integer);
    RETURN jsonb_build_object(
      'locked', true,
      'failed_attempts', v_failed,
      'retry_after_seconds', v_retry
    );
  END IF;

  IF v_locked_until IS NOT NULL AND v_locked_until <= v_now THEN
    v_failed := 0;
    v_locked_until := NULL;
  END IF;

  v_failed := COALESCE(v_failed, 0) + 1;

  IF v_failed >= v_max_attempts THEN
    v_locked_until := v_now + (v_lock_minutes * interval '1 minute');
    UPDATE public.admin_portal_login_lockout
    SET failed_attempts = v_failed,
        locked_until = v_locked_until,
        updated_at = v_now
    WHERE email_hash = trim(p_email_hash);

    v_retry := v_lock_minutes * 60;
    RETURN jsonb_build_object(
      'locked', true,
      'failed_attempts', v_failed,
      'retry_after_seconds', v_retry
    );
  END IF;

  UPDATE public.admin_portal_login_lockout
  SET failed_attempts = v_failed,
      locked_until = NULL,
      updated_at = v_now
  WHERE email_hash = trim(p_email_hash);

  RETURN jsonb_build_object(
    'locked', false,
    'failed_attempts', v_failed,
    'retry_after_seconds', 0
  );
END;
$$;
