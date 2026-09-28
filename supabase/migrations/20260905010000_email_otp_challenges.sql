-- Email OTP challenges for signup and login. The Flutter client never reads
-- the code hash. Edge Functions (service_role) insert and consume rows.

CREATE TABLE IF NOT EXISTS public.email_otp_challenges (
  challenge_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (user_id) ON DELETE CASCADE,
  email text NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempt_count integer NOT NULL DEFAULT 0,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS email_otp_challenges_user_idx
  ON public.email_otp_challenges (user_id, created_at DESC);

ALTER TABLE public.email_otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_otp_challenges FORCE ROW LEVEL SECURITY;

-- No client policies. Only service_role / postgres can read or write.
GRANT ALL ON public.email_otp_challenges TO service_role, postgres;
REVOKE ALL ON public.email_otp_challenges FROM anon, authenticated, PUBLIC;
