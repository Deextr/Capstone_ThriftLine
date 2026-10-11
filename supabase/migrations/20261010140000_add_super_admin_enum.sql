-- Add the super_admin role value by itself.
-- Postgres cannot use a new enum value in the same transaction that adds it,
-- and each migration file runs in one transaction.

ALTER TYPE public.user_role_enum ADD VALUE IF NOT EXISTS 'super_admin';
