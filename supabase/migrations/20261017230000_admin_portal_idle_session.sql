-- Server-enforced Admin Web Portal idle session (10 minutes).
-- Extends is_admin() so a portal session row requires recent activity or a fresh login.
-- Access tokens remain valid until JWT expiry; RLS/RPC checks reject idle portal sessions.

CREATE TABLE IF NOT EXISTS public.admin_portal_sessions (
  user_id uuid PRIMARY KEY REFERENCES public.users (user_id) ON DELETE CASCADE,
  session_version bigint NOT NULL DEFAULT 1,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_portal_sessions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.admin_portal_sessions FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.admin_portal_sessions IS
  'Tracks Admin Web Portal idle timeout. When present, is_admin() requires a non-revoked row within the inactivity window.';

CREATE OR REPLACE FUNCTION public._admin_portal_inactivity_interval()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT interval '10 minutes';
$$;

REVOKE ALL ON FUNCTION public._admin_portal_inactivity_interval() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_portal_inactivity_interval() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._is_active_admin_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = auth.uid()
      AND u.role IN (
        'admin'::public.user_role_enum,
        'super_admin'::public.user_role_enum
      )
      AND u.account_status = 'active'::public.account_status_enum
  );
$$;

REVOKE ALL ON FUNCTION public._is_active_admin_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._is_active_admin_user() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._admin_portal_session_is_live(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_portal_sessions s
    WHERE s.user_id = p_user_id
      AND s.revoked_at IS NULL
      AND s.last_activity_at > now() - public._admin_portal_inactivity_interval()
  );
$$;

REVOKE ALL ON FUNCTION public._admin_portal_session_is_live(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._admin_portal_session_is_live(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public._is_active_admin_user()
    AND (
      NOT EXISTS (
        SELECT 1
        FROM public.admin_portal_sessions s
        WHERE s.user_id = auth.uid()
      )
      OR public._admin_portal_session_is_live(auth.uid())
    );
$$;

COMMENT ON FUNCTION public.is_admin() IS
  'Active admin/super_admin. When an admin_portal_sessions row exists, the portal idle window must be satisfied.';

CREATE OR REPLACE FUNCTION public.admin_portal_session_begin()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT public._is_active_admin_user() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  INSERT INTO public.admin_portal_sessions AS s (
    user_id,
    session_version,
    last_activity_at,
    revoked_at,
    updated_at
  )
  VALUES (v_user, 1, now(), NULL, now())
  ON CONFLICT (user_id) DO UPDATE
  SET session_version = s.session_version + 1,
      last_activity_at = now(),
      revoked_at = NULL,
      updated_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_portal_session_touch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row_count integer := 0;
BEGIN
  IF v_user IS NULL OR NOT public._is_active_admin_user() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  UPDATE public.admin_portal_sessions s
  SET last_activity_at = now(),
      updated_at = now()
  WHERE s.user_id = v_user
    AND s.revoked_at IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;

  IF v_row_count = 0 THEN

    RETURN jsonb_build_object('success', false, 'error', 'portal_session_inactive');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_portal_session_revoke(p_reason text DEFAULT 'manual')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_reason text := NULLIF(btrim(coalesce(p_reason, '')), '');
BEGIN
  IF v_user IS NULL OR NOT public._is_active_admin_user() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  UPDATE public.admin_portal_sessions s
  SET revoked_at = now(),
      updated_at = now()
  WHERE s.user_id = v_user
    AND s.revoked_at IS NULL;

  PERFORM public.revoke_marketplace_sessions(v_user);

  IF v_reason IS NOT NULL AND v_reason IN ('idle', 'manual', 'sign_out') THEN
    PERFORM public.write_admin_audit_log(
      'system_security',
      'admin_portal_session_revoked',
      'success',
      'Admin portal session ended on the server.',
      v_user,
      'administrator',
      v_user::text,
      jsonb_build_object('reason', v_reason)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_portal_session_begin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_portal_session_touch() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_portal_session_revoke(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_portal_session_begin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_portal_session_touch() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_portal_session_revoke(text) TO authenticated;

-- Financial evidence: allow admins to delete orphan uploads (compensation after failed DB save).
DROP POLICY IF EXISTS financial_evidence_delete_admin ON storage.objects;
CREATE POLICY financial_evidence_delete_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'financial-evidence'
    AND public.is_admin()
    AND split_part(name, '/', 1) IN ('payouts', 'refunds')
  );

CREATE OR REPLACE FUNCTION public.financial_evidence_path_is_referenced(p_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.seller_payouts sp
    WHERE sp.evidence_path = p_path
  )
  OR EXISTS (
    SELECT 1
    FROM public.escrow_refund_details erd
    WHERE erd.manual_evidence_path = p_path
  );
$$;

REVOKE ALL ON FUNCTION public.financial_evidence_path_is_referenced(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.financial_evidence_path_is_referenced(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.financial_evidence_path_is_referenced(text) IS
  'True when a financial-evidence object path is stored on a payout or manual refund record.';
