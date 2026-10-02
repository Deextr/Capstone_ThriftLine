import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { clientIp, sha256Hex } from "../_shared/phone_otp.ts";
import {
  turnstileUserMessage,
  verifyTurnstileToken,
} from "../_shared/turnstile.ts";

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

type GoTrueTokenResponse = {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  token_type?: string;
  user?: Record<string, unknown>;
  error?: string;
  error_description?: string;
  msg?: string;
  message?: string;
  code?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed", code: "method_not_allowed" });
  }

  let email = "";
  let password = "";
  let turnstileToken = "";
  try {
    const body = await req.json();
    email = normalizeEmail(typeof body?.email === "string" ? body.email : "");
    password = typeof body?.password === "string" ? body.password : "";
    turnstileToken = typeof body?.turnstile_token === "string"
      ? body.turnstile_token
      : typeof body?.captcha_token === "string"
      ? body.captcha_token
      : "";
  } catch {
    return json(400, {
      error: "Enter a valid email and password.",
      code: "invalid_request",
    });
  }

  if (!isEmail(email)) {
    return json(400, {
      error: "Enter a valid email and password.",
      code: "invalid_request",
    });
  }
  if (!password || password.length > 256) {
    return json(400, {
      error: "Enter a valid email and password.",
      code: "invalid_request",
    });
  }
  if (!turnstileToken.trim()) {
    return json(400, {
      error: "Complete human verification before signing in.",
      code: "turnstile_required",
    });
  }

  const remoteIp = clientIp(req);
  const turnstile = await verifyTurnstileToken(turnstileToken, remoteIp, {
    expectedAction: "login",
  });
  if (!turnstile.success) {
    return json(403, {
      error: turnstileUserMessage(turnstile["error-codes"]),
      code: "turnstile_failed",
    });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey) {
    console.error("sign-in-with-email Supabase env is not configured");
    return json(503, {
      error: "Sign-in is temporarily unavailable. Please try again.",
      code: "unavailable",
    });
  }

  const service = createClient(supabaseUrl, serviceKey);
  const pepper = Deno.env.get("OTP_PEPPER") ?? "email-login";
  const emailHash = await sha256Hex(`${pepper}:${email}`);
  const ipHash = remoteIp
    ? await sha256Hex(`${pepper}:ip:${remoteIp}`)
    : null;

  const { data: claim, error: claimError } = await service.rpc(
    "claim_email_login_attempt",
    { p_email_hash: emailHash, p_ip_hash: ipHash },
  );
  if (claimError) {
    console.error("sign-in-with-email rate limit unavailable");
    return json(503, {
      error: "Sign-in is temporarily unavailable. Please try again.",
      code: "unavailable",
    });
  }
  if (claim === "cooldown") {
    return json(429, {
      error: "Too many attempts. Please wait a moment and try again.",
      code: "rate_limited",
    });
  }
  if (claim === "email_hourly" || claim === "ip_hourly") {
    return json(429, {
      error: "Too many sign-in attempts. Please wait and try again later.",
      code: "rate_limited",
    });
  }

  const authResponse = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        password,
      }),
    },
  );

  let payload: GoTrueTokenResponse;
  try {
    payload = await authResponse.json();
  } catch {
    console.error("sign-in-with-email GoTrue response was not JSON");
    return json(503, {
      error: "Sign-in is temporarily unavailable. Please try again.",
      code: "unavailable",
    });
  }

  if (!authResponse.ok || !payload.access_token || !payload.refresh_token) {
    const code = (payload.code ?? payload.error ?? "").toLowerCase();
    const msg = (payload.msg ?? payload.message ?? payload.error_description ??
      "")
      .toLowerCase();

    if (code.includes("captcha") || msg.includes("captcha")) {
      return json(403, {
        error: "Human verification failed. Please try again.",
        code: "turnstile_failed",
      });
    }
    if (code.includes("rate") || msg.includes("rate limit") ||
      msg.includes("too many")) {
      return json(429, {
        error: "Too many attempts. Please wait a moment and try again.",
        code: "rate_limited",
      });
    }

    return json(401, {
      error: "Invalid email or password. Please try again.",
      code: "invalid_credentials",
    });
  }

  return json(200, {
    session: {
      access_token: payload.access_token,
      refresh_token: payload.refresh_token,
      expires_in: payload.expires_in,
      token_type: payload.token_type ?? "bearer",
      user: payload.user,
    },
  });
});
