-- Phone OTP abuse protection: hashed request IP for server-side rate limits.
-- The Flutter client still cannot read this table.

ALTER TABLE public.phone_otp_challenges
  ADD COLUMN IF NOT EXISTS client_ip_hash text;

CREATE INDEX IF NOT EXISTS phone_otp_challenges_phone_idx
  ON public.phone_otp_challenges (phone, created_at DESC);

CREATE INDEX IF NOT EXISTS phone_otp_challenges_ip_idx
  ON public.phone_otp_challenges (client_ip_hash, created_at DESC)
  WHERE client_ip_hash IS NOT NULL;
