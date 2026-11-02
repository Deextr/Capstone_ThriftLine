-- ThriftLine — beta marketplace reset (paste into Supabase SQL Editor as postgres).
--
-- PURPOSE
--   Wipe marketplace activity and seller state so the app feels like a fresh
--   install while keeping auth logins and administrator accounts.
--
-- PRESERVES
--   * auth.users (all sign-in accounts)
--   * public.users rows (profiles updated, not deleted)
--   * roles: admin, super_admin (unchanged)
--   * public.categories (seed catalog)
--   * public.admin_profiles, public.admin_invitations
--   * storage bucket: app-links (static legal / policy assets)
--
-- REMOVES / RESETS
--   * Orders, payments, escrow, listings, auctions, chat, Looking For, reports,
--     reviews, notifications, carts, follows, addresses, sanctions, analytics
--   * seller_profiles and user_verifications for non-administrators
--   * Demotes role seller → buyer for non-administrators
--   * Resets trust scores and ratings to new-user defaults for marketplace users
--   * OTP / abuse / portal session / audit log rows (operational noise)
--   * Objects in marketplace storage buckets (verification docs, product images, …)
--     Uses storage.allow_delete_query (Supabase blocks bare DELETE on storage.objects).
--     If files still appear in Dashboard → Storage, empty those buckets there once.
--
-- PREREQUISITES
--   1. Take a backup or use a dedicated beta Supabase project.
--   2. Do not run against production unless you intend to erase live data.
--   3. All migrations through your current branch must already be applied.
--
-- IDEMPOTENT: Safe to re-run on an already-reset database (mostly no-op deletes).
--
-- After running, confirm super admin still appears in the final SELECT block.

SET statement_timeout = '10min';
SET lock_timeout = '2min';

BEGIN;

