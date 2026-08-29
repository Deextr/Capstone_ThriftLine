-- Phase 0 / 3 of 4 — product category seed.
--
-- The audit found 8 categories already present: Accessories, Bags, Bottoms,
-- Dresses, Others, Outerwear, Shoes, Tops. The ProductCategory enum in
-- lib/models/enums.dart defines 10: the 7 shared ones plus Vintage, Streetwear
-- and Formal. This adds the 3 missing values.
--
-- All 11 rows are listed rather than only the 3 new ones so the migration also
-- works against an empty database.
--
-- Idempotency comes from the existing UNIQUE (category_name) constraint, so no
-- hardcoded UUIDs are needed and existing category_id values are preserved —
-- important because products.category_id already references them.
--
-- 'Others' is not in the Flutter enum but is kept: it is a legitimate catch-all
-- and removing it would strand any product assigned to it.

INSERT INTO public.categories (category_name, is_active)
VALUES
  ('Tops',        true),
  ('Bottoms',     true),
  ('Dresses',     true),
  ('Outerwear',   true),
  ('Shoes',       true),
  ('Bags',        true),
  ('Accessories', true),
  ('Vintage',     true),
  ('Streetwear',  true),
  ('Formal',      true),
  ('Others',      true)
ON CONFLICT (category_name) DO NOTHING;
