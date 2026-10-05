import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  MAX_SENDS_PER_IP_HOUR,
  MAX_SENDS_PER_PHONE_HOUR,
  MAX_SENDS_PER_USER_HOUR,
  OTP_TTL_MS,
  PHONE_ALREADY_IN_USE_MESSAGE,
  PhoneOtpHttpError,
  RESEND_COOLDOWN_MS,
  clientIp,
  currentVerifiedPhoneForUser,
  isPhoneVerifiedByOtherAccount,
  maskPhMobile,
  normalizePhPhone,
  randomOtp,
  secondsUntil,
  buildPhoneOtpSmsMessage,
  sendSms,
  sha256Hex,
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

function hourAgoIso(): string {
  return new Date(Date.now() - 60 * 60 * 1000).toISOString();
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
    if (!phone) {
      return json(400, {
        error: "Enter a valid 11-digit mobile number starting with 09.",
        code: "invalid_phone",
      });
    }

    const pepper = Deno.env.get("OTP_PEPPER") ?? "";
    if (!pepper.trim()) {
      console.error("send-phone-otp OTP_PEPPER is not configured");
      return json(503, {
        error:
          "SMS verification is temporarily unavailable. Please try again later.",
        code: "unavailable",
      });
    }

    const ip = clientIp(req);
    const ipHash = ip ? await sha256Hex(`${pepper}:ip:${ip}`) : null;
    const userId = userData.user.id;

    console.log("send-phone-otp request received", {
      user: userId.slice(0, 8),
      phone: maskPhMobile(phone),
    });

    const currentVerified = await currentVerifiedPhoneForUser(service, userId);
    if (currentVerified === phone) {
      console.log("send-phone-otp skipped", { reason: "already_verified_for_user" });
      return json(200, {
        ok: true,
        already_verified: true,
        expires_in_seconds: OTP_TTL_MS / 1000,
        retry_after_seconds: RESEND_COOLDOWN_MS / 1000,
      });
    }

    if (await isPhoneVerifiedByOtherAccount(service, phone, userId)) {
      console.log("send-phone-otp rejected", { reason: "phone_already_in_use" });
      return json(409, {
        error: PHONE_ALREADY_IN_USE_MESSAGE,
        code: "phone_already_in_use",
      });
    }

    const { data: recentUser } = await service
      .from("phone_otp_challenges")
      .select("created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recentUser?.created_at) {
      const elapsed = Date.now() - new Date(recentUser.created_at).getTime();
      if (elapsed < RESEND_COOLDOWN_MS) {
        const wait = secondsUntil(elapsed, RESEND_COOLDOWN_MS);
        console.log("send-phone-otp rate-limit", {
          scope: "user_cooldown",
          phone: maskPhMobile(phone),
        });
        throw new PhoneOtpHttpError(
          429,
          "resend_cooldown",
          `Please wait ${wait}s before requesting another code.`,
          wait,
        );
      }
    }

    const { data: recentPhone } = await service
      .from("phone_otp_challenges")
      .select("created_at")
      .eq("phone", phone)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recentPhone?.created_at) {
      const elapsed = Date.now() - new Date(recentPhone.created_at).getTime();
      if (elapsed < RESEND_COOLDOWN_MS) {
        const wait = secondsUntil(elapsed, RESEND_COOLDOWN_MS);
        console.log("send-phone-otp rate-limit", {
          scope: "phone_cooldown",
          phone: maskPhMobile(phone),
        });
        throw new PhoneOtpHttpError(
          429,
          "resend_cooldown",
          `Please wait ${wait}s before requesting another code.`,
          wait,
        );
      }
    }

    const since = hourAgoIso();
    const [{ count: userHourCount }, { count: phoneHourCount }] =
      await Promise.all([
        service
          .from("phone_otp_challenges")
          .select("challenge_id", { count: "exact", head: true })
          .eq("user_id", userId)
          .gte("created_at", since),
        service
          .from("phone_otp_challenges")
          .select("challenge_id", { count: "exact", head: true })
          .eq("phone", phone)
          .gte("created_at", since),
      ]);

    if ((userHourCount ?? 0) >= MAX_SENDS_PER_USER_HOUR) {
      console.log("send-phone-otp rate-limit", {
        scope: "user_hour",
        phone: maskPhMobile(phone),
      });
      throw new PhoneOtpHttpError(
        429,
        "rate_limited",
        "Too many verification codes were requested. Please try again later.",
      );
    }
    if ((phoneHourCount ?? 0) >= MAX_SENDS_PER_PHONE_HOUR) {
      console.log("send-phone-otp rate-limit", {
        scope: "phone_hour",
        phone: maskPhMobile(phone),
      });
      throw new PhoneOtpHttpError(
        429,
        "rate_limited",
        "Too many verification codes were requested. Please try again later.",
      );
    }

    if (ipHash) {
      const { count: ipHourCount, error: ipCountError } = await service
        .from("phone_otp_challenges")
        .select("challenge_id", { count: "exact", head: true })
        .eq("client_ip_hash", ipHash)
        .gte("created_at", since);
      if (!ipCountError && (ipHourCount ?? 0) >= MAX_SENDS_PER_IP_HOUR) {
        console.log("send-phone-otp rate-limit", {
          scope: "ip_hour",
          phone: maskPhMobile(phone),
        });
        throw new PhoneOtpHttpError(
          429,
          "rate_limited",
          "Too many verification codes were requested. Please try again later.",
        );
      }
    }

    const otp = randomOtp();
    const codeHash = await sha256Hex(`${pepper}:${userId}:${phone}:${otp}`);
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString();

    const insertPayload: Record<string, unknown> = {
      user_id: userId,
      phone,
      code_hash: codeHash,
      expires_at: expiresAt,
    };
    if (ipHash) insertPayload.client_ip_hash = ipHash;

    let { data: inserted, error: insertError } = await service
      .from("phone_otp_challenges")
      .insert(insertPayload)
      .select("challenge_id")
      .single();
    if (insertError && ipHash) {
      delete insertPayload.client_ip_hash;
      const retry = await service
        .from("phone_otp_challenges")
        .insert(insertPayload)
        .select("challenge_id")
        .single();
      inserted = retry.data;
      insertError = retry.error;
    }
    if (insertError || !inserted) throw insertError;

    const sms = await sendSms(phone, buildPhoneOtpSmsMessage(otp));

    if (!sms.accepted) {
      await service
        .from("phone_otp_challenges")
        .update({ consumed_at: new Date().toISOString() })
        .eq("challenge_id", inserted.challenge_id);
      console.log("send-phone-otp rejected", {
        phone: maskPhMobile(phone),
        status: sms.status,
        code: sms.code,
      });
      return json(sms.code === "invalid_phone" ? 400 : 502, {
        error:
          sms.userMessage ??
          "We could not send the verification code. Please try again.",
        code: sms.code ?? "send_failed",
      });
    }

    console.log("send-phone-otp accepted", {
      phone: maskPhMobile(phone),
      status: sms.status,
    });
    return json(200, {
      ok: true,
      expires_in_seconds: OTP_TTL_MS / 1000,
      retry_after_seconds: RESEND_COOLDOWN_MS / 1000,
    });
  } catch (error) {
    if (error instanceof PhoneOtpHttpError) {
      return json(error.status, error.toBody());
    }
    console.error("send-phone-otp", error);
    return json(500, {
      error: "We could not send the verification code. Please try again.",
      code: "send_failed",
    });
  }
});
