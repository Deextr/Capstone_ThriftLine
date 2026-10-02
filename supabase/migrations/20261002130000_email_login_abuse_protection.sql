-- Server-side throttling for email/password sign-in attempts (Edge Function only).
-- Stores hashed scopes, never raw emails or IP addresses.

CREATE TABLE IF NOT EXISTS public.email_login_abuse (
  scope_key text PRIMARY KEY,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  last_attempt_at timestamptz NOT NULL DEFAULT now(),
  attempt_count integer NOT NULL DEFAULT 0,
  CONSTRAINT email_login_abuse_count_nonnegative CHECK (attempt_count >= 0)
);

ALTER TABLE public.email_login_abuse ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.email_login_abuse FROM PUBLIC;
REVOKE ALL ON TABLE public.email_login_abuse FROM anon;
REVOKE ALL ON TABLE public.email_login_abuse FROM authenticated;

COMMENT ON TABLE public.email_login_abuse IS
  'Hashed email/IP login attempt counters. service_role only via SECURITY DEFINER RPC.';

-- Returns ok, cooldown (same email < 3s), email_hourly (15/hour per email),
-- or ip_hourly (40/hour per IP scope).
CREATE OR REPLACE FUNCTION public.claim_email_login_attempt(
  p_email_hash text,
  p_ip_hash text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_inserted integer;
  v_window timestamptz;
  v_last timestamptz;
  v_count integer;
BEGIN
  IF p_email_hash IS NULL OR length(trim(p_email_hash)) < 32 THEN
    RAISE EXCEPTION 'invalid email login scope' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.email_login_abuse (scope_key, window_started_at, last_attempt_at, attempt_count)
  VALUES ('e:' || trim(p_email_hash), v_now, v_now, 1)
  ON CONFLICT (scope_key) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    SELECT window_started_at, last_attempt_at, attempt_count
      INTO v_window, v_last, v_count
    FROM public.email_login_abuse
    WHERE scope_key = 'e:' || trim(p_email_hash)
    FOR UPDATE;

    IF v_now - v_window >= interval '1 hour' THEN
      UPDATE public.email_login_abuse
      SET window_started_at = v_now,
          last_attempt_at = v_now,
          attempt_count = 1
      WHERE scope_key = 'e:' || trim(p_email_hash);
    ELSIF v_now - v_last < interval '3 seconds' THEN
      RETURN 'cooldown';
    ELSIF v_count >= 15 THEN
      RETURN 'email_hourly';
    ELSE
      UPDATE public.email_login_abuse
      SET last_attempt_at = v_now,
          attempt_count = v_count + 1
      WHERE scope_key = 'e:' || trim(p_email_hash);
    END IF;
  END IF;

  IF p_ip_hash IS NOT NULL AND length(trim(p_ip_hash)) >= 32 THEN
    INSERT INTO public.email_login_abuse (scope_key, window_started_at, last_attempt_at, attempt_count)
    VALUES ('ip:' || trim(p_ip_hash), v_now, v_now, 1)
    ON CONFLICT (scope_key) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    IF v_inserted = 0 THEN
      SELECT window_started_at, last_attempt_at, attempt_count
        INTO v_window, v_last, v_count
      FROM public.email_login_abuse
      WHERE scope_key = 'ip:' || trim(p_ip_hash)
      FOR UPDATE;

      IF v_now - v_window >= interval '1 hour' THEN
        UPDATE public.email_login_abuse
        SET window_started_at = v_now,
            last_attempt_at = v_now,
            attempt_count = 1
        WHERE scope_key = 'ip:' || trim(p_ip_hash);
      ELSIF v_count >= 40 THEN
        RETURN 'ip_hourly';
      ELSE
        UPDATE public.email_login_abuse
        SET last_attempt_at = v_now,
            attempt_count = v_count + 1
        WHERE scope_key = 'ip:' || trim(p_ip_hash);
      END IF;
    END IF;
  END IF;

  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.claim_email_login_attempt(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_email_login_attempt(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.claim_email_login_attempt(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_email_login_attempt(text, text) TO service_role;

COMMENT ON FUNCTION public.claim_email_login_attempt(text, text) IS
  'Service-role only. Throttles email/password login attempts by hashed email and optional hashed IP.';
