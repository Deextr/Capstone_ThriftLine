-- Trusted devices for email login.
--
-- After a successful email OTP, the Edge Function stores only a hash of a
-- random install token. The raw token stays in the phone's secure storage.
-- Login may skip a new OTP only when this table says the hash is still active
-- for that user. Expiry uses database now(), so the phone clock cannot extend it.
--
-- The Flutter client has no privileges on this table. service_role reaches it
-- through the functions below, which do not accept an expiry timestamp.

CREATE TABLE IF NOT EXISTS public.trusted_devices (
  trusted_device_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  device_token_hash text NOT NULL,
  platform text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_verified_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CONSTRAINT trusted_devices_hash_chk
    CHECK (device_token_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT trusted_devices_platform_chk
    CHECK (platform IS NULL OR platform IN ('android', 'ios', 'other')),
  CONSTRAINT trusted_devices_user_hash_key
    UNIQUE (user_id, device_token_hash)
);

CREATE INDEX IF NOT EXISTS trusted_devices_user_idx
  ON public.trusted_devices (user_id, expires_at DESC);

ALTER TABLE public.trusted_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trusted_devices FORCE ROW LEVEL SECURITY;

GRANT ALL ON public.trusted_devices TO service_role, postgres;
REVOKE ALL ON public.trusted_devices FROM anon, authenticated, PUBLIC;

COMMENT ON TABLE public.trusted_devices IS
  'Hashed install tokens that may skip email OTP for 7 days. No client access.';

-- ---------------------------------------------------------------------------
-- register_trusted_device
-- Called only by verify-email-otp after the code matches.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.register_trusted_device(
  p_user_id uuid,
  p_device_token_hash text,
  p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_platform text;
BEGIN
  IF p_user_id IS NULL
     OR p_device_token_hash IS NULL
     OR p_device_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid trusted device';
  END IF;

  v_platform := CASE
    WHEN p_platform IN ('android', 'ios', 'other') THEN p_platform
    ELSE NULL
  END;

  INSERT INTO public.trusted_devices (
    user_id,
    device_token_hash,
    platform,
    last_verified_at,
    expires_at
  ) VALUES (
    p_user_id,
    p_device_token_hash,
    v_platform,
    now(),
    now() + interval '7 days'
  )
  ON CONFLICT (user_id, device_token_hash)
  DO UPDATE SET
    platform = EXCLUDED.platform,
    last_verified_at = now(),
    expires_at = now() + interval '7 days',
    revoked_at = NULL;
END;
$$;

COMMENT ON FUNCTION public.register_trusted_device(uuid, text, text) IS
  'Starts or refreshes a 7-day trusted-device grant from database now().';

-- ---------------------------------------------------------------------------
-- trusted_device_is_active
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trusted_device_is_active(
  p_user_id uuid,
  p_device_token_hash text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.trusted_devices d
    WHERE d.user_id = p_user_id
      AND d.device_token_hash = p_device_token_hash
      AND d.revoked_at IS NULL
      AND d.expires_at > now()
  );
$$;

COMMENT ON FUNCTION public.trusted_device_is_active(uuid, text) IS
  'True only for an unrevoked grant whose expires_at is still after database now().';

-- ---------------------------------------------------------------------------
-- revoke_trusted_device
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.revoke_trusted_device(
  p_user_id uuid,
  p_device_token_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.trusted_devices
  SET revoked_at = now()
  WHERE user_id = p_user_id
    AND device_token_hash = p_device_token_hash
    AND revoked_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.revoke_trusted_device(uuid, text) IS
  'Revokes one install token for one user. Other users and devices are unchanged.';

REVOKE ALL ON FUNCTION public.register_trusted_device(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trusted_device_is_active(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_trusted_device(uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.register_trusted_device(uuid, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.trusted_device_is_active(uuid, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.revoke_trusted_device(uuid, text) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.register_trusted_device(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.trusted_device_is_active(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_trusted_device(uuid, text) TO service_role;

NOTIFY pgrst, 'reload schema';
