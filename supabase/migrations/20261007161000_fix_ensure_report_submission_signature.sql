-- Fix: PL/pgSQL calls _ensure_report_submission(..., 1, ...) with integer literal 1.
-- Function was declared (uuid, smallint, uuid) so Postgres reports 42883 "does not exist".

DROP FUNCTION IF EXISTS public._ensure_report_submission(uuid, smallint, uuid);
DROP FUNCTION IF EXISTS public._ensure_report_submission(uuid, integer, uuid);

CREATE OR REPLACE FUNCTION public._ensure_report_submission(
  p_report_id uuid,
  p_attempt integer,
  p_submitted_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_attempt smallint;
BEGIN
  IF p_attempt IS NULL OR p_attempt NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'Invalid evidence attempt %', p_attempt;
  END IF;
  v_attempt := p_attempt::smallint;

  INSERT INTO public.report_evidence_submissions (
    report_id, attempt_number, submitted_by
  ) VALUES (
    p_report_id, v_attempt, p_submitted_by
  )
  ON CONFLICT (report_id, attempt_number) DO UPDATE
    SET submitted_at = public.report_evidence_submissions.submitted_at
  RETURNING submission_id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public._ensure_report_submission(uuid, integer, uuid) FROM PUBLIC, anon, authenticated;
