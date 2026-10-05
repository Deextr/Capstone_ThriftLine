# UniSMS phone OTP — manual test checklist

Do not paste API keys, OTP codes, or full phone numbers into shared logs.

## Prerequisites

1. Set hosted secrets: `OTP_PEPPER`, `UNISMS_API_SECRET_KEY`, `UNISMS_SENDER_ID`, `SMS_PROVIDER=unisms`.
2. Deploy Edge Functions:

```bash
supabase functions deploy send-phone-otp
supabase functions deploy verify-phone-otp
supabase functions deploy test-unisms-sms
```

## Phase A — Connectivity (`test-unisms-sms`)

Sign in as an **admin** user in the app or obtain a user JWT, then:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/test-unisms-sms" \
  -H "Authorization: Bearer $USER_JWT" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"phone":"09XXXXXXXXX","content":"ThriftLine UniSMS connectivity test."}'
```

Record: HTTP status, `reference_id`, `delivery_status`, `code`, SMS received (Y/N).

## Phase B — Network matrix

| Network | HTTP | reference_id | delivery_status | fail_reason | SMS received | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Globe | | | | | | |
| TM | | | | | | |
| DITO | | | | | | |
| Smart | | | | | | |
| TNT | | | | | | |

Classify Smart/TNT failures from **API response**, not number prefix.

## Phase C — Full OTP flow

- [ ] Send OTP → receive SMS → verify → `users.is_phone_verified = true`
- [ ] Wrong OTP → user message; attempts increment
- [ ] Expired OTP → request new code
- [ ] Resend → old code invalid
- [ ] Reuse consumed OTP → rejected
- [ ] Too many wrong attempts → locked
- [ ] Resend cooldown / hourly send limits (backend enforced)
- [ ] Invalid `09` input
- [ ] Provider failure (temporarily invalid secret) → generic message, no raw JSON
- [ ] App restart mid-verify → state recovers

## Phase D — WSM / IV

After successful verify:

- [ ] `users.is_phone_verified` is true for the account
- [ ] Seller trust recalculates (trigger on `is_phone_verified`; IV phone uses `is_phone_verified` OR `user_verifications.phone_verified`)

## Phase E — Auth regression (smoke)

- [ ] Email OTP signup/login
- [ ] Email/password login
- [ ] Google Sign-In
- [ ] Forgot password
- [ ] Trusted device
- [ ] Become a Seller / verification flows unchanged
