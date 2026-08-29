import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function normalizePhPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  if (digits.startsWith("63") && digits.length === 12) return `0${digits.slice(2)}`;
  if (digits.startsWith("0") && digits.length === 11) return digits;
  if (digits.length === 10 && digits.startsWith("9")) return `0${digits}`;
  return null;
}

function toFmcsmsNumber(raw: string): string {
  const local = normalizePhPhone(raw);
  if (!local) return raw.replace(/\D/g, "");
  return `+63${local.slice(1)}`;
}

function randomOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function sendFmcsms(phone: string, message: string): Promise<void> {
  const apiKey = Deno.env.get("FMCSMS_API_KEY");
  const endpoint =
    Deno.env.get("FMCSMS_API_URL") ??
    "https://www.fortmed.org/web/FMCSMS/api/messages.php";
  const senderName = Deno.env.get("FMCSMS_SENDER") ?? "ThriftLine";
  const fromNumber = Deno.env.get("FMCSMS_FROM_NUMBER") ?? "";
  if (!apiKey) throw new Error("FMCSMS_API_KEY is not configured");
  if (!fromNumber.trim()) {
    throw new Error(
      "FMCSMS_FROM_NUMBER is not configured. Set it to the sender number from the FMCSMS dashboard.",
    );
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-Key": apiKey,
    },
    body: JSON.stringify({
      SenderName: senderName,
      ToNumber: toFmcsmsNumber(phone),
      MessageBody: message,
      FromNumber: toFmcsmsNumber(fromNumber),
    }),
  });

  const text = await response.text();
  let parsed: Record<string, unknown> | null = null;
  try {
    parsed = JSON.parse(text) as Record<string, unknown>;
  } catch {
    parsed = null;
  }

  const failed =
    !response.ok ||
    parsed?.success === false ||
    parsed?.status === "error" ||
    parsed?.error != null;

  if (failed) {
    const detail =
      (parsed?.error as string | undefined) ??
      (parsed?.message as string | undefined) ??
      text.slice(0, 200);
    throw new Error(`FMCSMS failed (${response.status}): ${detail}`);
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

    const body = await req.json();
    const phone = normalizePhPhone(String(body.phone ?? ""));
    if (!phone) {
      return json(400, { error: "Enter a valid Philippine mobile number." });
    }

    const { data: recent } = await service
      .from("phone_otp_challenges")
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
    const pepper = Deno.env.get("OTP_PEPPER") ?? Deno.env.get("FMCSMS_API_KEY") ?? "";
    const codeHash = await sha256Hex(`${pepper}:${userData.user.id}:${phone}:${otp}`);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

    const { error: insertError } = await service.from("phone_otp_challenges").insert({
      user_id: userData.user.id,
      phone,
      code_hash: codeHash,
      expires_at: expiresAt,
    });
    if (insertError) throw insertError;

    await sendFmcsms(
      phone,
      `ThriftLine code: ${otp}. Valid 5 minutes. Do not share this code.`,
    );

    return json(200, { ok: true, expires_in_seconds: 300 });
  } catch (error) {
    console.error("send-phone-otp", error);
    return json(500, {
      error: "We could not send the SMS. Check FMCSMS setup and try again.",
    });
  }
});
