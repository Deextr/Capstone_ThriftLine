-- Align Looking For request title length with client validation (5–100 chars).

CREATE OR REPLACE FUNCTION public._looking_for_validate_content(
  p_title text,
  p_description text,
  p_budget_min numeric,
  p_budget_max numeric,
  p_size text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_title text := btrim(COALESCE(p_title, ''));
  v_description text := btrim(COALESCE(p_description, ''));
BEGIN
  IF char_length(v_title) < 5 THEN
    RETURN 'Title must be at least 5 characters';
  END IF;
  IF char_length(v_title) > 100 THEN
    RETURN 'Title cannot exceed 100 characters';
  END IF;
  IF char_length(v_description) > 2000 THEN
    RETURN 'Keep the description under 2,000 characters.';
  END IF;
  IF p_budget_min < 0 OR p_budget_max < 0 THEN
    RETURN 'Enter a budget of zero or more.';
  END IF;
  IF p_budget_max < p_budget_min THEN
    RETURN 'The maximum budget must be at least the minimum.';
  END IF;
  IF p_budget_max > 10000000 THEN
    RETURN 'Enter a smaller budget.';
  END IF;
  IF p_size IS NOT NULL AND char_length(btrim(p_size)) > 40 THEN
    RETURN 'Keep the size under 40 characters.';
  END IF;
  RETURN NULL;
END;
$$;
