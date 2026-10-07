-- PostgreSQL requires new enum labels to be committed before use in the same
-- database session. Keep this migration separate from report_workflow_simplify.

ALTER TYPE public.report_status_enum ADD VALUE IF NOT EXISTS 'needs_more_evidence';
