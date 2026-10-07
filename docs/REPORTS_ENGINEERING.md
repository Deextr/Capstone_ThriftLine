# ThriftLine Reports & Disputes — Engineering Summary

## Report categories

1. **Looking For Reports** — `looking_for_reports`; LF post content moderation.
2. **Community Reports** — `reports` without order link; seller/listing conduct.
3. **Order Reports** — `reports` with `order_id` / order categories; `delivery_disputes` remains internal for escrow when inspection disputes apply.

## Status workflow

`under_review` → (`needs_more_evidence` ↔ resubmit) → `resolved` | `dismissed`

Max **3** evidence submission attempts per case (`evidence_attempt_count`), enforced in RPCs.

## Key migration

[`supabase/migrations/20261007140000_report_workflow_simplify.sql`](../supabase/migrations/20261007140000_report_workflow_simplify.sql)

## RPCs

- `submit_community_report`, `submit_order_report`, `submit_report` (wrapper)
- `attach_report_evidence`, `resubmit_report_evidence`
- `decide_report(p_report_id, p_decision, p_admin_response, p_violation_confirmed)`
- `review_looking_for_report` (same decision model; violation flag on resolve)

## Admin UI

Web: `/admin/reports/community`, `/admin/reports/orders`, `/admin/reports/looking-for` (single module, three categories).

## Security

- Attempt count and status changes are server-authoritative.
- `abandon_open_report` disabled post-submit.
- Reporter-only evidence; admin via `is_admin()`.
