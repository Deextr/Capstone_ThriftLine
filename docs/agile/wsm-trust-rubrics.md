# WSM trust rubrics (IMRAD alignment)

This note supplements [Capstone 2 - IMRAD.docx](Capstone%202%20-%20IMRAD.docx) **Tables 12–17** and matches the Postgres functions in `20260930190000_seller_trust_wsm.sql` and `20261005120000_seller_trust_iv_inputs.sql`.

## Formula (Section 2.3.2 / Figure 5)

```text
TS = 0.40×IV + 0.30×ST + 0.20×UR + 0.10×CR
```

Each criterion is scored 0–100 before weighting.

## Table 14 — User Ratings (UR) footnote

IMRAD Table 14 lists bands only when the seller has buyer ratings. The implementation uses a **neutral default** when there are no verified ratings yet:

| Condition | UR score |
|-----------|----------|
| `rating_count = 0` or `rating_average` is null | **60** (neutral; not a penalty) |

This keeps a newly approved seller with full identity verification, zero completed orders, and zero confirmed reports at **TS = 62** → **New Seller** (Table 17), together with **CR = 100** for zero admin-confirmed reports (Table 15).

## Table 12 — Identity Verification (IV) in code

- **Government ID (+25):** latest seller verification `verification_status = approved`.
- **Email (+25):** `user_verifications.email_verified` **or** confirmed auth email (`trust_seller_email_verified`).
- **Phone (+25):** `users.is_phone_verified` **or** `user_verifications.phone_verified`.
- **Face (+25):** approved verification and `liveness_passed`.

On admin approval, `apply_verification_decision` writes `email_verified` and `phone_verified` on the verification row from auth/users state.

## Table 17 — “Under Review” (40–59)

This band is a **trust score label**, not seller application status (`verification_status = pending`). Application review copy lives on the Become a Seller flow only.
