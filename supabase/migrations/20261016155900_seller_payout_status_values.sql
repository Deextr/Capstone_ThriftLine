-- Phase A seller payouts: add outcome statuses to seller_payout_status_enum.
-- Run this file by itself and wait for success before the next migration.
-- New enum values cannot be used in the same transaction that adds them.

ALTER TYPE public.seller_payout_status_enum ADD VALUE IF NOT EXISTS 'paid';
ALTER TYPE public.seller_payout_status_enum ADD VALUE IF NOT EXISTS 'rejected';
ALTER TYPE public.seller_payout_status_enum ADD VALUE IF NOT EXISTS 'cancelled';
