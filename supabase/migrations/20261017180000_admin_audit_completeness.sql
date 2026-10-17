-- Admin activity logs: server-side reliability, forged-log prevention, and missing actions.

-- ---------------------------------------------------------------------------
-- Trusted audit writer for admin RPCs (uses auth.uid(), not client-supplied id).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.log_admin_action_audit(
  p_category text,
  p_event_type text,
  p_status text,
  p_summary text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN public.write_admin_audit_log(
    p_category,
    p_event_type,
    p_status,
    p_summary,
    auth.uid(),
    p_target_type,
    p_target_id,
    COALESCE(p_details, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.log_admin_action_audit(
  text, text, text, text, text, text, jsonb
) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Client-callable audit: only low-risk portal telemetry (not financial actions).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_admin_audit_log(
  p_category text,
  p_event_type text,
  p_status text,
  p_summary text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_email text;
  v_event text := lower(trim(COALESCE(p_event_type, '')));
  v_details jsonb := COALESCE(p_details, '{}'::jsonb);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_category = 'account_management' THEN
    RAISE EXCEPTION 'account management audit is recorded by the server'
      USING ERRCODE = '42501';
  END IF;

  IF p_category NOT IN (
    'authentication',
    'system_security'
  ) THEN
    RAISE EXCEPTION 'this audit category must be recorded by the server'
      USING ERRCODE = '42501';
  END IF;

  IF v_event NOT IN (
    'admin_logout',
    'admin_login_completed',
    'marketplace_report_exported'
  ) THEN
    RAISE EXCEPTION 'event type cannot be recorded from the client'
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid audit status' USING ERRCODE = '22023';
  END IF;

  IF v_event = '' OR p_summary IS NULL OR length(trim(p_summary)) = 0 THEN
    RAISE EXCEPTION 'event_type and summary required' USING ERRCODE = '22023';
  END IF;

  SELECT u.email INTO v_email
  FROM public.users u
  WHERE u.user_id = auth.uid();

  INSERT INTO public.admin_audit_logs (
    category,
    event_type,
    status,
    summary,
    actor_user_id,
    actor_email,
    target_type,
    target_id,
    details
  )
  VALUES (
    p_category,
    trim(p_event_type),
    p_status,
    left(trim(p_summary), 500),
    auth.uid(),
    v_email,
    NULLIF(trim(p_target_type), ''),
    NULLIF(trim(p_target_id), ''),
    v_details
  )
  RETURNING log_id INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Moderation trigger: skip generic escrow rows when RPC writes a detailed log.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.audit_admin_moderation_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new jsonb := to_jsonb(NEW);
  v_old jsonb := to_jsonb(OLD);
  v_event text;
  v_summary text;
  v_category text;
  v_target_type text;
  v_target_id text;
  v_old_status text;
  v_new_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'user_verifications' THEN
    v_old_status := v_old->>'verification_status';
    v_new_status := v_new->>'verification_status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'approved' THEN
      v_event := 'seller_verification_approved';
      v_summary := 'Approved seller verification';
    ELSIF v_new_status = 'rejected' THEN
      v_event := 'seller_verification_rejected';
      v_summary := 'Rejected seller verification';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'seller_verification';
    v_target_type := 'verification';
    v_target_id := v_new->>'verification_id';
  ELSIF TG_TABLE_NAME = 'reports' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'needs_more_evidence' THEN
      v_event := 'order_report_evidence_requested';
      v_summary := 'Requested evidence for an order report';
    ELSIF v_new_status IN ('resolved', 'dismissed') AND v_new->>'order_id' IS NOT NULL THEN
      v_event := 'order_report_closed';
      v_summary := 'Resolved an order report';
    ELSIF v_new_status IN ('resolved', 'dismissed') THEN
      v_event := 'report_decided';
      v_summary := 'Resolved a community report';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'reports_disputes';
    v_target_type := 'report';
    v_target_id := v_new->>'report_id';
  ELSIF TG_TABLE_NAME = 'looking_for_reports' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status NOT IN ('resolved', 'dismissed') THEN
      RETURN NEW;
    END IF;
    v_event := 'looking_for_report_decided';
    v_summary := 'Resolved a Looking For report';
    v_category := 'reports_disputes';
    v_target_type := 'looking_for_report';
    v_target_id := v_new->>'report_id';
  ELSIF TG_TABLE_NAME = 'delivery_disputes' THEN
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_old_status IS DISTINCT FROM 'open' OR v_new_status IS DISTINCT FROM 'resolved' THEN
      RETURN NEW;
    END IF;
    v_event := 'delivery_dispute_closed';
    v_summary := 'Resolved a delivery dispute';
    v_category := 'reports_disputes';
    v_target_type := 'dispute';
    v_target_id := v_new->>'dispute_id';
  ELSIF TG_TABLE_NAME = 'escrow' THEN
    IF current_setting('thriftline.skip_escrow_audit', true) = '1' THEN
      RETURN NEW;
    END IF;
    v_old_status := v_old->>'status';
    v_new_status := v_new->>'status';
    IF v_new_status IS NOT DISTINCT FROM v_old_status THEN
      RETURN NEW;
    END IF;
    IF v_new_status = 'released' THEN
      v_event := 'delivery_payment_released';
      v_summary := 'Released escrow payment';
    ELSIF v_new_status = 'refunded' THEN
      v_event := 'delivery_payment_refunded';
      v_summary := 'Refunded escrow payment';
    ELSE
      RETURN NEW;
    END IF;
    v_category := 'payments_escrow';
    v_target_type := 'escrow';
    v_target_id := COALESCE(v_new->>'dispute_id', v_new->>'escrow_id');
  ELSE
    RETURN NEW;
  END IF;

  PERFORM public.write_admin_audit_log(
    v_category,
    v_event,
    'success',
    v_summary,
    auth.uid(),
    v_target_type,
    v_target_id,
    jsonb_build_object('status', v_new_status)
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._record_escrow_refund_decision(
  p_escrow_id uuid,
  p_provider text,
  p_paymongo_refund_id text,
  p_provider_status text,
  p_transfer_link text,
  p_transfer_link_expires_at timestamptz,
  p_provider_error text,
  p_default_reason text
)
RETURNS public.escrow_refund_state_enum
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_state public.escrow_refund_state_enum;
  v_escrow public.escrow%ROWTYPE;
  v_link text := NULLIF(btrim(coalesce(p_transfer_link, '')), '');
BEGIN
  v_state := public._resolve_refund_state(v_provider, p_provider_status, v_link);

  PERFORM set_config('thriftline.skip_escrow_audit', '1', true);

  UPDATE public.escrow
  SET
    status = 'refunded'::public.escrow_status_enum,
    refunded_at = now(),
    refund_reason = COALESCE(refund_reason, p_default_reason),
    refund_lock_at = NULL,
    refund_provider = v_provider::public.escrow_refund_provider_enum,
    paymongo_refund_id = NULLIF(btrim(coalesce(p_paymongo_refund_id, '')), ''),
    refund_provider_status = COALESCE(
      NULLIF(btrim(coalesce(p_provider_status, '')), ''),
      v_provider
    ),
    refund_state = v_state,
    refund_provider_error = NULLIF(btrim(coalesce(p_provider_error, '')), ''),
    refund_last_checked_at = now(),
    refund_completed_at = CASE
      WHEN v_state = 'succeeded'::public.escrow_refund_state_enum THEN now()
      ELSE NULL
    END
  WHERE escrow_id = p_escrow_id
    AND status IN (
      'held'::public.escrow_status_enum,
      'disputed'::public.escrow_status_enum
    )
  RETURNING * INTO v_escrow;

  PERFORM set_config('thriftline.skip_escrow_audit', '0', true);

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, transfer_link, transfer_link_expires_at
  )
  VALUES (
    v_escrow.escrow_id,
    v_escrow.buyer_id,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN v_link ELSE NULL END,
    CASE WHEN v_state = 'awaiting_buyer_claim' THEN p_transfer_link_expires_at ELSE NULL END
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET transfer_link = EXCLUDED.transfer_link,
      transfer_link_expires_at = EXCLUDED.transfer_link_expires_at;

  IF v_state = 'succeeded'::public.escrow_refund_state_enum THEN
    UPDATE public.payments
    SET payment_status = 'refunded'::public.payment_status_enum
    WHERE payment_id = v_escrow.payment_id
      AND payment_status = 'paid'::public.payment_status_enum;
  END IF;

  IF v_state = 'manual_required'::public.escrow_refund_state_enum THEN
    PERFORM public._notify_refund_admins(
      v_escrow,
      'Manual GCash refund needed',
      'Send ' || public._peso_text(v_escrow.amount_centavos) ||
        ' to the buyer through GCash for Order #' ||
        COALESCE(
          (SELECT o.order_number FROM public.orders o WHERE o.order_id = v_escrow.order_id),
          ''
        ) || ', then record the transfer in Buyer refunds.'
    );
  END IF;

  RETURN v_state;
END;
$$;

-- ---------------------------------------------------------------------------
-- Marketplace account disable (audit was blocked by record_admin_audit_log).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.disable_marketplace_account(
  p_user_id uuid,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.user_role_enum;
  v_status public.account_status_enum;
  v_name text;
  v_reason text := btrim(COALESCE(p_reason, ''));
  v_notes text := NULLIF(btrim(COALESCE(p_notes, '')), '');
  v_updated integer := 0;
  v_after public.account_status_enum;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_reason NOT IN (
    'Violation of marketplace guidelines',
    'Fraudulent or suspicious activity',
    'Repeated abusive behavior',
    'Multiple confirmed reports',
    'Account security concerns',
    'Other policy violation'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'invalid_reason',
      'error', 'Choose a reason for disabling this account.'
    );
  END IF;

  IF v_notes IS NOT NULL AND char_length(v_notes) > 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'notes_too_long',
      'error', 'Keep additional notes under 1,000 characters.'
    );
  END IF;

  SELECT u.role, u.account_status, COALESCE(u.full_name, u.username, u.email, 'User')
    INTO v_role, v_status, v_name
  FROM public.users u
  WHERE u.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_found',
      'error', 'That account was not found.'
    );
  END IF;

  IF v_role IN (
    'admin'::public.user_role_enum,
    'super_admin'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'Administrator accounts are managed separately.'
    );
  END IF;

  IF v_role NOT IN (
    'buyer'::public.user_role_enum,
    'seller'::public.user_role_enum
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'not_marketplace_account',
      'error', 'This account cannot be managed here.'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.looking_for_account_sanctions s
    WHERE s.user_id = p_user_id
      AND s.permanently_disabled_at IS NOT NULL
  ) OR v_status = 'banned'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_banned',
      'error', 'Account banned. This account is already restricted.'
    );
  END IF;

  IF v_status = 'suspended'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_disabled',
      'error', 'Account already disabled. No further disabling action is available.'
    );
  END IF;

  IF v_status IS DISTINCT FROM 'active'::public.account_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'already_restricted',
      'error', 'This account is already restricted.'
    );
  END IF;

  UPDATE public.users
  SET account_status = 'suspended'::public.account_status_enum
  WHERE user_id = p_user_id
    AND role = v_role
    AND account_status = 'active'::public.account_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  SELECT u.account_status
    INTO v_after
  FROM public.users u
  WHERE u.user_id = p_user_id;

  IF v_updated <> 1
     OR v_after IS DISTINCT FROM 'suspended'::public.account_status_enum THEN
    RAISE EXCEPTION 'This account could not be disabled.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.revoke_marketplace_sessions(p_user_id);

  PERFORM public.log_admin_action_audit(
    'account_management',
    'marketplace_account_disabled',
    'success',
    left('Disabled marketplace account ' || v_name, 500),
    'user',
    p_user_id::text,
    jsonb_build_object(
      'reason', v_reason,
      'notes', v_notes,
      'previous_status', 'active',
      'new_status', 'suspended',
      'full_name', v_name
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'account_status', 'suspended',
    'user_id', p_user_id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Refund decision audit (detailed row; escrow trigger suppressed above).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalize_delivery_refund(
  p_dispute_id uuid,
  p_provider text,
  p_paymongo_refund_id text DEFAULT NULL,
  p_provider_status text DEFAULT NULL,
  p_admin_note text DEFAULT NULL,
  p_transfer_link text DEFAULT NULL,
  p_transfer_link_expires_at timestamptz DEFAULT NULL,
  p_provider_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_provider text;
  v_dispute public.delivery_disputes%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_escrow public.escrow%ROWTYPE;
  v_note text;
  v_state public.escrow_refund_state_enum;
  v_summary text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can refund this payment.');
  END IF;

  v_provider := lower(trim(coalesce(p_provider, '')));
  IF v_provider NOT IN ('paymongo', 'internal') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown refund provider.');
  END IF;

  v_note := nullif(trim(coalesce(p_admin_note, '')), '');

  SELECT * INTO v_dispute
  FROM public.delivery_disputes
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery problem not found.');
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE order_id = v_dispute.order_id
  FOR UPDATE;

  SELECT * INTO v_escrow
  FROM public.escrow
  WHERE order_id = v_order.order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No held payment was found for this order.');
  END IF;

  IF v_escrow.status = 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_decided', true,
      'decision', 'refund',
      'status', 'refunded',
      'refund_provider', v_escrow.refund_provider::text,
      'refund_state', v_escrow.refund_state::text,
      'amount_centavos', v_escrow.amount_centavos
    );
  END IF;

  IF v_escrow.status = 'released'::public.escrow_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This payment was already released as seller earnings.'
    );
  END IF;

  PERFORM public._close_open_dispute(v_dispute.dispute_id, v_uid, v_note);

  UPDATE public.escrow
  SET resolved_by = v_uid,
      dispute_id = v_dispute.dispute_id,
      refund_reason = COALESCE(v_note, refund_reason)
  WHERE escrow_id = v_escrow.escrow_id;

  v_state := public._record_escrow_refund_decision(
    v_escrow.escrow_id,
    v_provider,
    p_paymongo_refund_id,
    p_provider_status,
    p_transfer_link,
    p_transfer_link_expires_at,
    p_provider_error,
    'admin_refund'
  );

  IF v_state IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not record this refund.');
  END IF;

  UPDATE public.shipments
  SET
    delivery_status = 'cancelled'::public.delivery_status_enum,
    completion_reason = COALESCE(completion_reason, 'admin_refunded_payment'),
    completed_at = COALESCE(completed_at, now())
  WHERE order_id = v_order.order_id
    AND delivery_status IS DISTINCT FROM 'cancelled'::public.delivery_status_enum;

  UPDATE public.orders
  SET order_status = 'cancelled'::public.order_status_enum,
      updated_at = now()
  WHERE order_id = v_order.order_id
    AND order_status IS DISTINCT FROM 'cancelled'::public.order_status_enum;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
  PERFORM public._notify_refund_buyer(v_escrow, v_state);

  PERFORM public.notify_user(
    v_order.seller_id,
    'system',
    'Payment refunded',
    'The held payment for Order #' || COALESCE(v_order.order_number, '') ||
      ' was refunded to the buyer and is not available as earnings.',
    jsonb_build_object('order_id', v_order.order_id)
  );

  v_summary := 'Approved buyer refund for Order #' || COALESCE(v_order.order_number, '') ||
    ' (state: ' || v_state::text || ')';
  IF v_state = 'manual_required'::public.escrow_refund_state_enum THEN
    v_summary := v_summary || ' — GCash transfer still required';
  ELSIF v_state = 'manual_completed'::public.escrow_refund_state_enum
        OR v_state = 'succeeded'::public.escrow_refund_state_enum THEN
    v_summary := v_summary || ' — refund completed';
  END IF;

  PERFORM public.log_admin_action_audit(
    'payments_escrow',
    'buyer_refund_decided',
    'success',
    v_summary,
    'order',
    v_order.order_id::text,
    jsonb_build_object(
      'escrow_id', v_escrow.escrow_id,
      'order_number', v_order.order_number,
      'refund_provider', v_provider,
      'refund_state', v_state::text,
      'amount_centavos', v_escrow.amount_centavos
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_decided', false,
    'decision', 'refund',
    'status', 'refunded',
    'refund_provider', v_provider,
    'refund_state', v_state::text,
    'amount_centavos', v_escrow.amount_centavos
  );
END;
$$;

-- Manual GCash refund completion (only when transfer is recorded).
CREATE OR REPLACE FUNCTION public.admin_record_manual_refund(
  p_escrow_id uuid,
  p_amount_centavos integer,
  p_reference text,
  p_sent_at timestamptz,
  p_evidence_path text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_gcash_account_name text DEFAULT NULL,
  p_gcash_mobile_number text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_escrow public.escrow%ROWTYPE;
  v_details public.escrow_refund_details%ROWTYPE;
  v_reference text := btrim(coalesce(p_reference, ''));
  v_note text := NULLIF(btrim(coalesce(p_note, '')), '');
  v_name text;
  v_mobile text;
  v_evidence text := NULLIF(btrim(coalesce(p_evidence_path, '')), '');
  v_number text;
  v_updated integer := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can record a manual refund.');
  END IF;

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = p_escrow_id FOR UPDATE;
  IF NOT FOUND OR v_escrow.status IS DISTINCT FROM 'refunded'::public.escrow_status_enum THEN
    RETURN jsonb_build_object('success', false, 'error', 'Refund not found.');
  END IF;

  IF v_escrow.refund_state = 'manual_completed'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object('success', true, 'already_recorded', true);
  END IF;

  IF v_escrow.refund_state IS DISTINCT FROM 'manual_required'::public.escrow_refund_state_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This refund is still with PayMongo. Do not send GCash unless PayMongo has failed.'
    );
  END IF;

  IF v_escrow.refund_lock_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'A PayMongo attempt has an unconfirmed result. Check PayMongo status before sending GCash.'
    );
  END IF;

  IF p_amount_centavos IS DISTINCT FROM v_escrow.amount_centavos THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The amount sent must equal the refund amount of ' ||
        public._peso_text(v_escrow.amount_centavos) || '.'
    );
  END IF;

  IF char_length(v_reference) NOT BETWEEN 4 AND 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash reference number.');
  END IF;

  IF p_sent_at IS NULL OR p_sent_at > now() + interval '1 hour'
     OR p_sent_at < v_escrow.refunded_at - interval '1 day' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the date the GCash transfer was sent.');
  END IF;

  IF v_evidence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Attach the GCash receipt for this refund.');
  END IF;

  IF v_evidence NOT LIKE 'refunds/' || v_escrow.buyer_id::text || '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'The receipt file is not linked to this refund.');
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 1,000 characters.');
  END IF;

  SELECT * INTO v_details FROM public.escrow_refund_details WHERE escrow_id = v_escrow.escrow_id;

  v_name := COALESCE(NULLIF(btrim(coalesce(p_gcash_account_name, '')), ''), v_details.gcash_account_name);
  v_mobile := COALESCE(
    NULLIF(regexp_replace(coalesce(p_gcash_mobile_number, ''), '[^0-9]', '', 'g'), ''),
    v_details.gcash_mobile_number
  );

  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 2 AND 80 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash account name the refund was sent to.');
  END IF;
  IF v_mobile IS NULL OR v_mobile !~ '^09[0-9]{9}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash number the refund was sent to.');
  END IF;

  INSERT INTO public.escrow_refund_details (
    escrow_id, buyer_id, gcash_account_name, gcash_mobile_number,
    manual_amount_centavos, manual_reference, manual_sent_at,
    manual_evidence_path, manual_note, manual_recorded_by, manual_recorded_at
  )
  VALUES (
    v_escrow.escrow_id, v_escrow.buyer_id, v_name, v_mobile,
    p_amount_centavos, v_reference, p_sent_at,
    v_evidence, v_note, v_uid, now()
  )
  ON CONFLICT (escrow_id) DO UPDATE
  SET gcash_account_name = EXCLUDED.gcash_account_name,
      gcash_mobile_number = EXCLUDED.gcash_mobile_number,
      manual_amount_centavos = EXCLUDED.manual_amount_centavos,
      manual_reference = EXCLUDED.manual_reference,
      manual_sent_at = EXCLUDED.manual_sent_at,
      manual_evidence_path = EXCLUDED.manual_evidence_path,
      manual_note = EXCLUDED.manual_note,
      manual_recorded_by = EXCLUDED.manual_recorded_by,
      manual_recorded_at = EXCLUDED.manual_recorded_at,
      transfer_link = NULL,
      transfer_link_expires_at = NULL;

  UPDATE public.escrow
  SET refund_state = 'manual_completed',
      refund_completed_at = now(),
      refund_last_checked_at = now()
  WHERE escrow_id = v_escrow.escrow_id
    AND refund_state = 'manual_required'::public.escrow_refund_state_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not complete this refund record.');
  END IF;

  UPDATE public.payments
  SET payment_status = 'refunded'::public.payment_status_enum
  WHERE payment_id = v_escrow.payment_id
    AND payment_status = 'paid'::public.payment_status_enum;

  SELECT COALESCE(o.order_number, '') INTO v_number
  FROM public.orders o WHERE o.order_id = v_escrow.order_id;

  PERFORM public.log_admin_action_audit(
    'payments_escrow',
    'manual_refund_recorded',
    'success',
    'Confirmed manual GCash refund of ' || public._peso_text(p_amount_centavos) ||
      ' for Order #' || v_number,
    'order',
    v_escrow.order_id::text,
    jsonb_build_object(
      'escrow_id', v_escrow.escrow_id,
      'order_number', v_number,
      'amount_centavos', p_amount_centavos,
      'gcash_reference', v_reference,
      'sent_at', p_sent_at,
      'refund_state', 'manual_completed',
      'has_evidence', v_evidence IS NOT NULL
    )
  );

  SELECT * INTO v_escrow FROM public.escrow WHERE escrow_id = v_escrow.escrow_id;
  PERFORM public._notify_refund_buyer(v_escrow, 'manual_completed');

  RETURN jsonb_build_object('success', true, 'refund_state', 'manual_completed');
