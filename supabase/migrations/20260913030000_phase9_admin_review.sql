-- Phase 9 — Admin Review Center (moderation decisions only).
--
-- Gives the existing Admin JWT a narrow way to:
--   1. decide community reports (under_review → action_taken|resolved|dismissed)
--   2. close delivery problems (open → resolved)
--
-- Does not add refunds, payouts, escrow release, trust-score math, appeals,
-- reported-user notification, automatic bans, or new report/dispute tables.
--
-- Clients still cannot UPDATE reports or delivery_disputes directly.
-- Admin identity is taken from auth.uid(), never from Flutter.
--
-- Idempotent. Safe to re-run. Do not edit earlier migrations.

-- ===========================================================================
-- 1. Delivery-dispute moderation metadata
-- ===========================================================================
-- Phase 7 stored only open|resolved. Phase 9 records who closed the case
-- and an optional note. Money state is left untouched.

ALTER TABLE public.delivery_disputes
  ADD COLUMN IF NOT EXISTS admin_note text;

ALTER TABLE public.delivery_disputes
  ADD COLUMN IF NOT EXISTS reviewed_by uuid
    REFERENCES public.users (user_id) ON DELETE SET NULL;

ALTER TABLE public.delivery_disputes
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'delivery_disputes_admin_note_len'
      AND conrelid = 'public.delivery_disputes'::regclass
  ) THEN
    ALTER TABLE public.delivery_disputes
      ADD CONSTRAINT delivery_disputes_admin_note_len
      CHECK (admin_note IS NULL OR char_length(admin_note) <= 2000);
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE INDEX IF NOT EXISTS delivery_disputes_status_created_idx
  ON public.delivery_disputes (status, created_at ASC);

COMMENT ON COLUMN public.delivery_disputes.admin_note IS
  'Optional Phase 9 Admin note. Not a payment or refund instruction.';

COMMENT ON COLUMN public.delivery_disputes.reviewed_by IS
  'Admin who closed the delivery problem. Set only by close_delivery_dispute.';

-- ===========================================================================
-- 2. decide_report
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.decide_report(
  p_report_id uuid,
  p_decision text,
  p_admin_response text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_response text;
  v_report public.reports%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can review reports.'
    );
  END IF;

  IF p_report_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  v_decision := lower(trim(coalesce(p_decision, '')));
  IF v_decision NOT IN ('action_taken', 'resolved', 'dismissed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a valid decision.');
  END IF;

  v_response := trim(coalesce(p_admin_response, ''));
  IF char_length(v_response) < 8 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Write a short response for the reporter.'
    );
  END IF;
  IF char_length(v_response) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the response under 2,000 characters.'
    );
  END IF;

  SELECT * INTO v_report
  FROM public.reports
  WHERE report_id = p_report_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Report not found.');
  END IF;

  IF v_report.status IS DISTINCT FROM 'under_review'::public.report_status_enum THEN
    IF v_report.status::text = v_decision THEN
      RETURN jsonb_build_object(
        'success', true,
        'already_decided', true,
        'report_id', v_report.report_id,
        'status', v_report.status::text
      );
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'This report has already been reviewed.'
    );
  END IF;

  UPDATE public.reports
  SET
    status = v_decision::public.report_status_enum,
    admin_response = v_response,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE report_id = p_report_id
    AND status = 'under_review'::public.report_status_enum;

  IF NOT FOUND THEN
    SELECT * INTO v_report
    FROM public.reports
    WHERE report_id = p_report_id;

    IF FOUND AND v_report.status::text = v_decision THEN
      RETURN jsonb_build_object(
        'success', true,
        'already_decided', true,
        'report_id', v_report.report_id,
        'status', v_report.status::text
      );
    END IF;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'This report has already been reviewed.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'report_id', p_report_id,
    'status', v_decision
  );
END;
$$;

COMMENT ON FUNCTION public.decide_report(uuid, text, text) IS
  'Admin-only. Moves a community report out of under_review. Identity comes from auth.uid(). Idempotent for a repeated matching decision. Does not ban, refund, or notify the reported user.';

REVOKE ALL ON FUNCTION public.decide_report(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_report(uuid, text, text) TO authenticated;

-- ===========================================================================
-- 3. close_delivery_dispute
-- ===========================================================================
-- Phase 7 statuses are only open|resolved. Closing records the Admin note
-- and does not change orders, shipments, payments, or payouts.

CREATE OR REPLACE FUNCTION public.close_delivery_dispute(
  p_dispute_id uuid,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_note text;
  v_dispute public.delivery_disputes%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Please sign in.');
  END IF;

  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can close a delivery problem.'
    );
  END IF;

  IF p_dispute_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Keep the note under 2,000 characters.'
    );
  END IF;

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  IF v_dispute.status IS DISTINCT FROM 'open'::public.delivery_dispute_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'dispute_id', v_dispute.dispute_id,
      'status', v_dispute.status::text
    );
  END IF;

  UPDATE public.delivery_disputes
  SET
    status = 'resolved'::public.delivery_dispute_status_enum,
    admin_note = v_note,
    reviewed_by = v_uid,
    resolved_at = now()
  WHERE dispute_id = p_dispute_id
    AND status = 'open'::public.delivery_dispute_status_enum;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'dispute_id', p_dispute_id,
      'status', 'resolved'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'dispute_id', p_dispute_id,
    'status', 'resolved'
  );
END;
$$;

COMMENT ON FUNCTION public.close_delivery_dispute(uuid, text) IS
  'Admin-only. Marks an open delivery problem resolved. Does not refund, pay out, or change payment or shipment money state.';

REVOKE ALL ON FUNCTION public.close_delivery_dispute(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_delivery_dispute(uuid, text) TO authenticated;
