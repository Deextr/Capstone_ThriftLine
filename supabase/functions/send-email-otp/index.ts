import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

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

function randomOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function sendGmail(to: string, otp: string): Promise<void> {
  const username = Deno.env.get("GMAIL_USER") ?? "";
  const password = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
  if (!username.trim() || !password.trim()) {
    throw new Error("GMAIL_USER or GMAIL_APP_PASSWORD is not configured");
  }

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username, password },
    },
  });

  try {
    await client.send({
      from: `ThriftLine <${username}>`,
      to,
      subject: "Your ThriftLine verification code",
      content: `Your ThriftLine code is ${otp}. It is valid for 5 minutes. Do not share this code.`,
      html:
        `<p>Your ThriftLine verification code is</p>` +
        `<p style="font-size:28px;letter-spacing:6px;font-weight:700">${otp}</p>` +
        `<p>This code expires in 5 minutes. If you did not request it, ignore this email.</p>`,
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

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
    const service = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) {
      return json(401, { error: "Sign in first." });
    }

    const email = normalizeEmail(userData.user.email ?? "");
    if (!email) {
      return json(400, { error: "This account does not have an email address." });
    }

    const { data: recent } = await service
      .from("email_otp_challenges")
      .select("created_at")
      .eq("user_id", userData.user.id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recent?.created_at) {
      const elapsed = Date.now() - new Date(recent.created_at).getTime();
      if (elapsed < 60_000) {
        return json(429, {
          error: `Please wait ${Math.ceil((60_000 - elapsed) / 1000)}s before requesting another code.`,
        });
      }
    }

    const otp = randomOtp();
    const pepper = Deno.env.get("OTP_PEPPER") ?? "";
    const codeHash = await sha256Hex(`${pepper}:${userData.user.id}:${email}:${otp}`);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

    const { error: insertError } = await service.from("email_otp_challenges").insert({
      user_id: userData.user.id,
      email,
      code_hash: codeHash,
      expires_at: expiresAt,
    });
    if (insertError) throw insertError;

    await sendGmail(email, otp);

    return json(200, { ok: true, expires_in_seconds: 300 });
  } catch (error) {
    console.error("send-email-otp", error);
    return json(500, {
      error: "We could not send the email. Check Gmail SMTP setup and try again.",
    });
  }
});
