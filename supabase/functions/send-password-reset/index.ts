import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
import { clientIp } from "../_shared/phone_otp.ts";
import { THRIFTLINE_ANDROID_PACKAGE } from "../_shared/thriftline_android.ts";
import {
  turnstileUserMessage,
  verifyTurnstileToken,
} from "../_shared/turnstile.ts";

// HTTPS is required so Gmail keeps the button clickable. The function then
// Refresh-redirects to thriftline://reset-password. Do not use target=_blank.
function recoveryBounceUrl(): string {
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  if (!base) return "";
  return `${base}/functions/v1/password-recovery-return`;
}

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

/** Safe for double-quoted href attributes. */
function escapeHtmlAttr(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll('"', "&quot;");
}

const BRAND_PRIMARY = "#0D9488";
const BRAND_TEXT = "#0F172A";
const BRAND_MUTED = "#64748B";

function buildRecoveryEmailHtml(httpsUrl: string, openAppUrl: string): string {
  const httpsHref = escapeHtmlAttr(httpsUrl);
  const openHref = escapeHtmlAttr(openAppUrl);
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
            Tap the button on the phone where ThriftLine is installed. The app should open so you can choose a new password.
          </p>
          <table role="presentation" cellspacing="0" cellpadding="0" style="margin:0 0 16px;">
            <tr><td style="border-radius:8px;background:${BRAND_PRIMARY};">
              <a href="${httpsHref}"
                 style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:8px;">
                Choose a New Password
              </a>
            </td></tr>
          </table>
          <p style="margin:0 0 20px;font-size:13px;">
            <a href="${openHref}" style="color:${BRAND_PRIMARY};font-weight:600;">Open ThriftLine</a>
          </p>
          <p style="margin:0;font-size:13px;line-height:1.5;color:${BRAND_MUTED};">
            This password reset link expires soon and can only be used once.
            If you did not request a password reset, you can safely ignore this email.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function buildRecoveryEmailText(httpsUrl: string, openAppUrl: string): string {
  return (
    "You requested to reset your ThriftLine password.\n\n" +
    "On the phone where ThriftLine is installed, open this link:\n" +
    `${httpsUrl}\n\n` +
    "Or open ThriftLine directly:\n" +
    `${openAppUrl}\n\n` +
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

async function sendRecoveryEmail(
  to: string,
  httpsUrl: string,
  openAppUrl: string,
): Promise<void> {
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

  const text = buildRecoveryEmailText(httpsUrl, openAppUrl);
  const html = buildRecoveryEmailHtml(httpsUrl, openAppUrl);

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
  let turnstileToken = "";
  try {
    const body = await req.json();
    email = normalizeEmail(
      typeof body?.email === "string" ? body.email : "",
    );
    turnstileToken = typeof body?.turnstile_token === "string"
      ? body.turnstile_token
      : typeof body?.captcha_token === "string"
      ? body.captcha_token
      : "";
  } catch {
    return json(400, { error: "Enter a valid email address." });
  }

  if (!isEmail(email)) {
    return json(400, { error: "Enter a valid email address." });
  }

  if (!turnstileToken.trim()) {
    return json(400, {
      error: "Complete human verification before requesting a reset email.",
    });
  }

  const remoteIp = clientIp(req);
  const turnstile = await verifyTurnstileToken(turnstileToken, remoteIp, {
    expectedAction: "password_reset",
  });
  if (!turnstile.success) {
    return json(403, { error: turnstileUserMessage(turnstile["error-codes"]) });
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

  const bounceUrl = recoveryBounceUrl();
  if (!bounceUrl.startsWith("https://")) {
    console.error("send-password-reset bounce URL is not configured");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  const { data: linkData, error: linkError } = await service.auth.admin
    .generateLink({
      type: "recovery",
      email,
      options: { redirectTo: "thriftline://reset-password" },
    });

  const hashedToken = (linkData?.properties?.hashed_token ?? "").trim();
  const query = hashedToken
    ? new URLSearchParams({
      token_hash: hashedToken,
      type: "recovery",
    }).toString()
    : "";
  const recoveryUrl = query ? `${bounceUrl}?${query}` : "";
  const openAppUrl = query
    ? `intent://reset-password?${query}#Intent;scheme=thriftline;package=${THRIFTLINE_ANDROID_PACKAGE};end`
    : "";
  if (linkError || !recoveryUrl.startsWith("https://") || !openAppUrl) {
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
    await sendRecoveryEmail(email, recoveryUrl, openAppUrl);
  } catch {
    console.error("send-password-reset smtp failed");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  return json(200, { ok: true });
});
