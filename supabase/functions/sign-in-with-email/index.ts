import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { clientIp, sha256Hex } from "../_shared/phone_otp.ts";
import {
  turnstileUserMessage,
  verifyTurnstileToken,
} from "../_shared/turnstile.ts";

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  return {
    "Access-Control-Allow-Origin": origin && origin.length > 0 ? origin : "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-client-version, accept, x-supabase-api-version, prefer, x-region, cache-control, pragma",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function json(req: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
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
  user?: Record<string, unknown> & { id?: string };
  error?: string;
  error_description?: string;
  msg?: string;
  message?: string;
  code?: string;
};

const ADMIN_MAX_LOGIN_ATTEMPTS = 5;

type AdminLockState = {
  locked?: boolean;
  failed_attempts?: number;
  retry_after_seconds?: number;
};

function adminAttemptsRemaining(failedAttempts: number): number {
  return Math.max(0, ADMIN_MAX_LOGIN_ATTEMPTS - failedAttempts);
}

function adminLockErrorMessage(retrySeconds: number): string {
  if (retrySeconds >= 60) {
    const minutes = Math.ceil(retrySeconds / 60);
    return `Too many failed login attempts. Please try again in ${minutes} minute${
      minutes === 1 ? "" : "s"
    }.`;
  }
  return `Too many failed login attempts. Please try again in ${retrySeconds} second${
    retrySeconds === 1 ? "" : "s"
  }.`;
}

function adminLockResponse(
  req: Request,
  state: AdminLockState,
): Response | null {
  if (state.locked !== true) return null;
  const retry = typeof state.retry_after_seconds === "number"
    ? Math.max(1, Math.floor(state.retry_after_seconds))
    : 300;
  const failed = typeof state.failed_attempts === "number"
    ? state.failed_attempts
    : ADMIN_MAX_LOGIN_ATTEMPTS;
  return json(req, 429, {
    error: adminLockErrorMessage(retry),
    code: "admin_login_locked",
    retry_after_seconds: retry,
    failed_attempts: failed,
    attempts_remaining: 0,
    max_attempts: ADMIN_MAX_LOGIN_ATTEMPTS,
  });
}

function adminInvalidCredentialsResponse(
  req: Request,
  state: AdminLockState | null,
) {
  const failed = typeof state?.failed_attempts === "number"
    ? state.failed_attempts
    : 0;
  const remaining = adminAttemptsRemaining(failed);
  return json(req, 401, {
    error: "Incorrect email or password. Please try again.",
    code: "invalid_credentials",
    failed_attempts: failed,
    attempts_remaining: remaining,
    max_attempts: ADMIN_MAX_LOGIN_ATTEMPTS,
  });
}

async function logAdminAuthAudit(
  // deno-lint-ignore no-explicit-any
  service: any,
  params: {
    eventType: string;
    status: "success" | "failed" | "blocked";
    summary: string;
    actorEmail?: string;
    actorUserId?: string;
    details?: Record<string, unknown>;
    ipHash?: string | null;
  },
) {
  try {
    const { error } = await service.rpc("insert_admin_auth_audit_log", {
      p_event_type: params.eventType,
      p_status: params.status,
      p_summary: params.summary,
      p_actor_email: params.actorEmail ?? null,
      p_actor_user_id: params.actorUserId ?? null,
      p_details: params.details ?? {},
      p_ip_hash: params.ipHash ?? null,
    });
    if (error) {
      console.error("sign-in-with-email audit log failed", error);
    }
  } catch (error) {
    console.error("sign-in-with-email audit log threw", error);
  }
}

function isMissingAdminLockRpc(error: { message?: string; code?: string }) {
  const msg = (error.message ?? "").toLowerCase();
  const code = (error.code ?? "").toLowerCase();
  return code === "pgrst202" ||
    code === "42883" ||
    msg.includes("could not find the function") ||
    msg.includes("does not exist");
}

async function checkAdminPortalLock(
  req: Request,
  // deno-lint-ignore no-explicit-any
  service: any,
  emailHash: string,
): Promise<Response | null> {
  try {
    const { data, error } = await service.rpc("check_admin_portal_login", {
      p_email_hash: emailHash,
    });
    if (error) {
      if (isMissingAdminLockRpc(error)) {
        console.warn(
          "sign-in-with-email admin lock RPC missing; apply migration 20261006240000",
        );
        return null;
      }
      console.error("sign-in-with-email admin lock check failed", error);
      return null;
    }
    return adminLockResponse(req, (data ?? {}) as AdminLockState);
  } catch (error) {
    console.error("sign-in-with-email admin lock check threw", error);
    return null;
  }
}

async function recordAdminPortalFailure(
  // deno-lint-ignore no-explicit-any
  service: any,
  emailHash: string,
): Promise<AdminLockState | null> {
  try {
    const { data, error } = await service.rpc(
      "record_admin_portal_login_failure",
      { p_email_hash: emailHash },
    );
    if (error) {
      if (isMissingAdminLockRpc(error)) {
        console.warn(
          "sign-in-with-email admin failure RPC missing; apply migration 20261006240000",
        );
        return null;
      }
      console.error("sign-in-with-email admin failure record failed", error);
      return null;
    }
    return (data ?? {}) as AdminLockState;
  } catch (error) {
    console.error("sign-in-with-email admin failure record threw", error);
    return null;
  }
}

async function clearAdminPortalFailures(
  // deno-lint-ignore no-explicit-any
  service: any,
  emailHash: string,
) {
  try {
    const { error } = await service.rpc("clear_admin_portal_login_failures", {
      p_email_hash: emailHash,
    });
    if (error && !isMissingAdminLockRpc(error)) {
      console.error("sign-in-with-email admin clear failures failed", error);
    }
  } catch (error) {
    console.error("sign-in-with-email admin clear failures threw", error);
  }
}

Deno.serve(async (req) => {
  try {
    const cors = corsHeaders(req);
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: cors });
    }
    if (req.method !== "POST") {
      return json(req, 405, {
        error: "Method not allowed",
        code: "method_not_allowed",
      });
    }

    let email = "";
    let password = "";
    let turnstileToken = "";
    let loginPortal = "app";
    try {
      const body = await req.json();
      email = normalizeEmail(typeof body?.email === "string" ? body.email : "");
      password = typeof body?.password === "string" ? body.password : "";
      turnstileToken = typeof body?.turnstile_token === "string"
        ? body.turnstile_token
        : typeof body?.captcha_token === "string"
        ? body.captcha_token
        : "";
      const portalRaw = typeof body?.login_portal === "string"
        ? body.login_portal.trim().toLowerCase()
        : "";
      if (portalRaw === "admin") loginPortal = "admin";
    } catch {
      return json(req, 400, {
        error: "Enter a valid email and password.",
        code: "invalid_request",
      });
    }

    const isAdminPortal = loginPortal === "admin";

    if (!isEmail(email)) {
      return json(req, 400, {
        error: "Enter a valid email and password.",
        code: "invalid_request",
      });
    }
    if (!password || password.length > 256) {
      return json(req, 400, {
        error: "Enter a valid email and password.",
        code: "invalid_request",
      });
    }
    if (!turnstileToken.trim()) {
      return json(req, 400, {
        error: "Complete human verification before signing in.",
        code: "turnstile_required",
      });
    }

    const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    if (!supabaseUrl || !serviceKey || !anonKey) {
      console.error("sign-in-with-email Supabase env is not configured");
      return json(req, 503, {
        error: "Sign-in is temporarily unavailable. Please try again.",
        code: "unavailable",
      });
    }

    const service = createClient(supabaseUrl, serviceKey);
    const pepper = Deno.env.get("OTP_PEPPER") ?? "email-login";
    const remoteIp = clientIp(req);
    const emailHash = await sha256Hex(`${pepper}:${email}`);
    const ipHash = remoteIp
      ? await sha256Hex(`${pepper}:ip:${remoteIp}`)
      : null;

    const turnstile = await verifyTurnstileToken(turnstileToken, remoteIp, {
      expectedAction: "login",
    });
    if (!turnstile.success) {
      if (isAdminPortal) {
        await logAdminAuthAudit(service, {
          eventType: "admin_turnstile_failed",
          status: "failed",
          summary: "Turnstile verification failed on admin login",
          actorEmail: email,
          ipHash: ipHash,
          details: { login_portal: "admin" },
        });
      }
      return json(req, 403, {
        error: turnstileUserMessage(turnstile["error-codes"]),
        code: "turnstile_failed",
      });
    }

    if (isAdminPortal) {
      const locked = await checkAdminPortalLock(req, service, emailHash);
      if (locked) {
        await logAdminAuthAudit(service, {
          eventType: "admin_login_blocked",
          status: "blocked",
          summary: "Admin login blocked during active lockout",
          actorEmail: email,
          ipHash: ipHash,
          details: { login_portal: "admin" },
        });
        return locked;
      }
    }

    const { data: claim, error: claimError } = await service.rpc(
      "claim_email_login_attempt",
      { p_email_hash: emailHash, p_ip_hash: ipHash },
    );
    if (claimError) {
      console.error("sign-in-with-email rate limit unavailable", claimError);
      return json(req, 503, {
        error: "Sign-in is temporarily unavailable. Please try again.",
        code: "unavailable",
      });
    }
    if (claim === "cooldown") {
      return json(req, 429, {
        error: "Too many attempts. Please wait a moment and try again.",
        code: "rate_limited",
      });
    }
    if (claim === "email_hourly" || claim === "ip_hourly") {
      return json(req, 429, {
        error: "Too many sign-in attempts. Please wait and try again later.",
        code: "rate_limited",
      });
    }

    let authResponse: Response;
    try {
      authResponse = await fetch(
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
    } catch (error) {
      console.error("sign-in-with-email GoTrue fetch failed", error);
      return json(req, 503, {
        error: "Sign-in is temporarily unavailable. Please try again.",
        code: "unavailable",
      });
    }

    let payload: GoTrueTokenResponse;
    try {
      payload = await authResponse.json();
    } catch {
      console.error("sign-in-with-email GoTrue response was not JSON");
      return json(req, 503, {
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
        return json(req, 403, {
          error: "Human verification failed. Please try again.",
          code: "turnstile_failed",
        });
      }
      if (code.includes("rate") || msg.includes("rate limit") ||
        msg.includes("too many")) {
        return json(req, 429, {
          error: "Too many attempts. Please wait a moment and try again.",
          code: "rate_limited",
        });
      }

      if (isAdminPortal) {
        const failureState = await recordAdminPortalFailure(service, emailHash);
        if (failureState?.locked === true) {
          await logAdminAuthAudit(service, {
            eventType: "admin_login_lockout",
            status: "blocked",
            summary: "Admin login lockout triggered after failed attempts",
            actorEmail: email,
            ipHash: ipHash,
            details: {
              login_portal: "admin",
              failed_attempts: failureState.failed_attempts ??
                ADMIN_MAX_LOGIN_ATTEMPTS,
              max_attempts: ADMIN_MAX_LOGIN_ATTEMPTS,
            },
          });
          const locked = adminLockResponse(req, failureState);
          if (locked) return locked;
        }
        const failed = failureState?.failed_attempts ?? 0;
        await logAdminAuthAudit(service, {
          eventType: "admin_login_failed",
          status: "failed",
          summary: "Failed admin login attempt",
          actorEmail: email,
          ipHash: ipHash,
          details: {
            login_portal: "admin",
            reason: "invalid_credentials",
            failed_attempts: failed,
            max_attempts: ADMIN_MAX_LOGIN_ATTEMPTS,
            attempt: `${failed} of ${ADMIN_MAX_LOGIN_ATTEMPTS}`,
          },
        });
        return adminInvalidCredentialsResponse(req, failureState);
      }

      return json(req, 401, {
        error: "Incorrect email or password. Please try again.",
        code: "invalid_credentials",
      });
    }

    const userId = payload.user?.id;
    if (isAdminPortal) {
      if (!userId) {
        return json(req, 503, {
          error: "Sign-in is temporarily unavailable. Please try again.",
          code: "unavailable",
        });
      }

      const { data: profile, error: profileError } = await service
        .from("users")
        .select("role")
        .eq("user_id", userId)
        .maybeSingle();

      if (profileError) {
        console.error("sign-in-with-email admin role lookup failed", profileError);
        return json(req, 503, {
          error: "Sign-in is temporarily unavailable. Please try again.",
          code: "unavailable",
        });
      }

      if (profile?.role !== "admin") {
        await logAdminAuthAudit(service, {
          eventType: "admin_login_denied",
          status: "failed",
          summary: "Sign-in rejected: account is not an administrator",
          actorEmail: email,
          actorUserId: userId,
          ipHash: ipHash,
          details: { login_portal: "admin", reason: "admin_access_denied" },
        });
        return json(req, 403, {
          error: "This account does not have admin access.",
          code: "admin_access_denied",
        });
      }

      await clearAdminPortalFailures(service, emailHash);
      await logAdminAuthAudit(service, {
        eventType: "admin_login_password_accepted",
        status: "success",
        summary: "Admin credentials accepted; email OTP may be required",
        actorEmail: email,
        actorUserId: userId,
        ipHash: ipHash,
        details: { login_portal: "admin" },
      });
    }

    return json(req, 200, {
      session: {
        access_token: payload.access_token,
        refresh_token: payload.refresh_token,
        expires_in: payload.expires_in,
        token_type: payload.token_type ?? "bearer",
        user: payload.user,
      },
    });
  } catch (error) {
    console.error("sign-in-with-email unhandled error", error);
    return json(req, 500, {
      error: "Sign-in is temporarily unavailable. Please try again.",
      code: "unavailable",
    });
  }
});
