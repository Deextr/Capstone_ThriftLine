# Email OTP — start-to-end setup

Do these steps **in order**. The Flutter screens are already in the app. Email OTP will not send until the database table, Edge Functions, and Gmail secrets are in place.

Google Sign-In does **not** use this step. Keep Supabase Auth **Confirm email** off the whole time.

---

## What you need before you start

- Access to your ThriftLine **Supabase** project (Dashboard).
- The Gmail account that will **send** the codes (can be `dexter041711@gmail.com`).
- That Gmail account must have **2-Step Verification** turned on (required for App Passwords).
- The Flutter app already pointing at this Supabase project (`.env` has `SUPABASE_URL` and `SUPABASE_ANON_KEY`).
- Optional: [Supabase CLI](https://supabase.com/docs/guides/cli) logged in. If you do not have it, use the Dashboard path in Step 5.

Do **not** put the Gmail App Password or `OTP_PEPPER` in Flutter `.env`. Those belong only in Supabase Edge Function secrets.

---

## Step 1 — Create a Gmail App Password

Regular Gmail login passwords are rejected by SMTP. You need an App Password.

1. Open the sender Gmail account in a browser.
2. Turn on [2-Step Verification](https://myaccount.google.com/signinoptions/two-step-verification) if it is not already on.
3. Open [App Passwords](https://myaccount.google.com/apppasswords).
4. Create an app password. Name it something like `ThriftLine OTP`.
5. Google shows a **16-character** password (spaces are fine; you can paste it with or without spaces).
6. Copy it somewhere private. You will paste it into Supabase in Step 6. You cannot view it again later.

If App Passwords is missing, 2-Step Verification is not fully on, or the account is a Workspace account that blocks App Passwords.

---

## Step 2 — Keep Confirm email off in Supabase

Signup must return a session immediately so the app can call `send-email-otp`.

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your ThriftLine project.
2. Go to **Authentication → Providers → Email**.
3. Confirm **Confirm email** is **disabled**.
4. Save if you changed anything.

Also apply `supabase/migrations/20260907010000_allow_google_identity_on_email_user.sql` in the SQL Editor (or `20260905020000` if you have not run either). That trigger only blocks attaching an **email/password** identity onto an existing Google user. Google sign-in onto an existing email account is allowed so you can still log in.

---

## Step 3 — Create the OTP table

1. In Supabase, open **SQL Editor**.
2. Click **New query**.
3. Open this file in the repo:

   `supabase/migrations/20260905010000_email_otp_challenges.sql`

4. Copy the entire file into the editor and click **Run**.
5. You should see success (no error). This creates `public.email_otp_challenges` with no client access.

If you already ran this file once, running it again is safe.

---

## Step 4 — Create the admin user, then promote it

Do **not** sign up in the ThriftLine app yet. Email OTP is not sending until Steps 5 and 6 are done, so an in-app signup would stop on the code screen with no email.

Create the account in Supabase Studio first, then run the seed.

### 4a — Create the auth user in Studio

1. In Supabase go to **Authentication → Users**.
2. Click **Add user → Create new user**.
3. Email: `dexter041711@gmail.com`
4. Password: the password you want for the ThriftLine app (the one you already chose).
5. Tick **Auto Confirm User** so you do not need a confirmation link.
6. Save.

That insert also creates a `public.users` row with role `buyer`. The next script only changes the role.

### 4b — Promote that user to admin

1. In **SQL Editor**, open a new query.
2. Copy the entire file:

   `supabase/seed/001_role_assignments.sql`

3. Click **Run**.
4. In the results, look for `PROMOTED` or `UNCHANGED` for `dexter041711@gmail.com`.
5. Run this check:

```sql
SELECT username, full_name, role, account_status
FROM public.users
WHERE lower(email) = 'dexter041711@gmail.com';
```

`role` must be `admin`. If the seed said `SKIPPED`, Step 4a did not create the user in this project — add the user again, then rerun the seed.

The seed does **not** store your password. Set or change the password only in Studio.

---

## Step 5 — Deploy the two Edge Functions

You need both:

- `send-email-otp` — creates the hashed code and emails it
- `verify-email-otp` — checks the code the user typed

### Option A — Supabase CLI (preferred)

In a terminal, from the repo root (`Capstone_ThriftLine`):

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy send-email-otp
supabase functions deploy verify-email-otp
```

`YOUR_PROJECT_REF` is the short id in the project URL:

`https://supabase.com/dashboard/project/YOUR_PROJECT_REF`

### Option B — Dashboard (no CLI)

1. Go to **Edge Functions**.
2. Create a function named exactly `send-email-otp`.
3. Paste the contents of `supabase/functions/send-email-otp/index.ts` and deploy.
4. Create a function named exactly `verify-email-otp`.
5. Paste the contents of `supabase/functions/verify-email-otp/index.ts` and deploy.

The Flutter app calls those exact names. Do not rename them.

---

## Step 6 — Set Edge Function secrets

1. In Supabase go to **Edge Functions → Secrets**  
   (or **Project Settings → Edge Functions**).
2. Add these three secrets:

| Name | What to paste |
| --- | --- |
| `GMAIL_USER` | The full sender Gmail address, e.g. `dexter041711@gmail.com` |
| `GMAIL_APP_PASSWORD` | The 16-character App Password from Step 1 |
| `OTP_PEPPER` | A long random string you invent. If phone OTP already uses `OTP_PEPPER`, reuse that same value. |

3. Save.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are already injected into Edge Functions. Do not copy the service role key into the Flutter app.

If you used the CLI instead:

```bash
supabase secrets set GMAIL_USER="dexter041711@gmail.com"
supabase secrets set GMAIL_APP_PASSWORD="your-16-char-app-password"
supabase secrets set OTP_PEPPER="a-long-random-string-you-invent"
```

After changing secrets, redeploy both functions (Step 5) so they pick up the new values.

---

## Step 7 — Confirm nothing landed in Flutter `.env`

`.env` should only have:

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
GOOGLE_WEB_CLIENT_ID=...
```

If you added Gmail or pepper values here, remove them.

---

## Step 8 — Run the app and test

1. Restart the Flutter app so it uses a fresh session.
2. **Sign up** with a real email you can open (or log in with an existing email/password account).
3. After password success you should land on **Check your email**, not buyer/seller/admin home.
4. Open the inbox of **that user** (not only the sender Gmail). The subject is `Your ThriftLine verification code`.
5. Type a wrong 6-digit code → it should fail.
6. Type the real code → buyer home (or `/admin` if you used `dexter041711@gmail.com`).
7. Log out, log in with email/password again → a **new** code is required.
8. On the OTP screen, kill the app and reopen it → you should return to the OTP screen, not home.
9. **Continue with Google** should still skip OTP and go home.

Codes expire in **5 minutes**. Resend is limited to **once per 60 seconds**. Five wrong attempts lock that code; tap **Resend code**.

---

## If something fails

| What you see | Likely cause | What to do |
| --- | --- | --- |
| OTP screen appears but no email | Functions not deployed, or secrets missing | Repeat Steps 5 and 6. Open **Edge Functions → send-email-otp → Logs**. |
| `We could not send the email. Check Gmail SMTP setup` | Wrong App Password, 2-Step off, or `GMAIL_USER` mismatch | Recreate the App Password. `GMAIL_USER` must be the same mailbox that owns the App Password. Redeploy after updating secrets. |
| `Please wait Xs before requesting another code` | 60-second cooldown | Wait, then tap Resend. |
| `That code has expired` | Older than 5 minutes | Tap Resend and use the new code. |
| `That code is invalid` | Typo or old code | Use the latest email only. |
| `Sign in first` | No session (Confirm email still on) | Repeat Step 2, then sign up / log in again. |
| Seed result `SKIPPED` | Admin auth user is not in this project | Add the user in Studio, then rerun Step 4. |
| After login you skip OTP and go home | Old session from before this feature | Log out once, then log in with email/password again. |
| Email is in Spam | Gmail sending to another Gmail inbox | Check Spam. Mark as Not spam. |

---

## What the app does after this is set up

1. User signs up or logs in with email and password.
2. Supabase creates a session.
3. The app marks that session as pending and calls `send-email-otp`.
4. The function stores a hashed 6-digit code and sends it through Gmail SMTP (`smtp.gmail.com`, port 465).
5. The user types the code. `verify-email-otp` checks it.
6. Pending is cleared and the app opens the role home (buyer, seller, or admin).

The Flutter client never sees the Gmail App Password or the OTP hash.
