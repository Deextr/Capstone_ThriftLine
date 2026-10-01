import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Must match PasswordRecoveryLink.redirectUrl and the Auth redirect allow list.
const RECOVERY_REDIRECT = "thriftline://reset-password";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

function isEmail(value: string): boolean {
  if (value.length === 0 || value.length > 320) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function escapeHtmlText(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/** Safe for double-quoted href attributes on https recovery URLs. */
function escapeHtmlAttr(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;");
}

const BRAND_PRIMARY = "#0D9488";
const BRAND_TEXT = "#0F172A";
const BRAND_MUTED = "#64748B";

function buildRecoveryEmailHtml(recoveryUrl: string): string {
  const href = escapeHtmlAttr(recoveryUrl);
  const linkText = escapeHtmlText(recoveryUrl);
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F8FAFC;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F8FAFC;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:480px;background:#FFFFFF;border-radius:12px;border:1px solid #E2E8F0;">
        <tr><td style="padding:32px 28px;">
          <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:${BRAND_TEXT};">ThriftLine</p>
          <p style="margin:0 0 20px;font-size:16px;line-height:1.5;color:${BRAND_TEXT};">
            You requested to reset your ThriftLine password.
          </p>
          <p style="margin:0 0 24px;font-size:15px;line-height:1.5;color:${BRAND_MUTED};">
            Click the button below to create a new password. Open this email on the phone where ThriftLine is installed.
          </p>
          <table role="presentation" cellspacing="0" cellpadding="0" style="margin:0 0 28px;">
            <tr><td style="border-radius:8px;background:${BRAND_PRIMARY};">
              <a href="${href}" target="_blank" rel="noopener noreferrer"
                 style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:8px;">
                Choose a New Password
              </a>
            </td></tr>
          </table>
          <p style="margin:0 0 12px;font-size:13px;line-height:1.5;color:${BRAND_MUTED};">
            This password reset link will expire according to the configured recovery token validity period.
            If you did not request a password reset, you can safely ignore this email.
          </p>
          <p style="margin:0;font-size:12px;line-height:1.5;color:${BRAND_MUTED};">
            If the button does not work, copy and paste this link into your browser:<br/>
            <a href="${href}" style="color:${BRAND_PRIMARY};word-break:break-all;">${linkText}</a>
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildRecoveryEmailText(recoveryUrl: string): string {
  return (
    "You requested to reset your ThriftLine password.\n\n" +
    "Open this link on your phone to choose a new password:\n" +
    `${recoveryUrl}\n\n` +
    "This link expires soon and can only be used once. " +
    "If you did not request a password reset, you can safely ignore this email."
  );
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function sendRecoveryEmail(to: string, recoveryUrl: string): Promise<void> {
  const username = Deno.env.get("GMAIL_USER") ?? "";
  const password = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
  if (!username.trim() || !password.trim()) {
    throw new Error("gmail smtp is not configured");
  }

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username, password },
    },
  });

  const text = buildRecoveryEmailText(recoveryUrl);
  const html = buildRecoveryEmailHtml(recoveryUrl);

  try {
    await client.send({
      from: `ThriftLine <${username}>`,
      to,
      subject: "Reset Your ThriftLine Password",
      content: text,
      html,
    });
  } finally {
    await client.close();
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  let email = "";
  try {
    const body = await req.json();
    email = normalizeEmail(
      typeof body?.email === "string" ? body.email : "",
    );
  } catch {
    return json(400, { error: "Enter a valid email address." });
  }

  if (!isEmail(email)) {
    return json(400, { error: "Enter a valid email address." });
  }

  const service = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const pepper = Deno.env.get("OTP_PEPPER") ?? "password-reset";
  const emailHash = await sha256Hex(`${pepper}:${email}`);

  const { data: claim, error: claimError } = await service.rpc(
    "claim_password_reset_attempt",
    { p_email_hash: emailHash },
  );
  if (claimError) {
    console.error("send-password-reset rate limit unavailable");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }
  if (claim === "cooldown" || claim === "hourly") {
    return json(429, {
      error:
        "Too many reset emails requested. Please wait a moment and try again.",
    });
  }

  const { data: kind, error: kindError } = await service.rpc(
    "password_reset_account_kind",
    { p_email: email },
  );
  if (kindError) {
    console.error("send-password-reset eligibility unavailable");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  // Same response whether the address is missing or Google-only, so this
  // endpoint cannot be used to list accounts. A recovery link is only minted
  // for an email/password identity. That avoids attaching a password to a
  // Google-only account.
  if (kind !== "email") {
    console.log(`send-password-reset skipped kind=${kind ?? "unknown"}`);
    return json(200, { ok: true });
  }

  const { data: linkData, error: linkError } = await service.auth.admin
    .generateLink({
      type: "recovery",
      email,
      options: { redirectTo: RECOVERY_REDIRECT },
    });

  // Gmail and most clients strip non-http(s) href values. Use Supabase's HTTPS
  // verify URL; after verification Auth redirects to thriftline://reset-password.
  const recoveryUrl = linkData?.properties?.action_link ?? "";
  if (linkError || !recoveryUrl.startsWith("https://")) {
    const code = linkError && "code" in linkError
      ? String(linkError.code ?? "")
      : "";
    const status = linkError && "status" in linkError
      ? String(linkError.status ?? "")
      : "";
    console.error(
      `send-password-reset link failed status=${status} code=${code}`,
    );
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  try {
    await sendRecoveryEmail(email, recoveryUrl);
  } catch {
    console.error("send-password-reset smtp failed");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  return json(200, { ok: true });
});