END;
$$;

-- ---------------------------------------------------------------------------
-- Seller payouts: audit only after a successful status change.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_mark_seller_payout_paid(
  p_payout_id uuid,
  p_transferred_amount_centavos integer,
  p_gcash_reference text,
  p_transferred_at timestamptz,
  p_evidence_path text DEFAULT NULL,
  p_admin_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_payout public.seller_payouts%ROWTYPE;
  v_reference text := btrim(coalesce(p_gcash_reference, ''));
  v_note text := NULLIF(btrim(coalesce(p_admin_note, '')), '');
  v_evidence text := NULLIF(btrim(coalesce(p_evidence_path, '')), '');
  v_updated integer := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can record a payout transfer.');
  END IF;

  SELECT * INTO v_payout
  FROM public.seller_payouts
  WHERE payout_id = p_payout_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payout request not found.');
  END IF;

  IF v_payout.status = 'paid'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object('success', true, 'already_recorded', true);
  END IF;

  IF v_payout.status IS DISTINCT FROM 'requested'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a waiting payout request can be marked as paid.'
    );
  END IF;

  IF p_transferred_amount_centavos IS DISTINCT FROM v_payout.amount_centavos THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'The amount sent must equal the requested ' ||
        public._peso_text(v_payout.amount_centavos) ||
        '. If you sent a different amount, reject this request and ask the seller to request again.'
    );
  END IF;

  IF char_length(v_reference) NOT BETWEEN 4 AND 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the GCash reference number.');
  END IF;

  IF p_transferred_at IS NULL
     OR p_transferred_at > now() + interval '1 hour'
     OR p_transferred_at < v_payout.requested_at - interval '1 day' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter the date the GCash transfer was sent.');
  END IF;

  IF v_evidence IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Attach the GCash receipt for this transfer.');
  END IF;

  IF v_evidence NOT LIKE 'payouts/' || v_payout.seller_id::text || '/%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'The receipt file is not linked to this payout.');
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Keep the note under 1,000 characters.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seller_payouts
    WHERE gcash_reference = v_reference
      AND payout_id IS DISTINCT FROM v_payout.payout_id
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This GCash reference is already recorded on another payout.'
    );
  END IF;

  UPDATE public.seller_payouts
  SET status = 'paid'::public.seller_payout_status_enum,
      transferred_amount_centavos = p_transferred_amount_centavos,
      gcash_reference = v_reference,
      transferred_at = p_transferred_at,
      evidence_path = v_evidence,
      admin_note = v_note,
      processed_by = v_uid,
      processed_at = now()
  WHERE payout_id = v_payout.payout_id
    AND status = 'requested'::public.seller_payout_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not mark this payout as paid.');
  END IF;

  PERFORM public.log_admin_action_audit(
    'payments_escrow',
    'seller_payout_paid',
    'success',
    'Confirmed GCash payout of ' || public._peso_text(v_payout.amount_centavos),
    'seller_payout',
    v_payout.payout_id::text,
    jsonb_build_object(
      'seller_id', v_payout.seller_id,
      'amount_centavos', v_payout.amount_centavos,
      'gcash_reference', v_reference,
      'transferred_at', p_transferred_at,
      'has_evidence', v_evidence IS NOT NULL
    )
  );

  PERFORM public.notify_user(
    v_payout.seller_id,
    'system',
    'Payout sent',
    'The ThriftLine team sent ' || public._peso_text(v_payout.amount_centavos) ||
      ' to your GCash. Reference: ' || v_reference || '.',
    jsonb_build_object('payout_id', v_payout.payout_id),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object('success', true, 'status', 'paid');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_seller_payout(
  p_payout_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_payout public.seller_payouts%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_updated integer := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an admin can reject a payout request.');
  END IF;

  IF char_length(v_reason) NOT BETWEEN 5 AND 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Give the seller a short reason (5 to 500 characters).');
  END IF;

  SELECT * INTO v_payout
  FROM public.seller_payouts
  WHERE payout_id = p_payout_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Payout request not found.');
  END IF;

  IF v_payout.status = 'rejected'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object('success', true, 'already_rejected', true);
  END IF;

  IF v_payout.status IS DISTINCT FROM 'requested'::public.seller_payout_status_enum THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only a waiting payout request can be rejected.'
    );
  END IF;

  UPDATE public.seller_payouts
  SET status = 'rejected'::public.seller_payout_status_enum,
      rejection_reason = v_reason,
      processed_by = v_uid,
      processed_at = now()
  WHERE payout_id = v_payout.payout_id
    AND status = 'requested'::public.seller_payout_status_enum;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Could not reject this payout request.');
  END IF;

  PERFORM public.log_admin_action_audit(
    'payments_escrow',
    'seller_payout_rejected',
    'success',
    'Rejected payout request of ' || public._peso_text(v_payout.amount_centavos),
    'seller_payout',
    v_payout.payout_id::text,
    jsonb_build_object(
      'seller_id', v_payout.seller_id,
      'amount_centavos', v_payout.amount_centavos,
      'reason', v_reason
    )
  );

  PERFORM public.notify_user(
    v_payout.seller_id,
    'system',
    'Payout request not completed',
    'Your payout request of ' || public._peso_text(v_payout.amount_centavos) ||
      ' was not sent: ' || v_reason || ' The amount is available again.',
    jsonb_build_object('payout_id', v_payout.payout_id),
    'seller'::public.notification_audience_enum
  );

  RETURN jsonb_build_object('success', true, 'status', 'rejected');
END;
$$;

-- ---------------------------------------------------------------------------
-- Previously unlogged admin actions.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.review_external_transaction(
  p_transaction_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tx public.external_transactions%ROWTYPE;
  v_kinds integer;
  v_note text;
  v_old_status text;
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.is_admin()
  THEN
    RAISE EXCEPTION 'only an admin can review external transaction evidence'
      USING ERRCODE = '42501';
  END IF;

  IF p_decision NOT IN ('verified', 'insufficient_evidence', 'rejected') THEN
    RAISE EXCEPTION 'decision must be verified, insufficient_evidence, or rejected';
  END IF;

  SELECT *
    INTO v_tx
  FROM public.external_transactions
  WHERE transaction_id = p_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'external transaction not found';
  END IF;

  v_old_status := v_tx.review_status;

  IF p_decision = 'verified' THEN
    SELECT count(DISTINCT e.evidence_type)::integer
      INTO v_kinds
    FROM public.external_transaction_evidence e
    WHERE e.transaction_id = p_transaction_id;

    IF COALESCE(v_kinds, 0) < 2 THEN
      RAISE EXCEPTION 'Verify needs two different kinds of evidence';
    END IF;
  END IF;

  v_note := NULLIF(btrim(COALESCE(p_note, '')), '');
  IF v_note IS NOT NULL AND char_length(v_note) > 500 THEN
    RAISE EXCEPTION 'Keep the review note under 500 characters';
  END IF;

  PERFORM set_config('thriftline.review_external', '1', true);
  UPDATE public.external_transactions
  SET review_status = p_decision,
      admin_review_note = v_note,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  WHERE transaction_id = p_transaction_id;
  PERFORM set_config('thriftline.review_external', '0', true);

  IF auth.uid() IS NOT NULL AND public.is_admin() THEN
    PERFORM public.log_admin_action_audit(
      'seller_verification',
      'external_transaction_reviewed',
      'success',
      'Reviewed external selling history (' || p_decision || ')',
      'external_transaction',
      p_transaction_id::text,
      jsonb_build_object(
        'user_id', v_tx.user_id,
        'previous_status', v_old_status,
        'new_status', p_decision
      )
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_return_shipment(p_dispute_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.return_shipments%ROWTYPE;
  v_updated integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only an admin can stop this return.'
    );
  END IF;

  SELECT * INTO v_row
  FROM public.return_shipments
  WHERE dispute_id = p_dispute_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'No return was found for this order.');
  END IF;

  IF v_row.status IN (
       'returned'::public.return_status_enum,
       'not_required'::public.return_status_enum,
       'cancelled_by_admin'::public.return_status_enum
     ) THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_recorded', true,
      'return_status', v_row.status::text
    );
  END IF;

  UPDATE public.return_shipments
  SET status = 'cancelled_by_admin'::public.return_status_enum
  WHERE return_id = v_row.return_id
    AND status IN (
      'waiting_for_rider'::public.return_status_enum,
      'rider_assigned'::public.return_status_enum,
      'picked_up'::public.return_status_enum
    );

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'This return can no longer be stopped.');
  END IF;

  PERFORM public.log_admin_action_audit(
    'reports_disputes',
    'return_shipment_cancelled',
    'success',
    'Stopped an in-progress item return for an order dispute',
    'dispute',
    p_dispute_id::text,
    jsonb_build_object(
      'order_id', v_row.order_id,
      'return_id', v_row.return_id,
      'previous_status', v_row.status::text,
      'new_status', 'cancelled_by_admin'
    )
  );

  PERFORM public.notify_user(
    v_row.buyer_id,
    'system',
    'Return stopped',
    'An admin stopped the item return. Your refund is unchanged.',
    jsonb_build_object('order_id', v_row.order_id)
  );
  PERFORM public.notify_user(
    v_row.seller_id,
    'system',
    'Return stopped',
    'An admin stopped the item return. The buyer refund is unchanged.',
    jsonb_build_object('order_id', v_row.order_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'already_recorded', false,
    'return_status', 'cancelled_by_admin'
  );
END;
$$;

-- Activity log search: escape ILIKE wildcards in user input.
CREATE OR REPLACE FUNCTION public.list_admin_audit_logs(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_actor_user_id uuid DEFAULT NULL,
  p_actor_kind text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_search text := NULLIF(trim(COALESCE(p_search, '')), '');
  v_category text := NULLIF(trim(COALESCE(p_category, '')), '');
  v_status text := NULLIF(trim(COALESCE(p_status, '')), '');
  v_actor_kind text := NULLIF(lower(trim(COALESCE(p_actor_kind, ''))), '');
  v_total bigint;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'super admin access required' USING ERRCODE = '42501';
  END IF;

  IF v_category IS NOT NULL AND v_category <> 'all'
     AND v_category NOT IN (
       'authentication',
       'seller_verification',
       'reports_disputes',
       'account_management',
       'payments_escrow',
       'system_security'
     ) THEN
    RAISE EXCEPTION 'invalid category filter' USING ERRCODE = '22023';
  END IF;

  IF v_status IS NOT NULL AND v_status <> 'all'
     AND v_status NOT IN ('success', 'failed', 'blocked') THEN
    RAISE EXCEPTION 'invalid status filter' USING ERRCODE = '22023';
  END IF;

  IF v_actor_kind IS NOT NULL
     AND v_actor_kind NOT IN ('administrator', 'super_admin', 'system') THEN
    RAISE EXCEPTION 'invalid actor filter' USING ERRCODE = '22023';
  END IF;

  IF v_search IS NOT NULL THEN
    v_search := replace(v_search, chr(92), chr(92) || chr(92));
    v_search := replace(v_search, '%', chr(92) || '%');
    v_search := replace(v_search, '_', chr(92) || '_');
  END IF;

  SELECT count(*)::bigint INTO v_total
  FROM public.admin_audit_logs l
  LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
  WHERE (
      v_category IS NULL
      OR v_category = 'all'
      OR l.category = v_category
      OR (
        v_category = 'account_management'
        AND l.category IN ('account_management', 'authentication')
      )
    )
    AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
    AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
    AND (
      v_actor_kind IS NULL
      OR (
        v_actor_kind = 'system'
        AND l.actor_user_id IS NULL
      )
      OR (
        v_actor_kind = 'super_admin'
        AND actor.role = 'super_admin'::public.user_role_enum
      )
      OR (
        v_actor_kind = 'administrator'
        AND actor.role = 'admin'::public.user_role_enum
      )
    )
    AND (p_from IS NULL OR l.created_at >= p_from)
    AND (p_to IS NULL OR l.created_at < p_to)
    AND (
      v_search IS NULL
      OR l.summary ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      OR l.event_type ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      OR COALESCE(l.target_type, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
    );

  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT
      l.log_id,
      l.created_at,
      l.category,
      l.event_type,
      l.status,
      l.summary,
      l.actor_user_id,
      l.actor_email,
      actor.full_name AS actor_full_name,
      actor.role::text AS actor_role,
      l.target_type,
      l.target_id,
      l.details
    FROM public.admin_audit_logs l
    LEFT JOIN public.users actor ON actor.user_id = l.actor_user_id
    WHERE (
        v_category IS NULL
        OR v_category = 'all'
        OR l.category = v_category
        OR (
          v_category = 'account_management'
          AND l.category IN ('account_management', 'authentication')
        )
      )
      AND (v_status IS NULL OR v_status = 'all' OR l.status = v_status)
      AND (p_actor_user_id IS NULL OR l.actor_user_id = p_actor_user_id)
      AND (
        v_actor_kind IS NULL
        OR (
          v_actor_kind = 'system'
          AND l.actor_user_id IS NULL
        )
        OR (
          v_actor_kind = 'super_admin'
          AND actor.role = 'super_admin'::public.user_role_enum
        )
        OR (
          v_actor_kind = 'administrator'
          AND actor.role = 'admin'::public.user_role_enum
        )
      )
      AND (p_from IS NULL OR l.created_at >= p_from)
      AND (p_to IS NULL OR l.created_at < p_to)
      AND (
        v_search IS NULL
        OR l.summary ILIKE ('%' || v_search || '%') ESCAPE chr(92)
        OR l.event_type ILIKE ('%' || v_search || '%') ESCAPE chr(92)
        OR COALESCE(l.actor_email, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
        OR COALESCE(actor.full_name, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
        OR COALESCE(l.target_id, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
        OR COALESCE(l.target_type, '') ILIKE ('%' || v_search || '%') ESCAPE chr(92)
      )
    ORDER BY l.created_at DESC
    LIMIT v_limit
    OFFSET v_offset
  ) x;

  RETURN jsonb_build_object(
    'rows', v_rows,
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset
  );
END;
$$;
