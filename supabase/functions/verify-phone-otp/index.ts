import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  MAX_VERIFY_ATTEMPTS,
  PHONE_ALREADY_IN_USE_MESSAGE,
  isPhoneVerifiedByOtherAccount,
  maskPhMobile,
  normalizePhPhone,
  sha256Hex,
  timingSafeEqual,
} from "../_shared/phone_otp.ts";

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
      return json(401, {
        error: "Sign in first.",
        code: "unauthenticated",
      });
    }

    const body = await req.json();
    const phone = normalizePhPhone(String(body.phone ?? ""));
    const token = String(body.token ?? "").replace(/\D/g, "");
    if (!phone) {
      return json(400, {
        error: "Enter a valid 11-digit mobile number starting with 09.",
        code: "invalid_phone",
      });
    }
    if (token.length < 6) {
      return json(400, {
        error: "Enter the 6-digit code from the SMS.",
        code: "invalid_code",
      });
    }

    const pepper = Deno.env.get("OTP_PEPPER") ?? "";
    if (!pepper.trim()) {
      console.error("verify-phone-otp OTP_PEPPER is not configured");
      return json(503, {
        error: "Could not verify that code. Please try again.",
        code: "unavailable",
      });
    }

    const userId = userData.user.id;
    console.log("verify-phone-otp attempt", {
      user: userId.slice(0, 8),
      phone: maskPhMobile(phone),
    });

    const { data: challenge, error: fetchError } = await service
      .from("phone_otp_challenges")
      .select("challenge_id, code_hash, expires_at, attempt_count, consumed_at")
      .eq("user_id", userId)
      .eq("phone", phone)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!challenge) {
      console.log("verify-phone-otp failed", { reason: "no_active_code" });
      return json(400, {
        error: "No active code. Request a new one.",
        code: "no_active_code",
      });
    }
    if (challenge.consumed_at) {
      console.log("verify-phone-otp failed", { reason: "already_used" });
      return json(400, {
        error: "That code is no longer valid. Request a new one.",
        code: "already_used",
      });
    }
    if (new Date(challenge.expires_at).getTime() < Date.now()) {
      console.log("verify-phone-otp failed", { reason: "expired" });
      return json(400, {
        error: "That code has expired. Request a new one.",
        code: "expired",
      });
    }
    if ((challenge.attempt_count ?? 0) >= MAX_VERIFY_ATTEMPTS) {
      console.log("verify-phone-otp rate-limit", { reason: "too_many_attempts" });
      return json(429, {
        error: "Too many attempts. Request a new code.",
        code: "too_many_attempts",
      });
    }

    if (await isPhoneVerifiedByOtherAccount(service, phone, userId)) {
      console.log("verify-phone-otp failed", { reason: "phone_already_in_use" });
      return json(409, {
        error: PHONE_ALREADY_IN_USE_MESSAGE,
        code: "phone_already_in_use",
      });
    }

    const incoming = await sha256Hex(`${pepper}:${userId}:${phone}:${token}`);
    if (!timingSafeEqual(incoming, String(challenge.code_hash))) {
      const nextAttempts = (challenge.attempt_count ?? 0) + 1;
      const locked = nextAttempts >= MAX_VERIFY_ATTEMPTS;
      await service
        .from("phone_otp_challenges")
        .update({
          attempt_count: nextAttempts,
          ...(locked ? { consumed_at: new Date().toISOString() } : {}),
        })
        .eq("challenge_id", challenge.challenge_id);
      console.log("verify-phone-otp failed", {
        reason: locked ? "too_many_attempts" : "invalid_code",
      });
      if (locked) {
        return json(429, {
          error: "Too many attempts. Request a new code.",
          code: "too_many_attempts",
        });
      }
      return json(400, {
        error: "That code is invalid.",
        code: "invalid_code",
      });
    }

    await service
      .from("phone_otp_challenges")
      .update({ consumed_at: new Date().toISOString() })
      .eq("challenge_id", challenge.challenge_id);

    const { error: updateError } = await service
      .from("users")
      .update({ phone_number: phone, is_phone_verified: true })
      .eq("user_id", userId);
    if (updateError) {
      if (updateError.code === "23505") {
        return json(409, {
          error: PHONE_ALREADY_IN_USE_MESSAGE,
          code: "phone_already_in_use",
        });
      }
      throw updateError;
    }

    const deviceToken = String(body.device_token ?? "").trim();
    const platformRaw = String(body.platform ?? "").trim().toLowerCase();
    const platform =
      platformRaw === "android" || platformRaw === "ios" ? platformRaw : "other";
    if (deviceToken.length >= 32) {
      const tokenHash =
        /^[0-9a-f]{64}$/i.test(deviceToken)
          ? deviceToken.toLowerCase()
          : await sha256Hex(deviceToken);
      const { error: signalError } = await service.rpc(
        "register_user_install_signal",
        {
          p_user_id: userId,
          p_token_hash: tokenHash,
          p_platform: platform,
        },
      );
      if (signalError) {
        console.error("verify-phone-otp install signal", signalError);
      }
    }

    console.log("verify-phone-otp success", {
      user: userId.slice(0, 8),
      phone: maskPhMobile(phone),
    });
    return json(200, { ok: true });
  } catch (error) {
    console.error("verify-phone-otp", error);
    return json(500, {
      error: "Could not verify that code. Please try again.",
      code: "unavailable",
    });
  }
});
