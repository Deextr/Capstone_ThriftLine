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

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function sendRecoveryEmail(to: string, link: string): Promise<void> {
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

  const text =
    "You asked to reset your ThriftLine password.\n\n" +
    `Open this link on your phone:\n${link}\n\n` +
    "The link expires soon and can only be used once. " +
    "If you did not ask for this, you can ignore this email.";

  const safeLink = escapeHtml(link);
  const html =
    "<p>You asked to reset your ThriftLine password.</p>" +
    `<p><a href="${safeLink}">Choose a new password</a></p>` +
    "<p>The link expires soon and can only be used once. " +
    "If you did not ask for this, you can ignore this email.</p>";

  try {
    await client.send({
      from: `ThriftLine <${username}>`,
      to,
      subject: "Reset your ThriftLine password",
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
    });

  const hashedToken = linkData?.properties?.hashed_token ?? "";
  const appLink = hashedToken
    ? `${RECOVERY_REDIRECT}?token_hash=${encodeURIComponent(hashedToken)}&type=recovery`
    : "";
  if (linkError || !appLink) {
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
    await sendRecoveryEmail(email, appLink);
  } catch {
    console.error("send-password-reset smtp failed");
    return json(500, {
      error:
        "We could not send the reset email right now. Please try again in a moment.",
    });
  }

  return json(200, { ok: true });
});
