-- Fix review ratings synchronization and column guard
-- Ensures ratings submitted by buyers authoritatively update users.rating_average and users.rating_count
-- without being reverted by trg_users_column_guard.

CREATE OR REPLACE FUNCTION public.enforce_users_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('thriftline.maintain_trust', true) IS DISTINCT FROM '1' THEN
    NEW.trust_score      := OLD.trust_score;
    NEW.trust_level      := OLD.trust_level;
    NEW.trust_breakdown  := OLD.trust_breakdown;
    NEW.trust_updated_at := OLD.trust_updated_at;
  END IF;

  IF auth.uid() IS NULL
     OR auth.role() = 'service_role'
     OR public.is_admin()
  THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable' USING ERRCODE = '42501';
  END IF;

  NEW.role              := OLD.role;
  NEW.account_status    := OLD.account_status;
  NEW.created_at        := OLD.created_at;
  NEW.is_phone_verified := OLD.is_phone_verified;

  IF current_setting('thriftline.maintain_ratings', true) IS DISTINCT FROM '1' THEN
    NEW.rating_average := OLD.rating_average;
    NEW.rating_count   := OLD.rating_count;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_users_column_guard() IS
  'Ordinary clients cannot write role, account_status, phone verification, or ratings. rating_average and rating_count change only when thriftline.maintain_ratings=1.';

CREATE OR REPLACE FUNCTION public.refresh_user_rating(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
  v_avg numeric;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('thriftline.maintain_ratings', '1', true);

  SELECT count(*), round(avg(rating)::numeric, 2)
    INTO v_count, v_avg
  FROM public.reviews
  WHERE reviewed_user_id = p_user_id;

  UPDATE public.users
  SET rating_count   = COALESCE(v_count, 0),
      rating_average = CASE WHEN COALESCE(v_count, 0) = 0 THEN 0 ELSE v_avg END,
      updated_at     = now()
  WHERE user_id = p_user_id;

  PERFORM set_config('thriftline.maintain_ratings', '0', true);
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_user_rating(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_user_rating(uuid) TO postgres, service_role;

-- Ensure triggers on reviews
DROP TRIGGER IF EXISTS trg_reviews_rating_aggregate ON public.reviews;
CREATE TRIGGER trg_reviews_rating_aggregate
AFTER INSERT OR UPDATE OR DELETE ON public.reviews
FOR EACH ROW
EXECUTE FUNCTION public.handle_review_change();

-- Add reviews to realtime publication for responsive buyer and seller updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
  END IF;
END;
$$;

-- Recalculate existing ratings for all reviewed users to guarantee consistency
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT DISTINCT reviewed_user_id FROM public.reviews LOOP
    PERFORM public.refresh_user_rating(r.reviewed_user_id);
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'recalculate_seller_trust') THEN
      PERFORM public.recalculate_seller_trust(r.reviewed_user_id);
    END IF;
  END LOOP;
END;
$$;
