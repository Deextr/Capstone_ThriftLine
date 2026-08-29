-- ThriftLine — Phase 0 follow-up probe.
--
-- READ-ONLY. Answers the two questions the first audit left open:
--
--   1. What does the existing handle_new_auth_user() actually insert?
--      Needed before the client-side insert in auth_service.dart can be removed,
--      and before the users INSERT policy is dropped for good.
--
--   2. What is the single orphaned public.users row (a profile with no matching
--      auth.users account), and does anything reference it? This decides whether
--      the FOREIGN KEY to auth.users can be added, and whether the orphan can be
--      deleted or must be kept.
--
-- No email or phone_number is selected.

SELECT jsonb_pretty(jsonb_build_object(

  'handle_new_auth_user_source', (
    SELECT p.prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'handle_new_auth_user'
  ),

  'orphan_profiles', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'user_id',          u.user_id,
             'username',         u.username,
             'full_name',        u.full_name,
             'role',             u.role,
             'account_status',   u.account_status,
             'created_at',       u.created_at,
             'products_owned',   (SELECT count(*) FROM public.products p            WHERE p.seller_id = u.user_id),
             'addresses',        (SELECT count(*) FROM public.addresses a           WHERE a.user_id   = u.user_id),
             'orders_as_buyer',  (SELECT count(*) FROM public.orders o              WHERE o.buyer_id  = u.user_id),
             'orders_as_seller', (SELECT count(*) FROM public.orders o              WHERE o.seller_id = u.user_id),
             'saved_items',      (SELECT count(*) FROM public.saved_items s         WHERE s.user_id   = u.user_id),
             'verifications',    (SELECT count(*) FROM public.user_verifications v  WHERE v.user_id   = u.user_id),
             'bids',             (SELECT count(*) FROM public.bids b                WHERE b.bidder_id = u.user_id)
           )), '[]'::jsonb)
    FROM public.users u
    LEFT JOIN auth.users a ON a.id = u.user_id
    WHERE a.id IS NULL
  ),

  -- Confirms the seller backfill in migration 20260818020000 covered everyone
  -- who owns a listing.
  'product_owner_roles', (
    SELECT coalesce(jsonb_agg(DISTINCT jsonb_build_object(
             'seller_id', p.seller_id,
             'role',      u.role::text
           )), '[]'::jsonb)
    FROM public.products p
    JOIN public.users u ON u.user_id = p.seller_id
  )

)) AS phase0_followup;
