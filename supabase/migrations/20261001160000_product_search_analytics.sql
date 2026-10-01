-- Aggregated product search analytics (no per-user exposure in reads).

CREATE TABLE IF NOT EXISTS public.product_search_daily_stats (
  normalized_term text NOT NULL,
  search_date date NOT NULL DEFAULT (timezone('utc', now()))::date,
  hit_count integer NOT NULL DEFAULT 0 CHECK (hit_count >= 0),
  PRIMARY KEY (normalized_term, search_date)
);

CREATE TABLE IF NOT EXISTS public.product_search_user_daily (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  normalized_term text NOT NULL,
  search_date date NOT NULL DEFAULT (timezone('utc', now()))::date,
  PRIMARY KEY (user_id, normalized_term, search_date)
);

CREATE INDEX IF NOT EXISTS idx_product_search_daily_stats_date
  ON public.product_search_daily_stats (search_date DESC);

ALTER TABLE public.product_search_daily_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_search_user_daily ENABLE ROW LEVEL SECURITY;

-- No direct client access; RPCs below run as SECURITY DEFINER.

CREATE OR REPLACE FUNCTION public.normalize_product_search_term(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT NULLIF(
    lower(
      trim(
        regexp_replace(
          coalesce(p_raw, ''),
          '\s+',
          ' ',
          'g'
        )
      )
    ),
    ''
  );
$$;

CREATE OR REPLACE FUNCTION public.record_product_search(p_term text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_term text := public.normalize_product_search_term(p_term);
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  IF v_term IS NULL OR char_length(v_term) < 2 OR char_length(v_term) > 80 THEN
    RETURN;
  END IF;

  -- Basic noise / abuse guard.
  IF v_term ~ '^[^a-z0-9]+$' THEN
    RETURN;
  END IF;

  INSERT INTO public.product_search_user_daily (user_id, normalized_term, search_date)
  VALUES (v_uid, v_term, (timezone('utc', now()))::date)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN;
  END IF;

  -- Only count the first submitted search per buyer/term/day.
  INSERT INTO public.product_search_daily_stats (normalized_term, search_date, hit_count)
  VALUES (v_term, (timezone('utc', now()))::date, 1)
  ON CONFLICT (normalized_term, search_date)
  DO UPDATE SET hit_count = public.product_search_daily_stats.hit_count + 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_popular_product_searches(
  p_limit integer DEFAULT 8,
  p_days integer DEFAULT 14,
  p_min_total_hits integer DEFAULT 3
)
RETURNS TABLE (term text, total_hits bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    s.normalized_term AS term,
    sum(s.hit_count)::bigint AS total_hits
  FROM public.product_search_daily_stats s
  WHERE s.search_date >= ((timezone('utc', now()))::date - make_interval(days => greatest(p_days, 1)))
  GROUP BY s.normalized_term
  HAVING sum(s.hit_count) >= greatest(p_min_total_hits, 1)
  ORDER BY total_hits DESC, s.normalized_term ASC
  LIMIT greatest(p_limit, 1);
$$;

REVOKE ALL ON FUNCTION public.record_product_search(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_search(text) TO authenticated;

REVOKE ALL ON FUNCTION public.get_popular_product_searches(integer, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_popular_product_searches(integer, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_popular_product_searches(integer, integer, integer) TO anon;
