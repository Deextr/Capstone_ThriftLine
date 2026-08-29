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

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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
    const token = String(body.token ?? "").replace(/\D/g, "");
    if (!phone) return json(400, { error: "Enter a valid Philippine mobile number." });
    if (token.length < 6) return json(400, { error: "Enter the 6-digit code from the SMS." });

    const { data: challenge, error: fetchError } = await service
      .from("phone_otp_challenges")
      .select("challenge_id, code_hash, expires_at, attempt_count, consumed_at")
      .eq("user_id", userData.user.id)
      .eq("phone", phone)
      .is("consumed_at", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!challenge) {
      return json(400, { error: "No active code. Request a new one." });
    }
    if (new Date(challenge.expires_at).getTime() < Date.now()) {
      return json(400, { error: "That code has expired. Request a new one." });
    }
    if ((challenge.attempt_count ?? 0) >= 5) {
      return json(429, { error: "Too many attempts. Request a new code." });
    }

    const pepper = Deno.env.get("OTP_PEPPER") ?? Deno.env.get("FMCSMS_API_KEY") ?? "";
    const incoming = await sha256Hex(`${pepper}:${userData.user.id}:${phone}:${token}`);

    if (incoming !== challenge.code_hash) {
      await service
        .from("phone_otp_challenges")
        .update({ attempt_count: (challenge.attempt_count ?? 0) + 1 })
        .eq("challenge_id", challenge.challenge_id);
      return json(400, { error: "That code is invalid." });
    }

    await service
      .from("phone_otp_challenges")
      .update({ consumed_at: new Date().toISOString() })
      .eq("challenge_id", challenge.challenge_id);

    const { error: updateError } = await service
      .from("users")
      .update({ phone_number: phone, is_phone_verified: true })
      .eq("user_id", userData.user.id);
    if (updateError) throw updateError;

    return json(200, { ok: true });
  } catch (error) {
    console.error("verify-phone-otp", error);
    return json(500, { error: "Could not verify that code. Please try again." });
  }
});
