-- Buyer/Seller notification prefs, seller shop avatar, email-change OTP purpose.

ALTER TABLE public.seller_profiles
  ADD COLUMN IF NOT EXISTS shop_avatar_url text;

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS buyer_push_notifications_enabled boolean,
  ADD COLUMN IF NOT EXISTS seller_push_notifications_enabled boolean,
  ADD COLUMN IF NOT EXISTS buyer_email_notifications_enabled boolean,
  ADD COLUMN IF NOT EXISTS seller_email_notifications_enabled boolean;

UPDATE public.user_settings
SET
  buyer_push_notifications_enabled = COALESCE(
    buyer_push_notifications_enabled,
    push_notifications_enabled,
    true
  ),
  seller_push_notifications_enabled = COALESCE(
    seller_push_notifications_enabled,
    push_notifications_enabled,
    true
  ),
  buyer_email_notifications_enabled = COALESCE(
    buyer_email_notifications_enabled,
    email_notifications_enabled,
    false
  ),
  seller_email_notifications_enabled = COALESCE(
    seller_email_notifications_enabled,
    email_notifications_enabled,
    false
  );

ALTER TABLE public.user_settings
  ALTER COLUMN buyer_push_notifications_enabled SET NOT NULL,
  ALTER COLUMN seller_push_notifications_enabled SET NOT NULL,
  ALTER COLUMN buyer_email_notifications_enabled SET NOT NULL,
  ALTER COLUMN seller_email_notifications_enabled SET NOT NULL;

ALTER TABLE public.user_settings
  ALTER COLUMN buyer_push_notifications_enabled SET DEFAULT true,
  ALTER COLUMN seller_push_notifications_enabled SET DEFAULT true,
  ALTER COLUMN buyer_email_notifications_enabled SET DEFAULT false,
  ALTER COLUMN seller_email_notifications_enabled SET DEFAULT false;

ALTER TABLE public.email_otp_challenges
  ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'login_verify',
  ADD COLUMN IF NOT EXISTS target_email text;

CREATE OR REPLACE FUNCTION public.user_notification_channel_enabled(
  p_user_id uuid,
  p_audience public.notification_audience_enum,
  p_channel text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settings public.user_settings%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_settings
  FROM public.user_settings
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN true;
  END IF;

  IF p_channel = 'push' THEN
    RETURN CASE p_audience
      WHEN 'seller'::public.notification_audience_enum
        THEN COALESCE(v_settings.seller_push_notifications_enabled, true)
      WHEN 'buyer'::public.notification_audience_enum
        THEN COALESCE(v_settings.buyer_push_notifications_enabled, true)
      ELSE true
    END;
  END IF;

  IF p_channel = 'email' THEN
    RETURN CASE p_audience
      WHEN 'seller'::public.notification_audience_enum
        THEN COALESCE(v_settings.seller_email_notifications_enabled, false)
      WHEN 'buyer'::public.notification_audience_enum
        THEN COALESCE(v_settings.buyer_email_notifications_enabled, false)
      ELSE true
    END;
  END IF;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.user_notification_channel_enabled IS
  'Optional notification delivery gates. In-app notifications are unaffected.';

REVOKE ALL ON FUNCTION public.user_notification_channel_enabled(uuid, notification_audience_enum, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_notification_channel_enabled(uuid, notification_audience_enum, text)
  TO postgres, service_role;