-- ---------------------------------------------------------------------------
-- Helpers (session-local)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pg_temp.thriftline_delete_all(p_table text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted bigint := 0;
BEGIN
  IF to_regclass(format('public.%I', p_table)) IS NULL THEN
    RETURN 0;
  END IF;

  EXECUTE format('DELETE FROM public.%I', p_table);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.thriftline_is_admin_user(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.user_id = p_user_id
      AND u.role IN (
        'admin'::public.user_role_enum,
        'super_admin'::public.user_role_enum
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 1. Looking For (reports and evidence before posts)
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('looking_for_report_evidence');
SELECT pg_temp.thriftline_delete_all('looking_for_evidence_submissions');
-- violations RESTRICT report_id and post_id — must run before reports and posts
SELECT pg_temp.thriftline_delete_all('looking_for_violations');
SELECT pg_temp.thriftline_delete_all('looking_for_reports');
SELECT pg_temp.thriftline_delete_all('looking_for_post_activity');
SELECT pg_temp.thriftline_delete_all('looking_for_responses');
SELECT pg_temp.thriftline_delete_all('looking_for_account_sanctions');
SELECT pg_temp.thriftline_delete_all('looking_for_posts');

-- ---------------------------------------------------------------------------
-- 2. Messaging
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('messages');
SELECT pg_temp.thriftline_delete_all('conversations');

-- ---------------------------------------------------------------------------
-- 3. Trust & safety / reviews
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('report_evidence');
SELECT pg_temp.thriftline_delete_all('report_evidence_submissions');
SELECT pg_temp.thriftline_delete_all('report_appeals');
SELECT pg_temp.thriftline_delete_all('reports');
SELECT pg_temp.thriftline_delete_all('review_photos');
SELECT pg_temp.thriftline_delete_all('reviews');

-- ---------------------------------------------------------------------------
-- 4. Escrow / refunds (before payments and orders)
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('escrow_refund_attempts');
SELECT pg_temp.thriftline_delete_all('escrow_refund_details');
SELECT pg_temp.thriftline_delete_all('escrow');

-- ---------------------------------------------------------------------------
-- 5. Orders and checkout (dependency-safe order)
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('seller_payouts');
SELECT pg_temp.thriftline_delete_all('return_shipments');
SELECT pg_temp.thriftline_delete_all('auction_bidding_violations');
SELECT pg_temp.thriftline_delete_all('auction_bidding_sanctions');
SELECT pg_temp.thriftline_delete_all('auction_bid_risk_events');
SELECT pg_temp.thriftline_delete_all('fulfillment_sla_events');
SELECT pg_temp.thriftline_delete_all('delivery_pin_secrets');
SELECT pg_temp.thriftline_delete_all('delivery_events');
SELECT pg_temp.thriftline_delete_all('delivery_disputes');
SELECT pg_temp.thriftline_delete_all('shipments');
SELECT pg_temp.thriftline_delete_all('shipping');
SELECT pg_temp.thriftline_delete_all('payments');
SELECT pg_temp.thriftline_delete_all('order_items');
SELECT pg_temp.thriftline_delete_all('orders');
SELECT pg_temp.thriftline_delete_all('checkout_groups');
SELECT pg_temp.thriftline_delete_all('paymongo_webhook_events');

-- ---------------------------------------------------------------------------
-- 6. Push + in-app notifications
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('push_notification_deliveries');
SELECT pg_temp.thriftline_delete_all('push_device_tokens');
SELECT pg_temp.thriftline_delete_all('notifications');

-- ---------------------------------------------------------------------------
-- 7. External selling history (trust inputs)
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('external_transaction_evidence');
SELECT pg_temp.thriftline_delete_all('external_transactions');

-- ---------------------------------------------------------------------------
-- 8. Catalog, auctions, live
-- ---------------------------------------------------------------------------

UPDATE public.auctions
SET winning_bid_id = NULL
WHERE winning_bid_id IS NOT NULL;

SELECT pg_temp.thriftline_delete_all('bids');
SELECT pg_temp.thriftline_delete_all('live_sessions');
SELECT pg_temp.thriftline_delete_all('cart_items');
SELECT pg_temp.thriftline_delete_all('saved_items');
SELECT pg_temp.thriftline_delete_all('product_images');
SELECT pg_temp.thriftline_delete_all('products');
SELECT pg_temp.thriftline_delete_all('auctions');

-- ---------------------------------------------------------------------------
-- 9. Social / buyer prefs / seller ops / analytics
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('follows');
SELECT pg_temp.thriftline_delete_all('addresses');
SELECT pg_temp.thriftline_delete_all('seller_saved_riders');
SELECT pg_temp.thriftline_delete_all('seller_payout_methods');
SELECT pg_temp.thriftline_delete_all('product_search_user_daily');
SELECT pg_temp.thriftline_delete_all('product_search_daily_stats');
SELECT pg_temp.thriftline_delete_all('user_install_signals');

-- ---------------------------------------------------------------------------
-- 10. Seller identity (non-administrators only)
-- ---------------------------------------------------------------------------

DELETE FROM public.seller_profiles sp
WHERE NOT pg_temp.thriftline_is_admin_user(sp.seller_id);

DELETE FROM public.user_verifications uv
WHERE NOT pg_temp.thriftline_is_admin_user(uv.user_id);

-- ---------------------------------------------------------------------------
-- 11. Demote sellers and reset marketplace profile metrics
--     (auth.uid() IS NULL in SQL Editor → column guard allows role writes)
-- ---------------------------------------------------------------------------

SELECT set_config('thriftline.maintain_trust', '1', true);
SELECT set_config('thriftline.maintain_ratings', '1', true);

UPDATE public.users u
SET
  role = CASE
    WHEN u.role = 'seller'::public.user_role_enum
      THEN 'buyer'::public.user_role_enum
    ELSE u.role
  END,
  trust_score = 80,
  trust_level = public.trust_level_for(80),
  trust_breakdown = NULL,
  trust_updated_at = now(),
  rating_average = NULL,
  rating_count = 0
WHERE u.role NOT IN (
  'admin'::public.user_role_enum,
  'super_admin'::public.user_role_enum
);

SELECT set_config('thriftline.maintain_trust', '0', true);
SELECT set_config('thriftline.maintain_ratings', '0', true);

-- ---------------------------------------------------------------------------
-- 12. Operational / session tables (keeps auth accounts; clears noise)
-- ---------------------------------------------------------------------------

SELECT pg_temp.thriftline_delete_all('email_otp_challenges');
SELECT pg_temp.thriftline_delete_all('phone_otp_challenges');
SELECT pg_temp.thriftline_delete_all('email_login_session_gates');
SELECT pg_temp.thriftline_delete_all('email_login_abuse');
SELECT pg_temp.thriftline_delete_all('password_reset_attempts');
SELECT pg_temp.thriftline_delete_all('trusted_devices');
SELECT pg_temp.thriftline_delete_all('unisms_test_sms_usage');
SELECT pg_temp.thriftline_delete_all('admin_portal_sessions');
SELECT pg_temp.thriftline_delete_all('admin_portal_login_lockout');
SELECT pg_temp.thriftline_delete_all('admin_audit_logs');

-- ---------------------------------------------------------------------------
-- 13. Storage — marketplace uploads (NOT app-links)
-- ---------------------------------------------------------------------------

SELECT set_config('storage.allow_delete_query', 'true', true);

DELETE FROM storage.objects
WHERE bucket_id IN (
  'verification-docs',
  'product-images',
  'looking-for',
  'message-attachments',
  'report-evidence',
  'review-photos',
  'financial-evidence'
);

COMMIT;

-- ---------------------------------------------------------------------------
-- Verification (read-only)
-- ---------------------------------------------------------------------------

SELECT 'users_by_role' AS check_name, u.role::text AS value, count(*) AS n
FROM public.users u
GROUP BY u.role
ORDER BY u.role;

SELECT 'super_admin_accounts' AS check_name, u.email, u.role::text, u.account_status::text
FROM public.users u
WHERE u.role = 'super_admin'::public.user_role_enum
ORDER BY u.email;

SELECT 'marketplace_row_counts' AS check_name, t.table_name, t.n
FROM (
  SELECT 'products' AS table_name, count(*)::bigint AS n FROM public.products
  UNION ALL SELECT 'orders', count(*) FROM public.orders
  UNION ALL SELECT 'seller_profiles', count(*) FROM public.seller_profiles
  UNION ALL SELECT 'user_verifications', count(*) FROM public.user_verifications
  UNION ALL SELECT 'notifications', count(*) FROM public.notifications
  UNION ALL SELECT 'conversations', count(*) FROM public.conversations
) t
ORDER BY t.table_name;

SELECT 'storage_objects' AS check_name, o.bucket_id, count(*) AS n
FROM storage.objects o
WHERE o.bucket_id IN (
  'verification-docs',
  'product-images',
  'looking-for',
  'message-attachments',
  'report-evidence',
  'review-photos',
  'financial-evidence'
)
GROUP BY o.bucket_id
ORDER BY o.bucket_id;
