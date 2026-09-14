-- Phase 6 slice 1 — add payment_method_enum value `paymongo`.
-- Run this file BY ITSELF and wait for success before 20260911040100.
-- Postgres cannot use a newly added enum label in the same transaction.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'payment_method_enum'
      AND e.enumlabel = 'paymongo'
  ) THEN
    ALTER TYPE public.payment_method_enum ADD VALUE 'paymongo';
  END IF;
END $$;
