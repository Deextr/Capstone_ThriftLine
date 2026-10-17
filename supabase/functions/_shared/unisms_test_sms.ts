import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  maskPhMobile,
  normalizePhPhone,
  sendUnisms,
  type SmsSendResult,
} from "./phone_otp.ts";

export const FIXED_TEST_SMS_CONTENT =
  "ThriftLine UniSMS connectivity test. If you did not expect this, contact support.";

export const MAX_TEST_SMS_BODY_BYTES = 512;

export type TestSmsAuthDecision =
  | { allowed: true; role: "super_admin" }
  | { allowed: false; httpStatus: 401 | 403; code: string; message: string };

export type TestSmsBodyDecision =
  | { ok: true; phone: string }
  | { ok: false; httpStatus: 400; code: string; message: string };

export type TestSmsRateClaim =
  | "ok"
  | "cooldown"
  | "user_daily"
  | "global_daily"
  | "error";

export function isTestSmsFeatureEnabled(raw: string | undefined): boolean {
  return (raw ?? "").trim().toLowerCase() === "true";
}

export function parseTestPhoneAllowlist(raw: string | undefined): Set<string> {
  const out = new Set<string>();
  const text = (raw ?? "").trim();
  if (!text) return out;
  for (const part of text.split(/[,;\s]+/)) {
    const normalized = normalizePhPhone(part.trim());
    if (normalized) out.add(normalized);
  }
  return out;
}

export function authorizeTestUnismsSmsUser(params: {
  role: string | null | undefined;
  accountStatus: string | null | undefined;
}): TestSmsAuthDecision {
  const role = params.role ?? "";
  const status = params.accountStatus ?? "";

  if (status !== "active") {
    return {
      allowed: false,
      httpStatus: 403,
      code: "forbidden",
      message: "Super Admin access is required for SMS connectivity tests.",
    };
  }

  if (role === "super_admin") {
    return { allowed: true, role: "super_admin" };
  }

  if (role === "admin") {
    return {
      allowed: false,
      httpStatus: 403,
      code: "forbidden",
      message: "Only a Super Admin may run SMS connectivity tests.",
    };
  }

  return {
    allowed: false,
    httpStatus: 403,
    code: "forbidden",
    message: "Super Admin access is required for SMS connectivity tests.",
  };
}

export function parseTestSmsRequestBody(body: unknown): TestSmsBodyDecision {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return {
      ok: false,
      httpStatus: 400,
      code: "invalid_body",
      message: "Request body must be a JSON object with a phone field.",
    };
  }

  const record = body as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length === 0) {
    return {
      ok: false,
      httpStatus: 400,
      code: "missing_phone",
      message: "Enter a valid 11-digit mobile number starting with 09.",
    };
  }

  for (const key of keys) {
    if (key !== "phone") {
      return {
        ok: false,
        httpStatus: 400,
        code: "invalid_field",
        message: "Only the phone field is accepted for SMS connectivity tests.",
      };
    }
  }

  if (typeof record.phone !== "string" && typeof record.phone !== "number") {
    return {
      ok: false,
      httpStatus: 400,
      code: "invalid_phone",
      message: "Enter a valid 11-digit mobile number starting with 09.",
    };
  }

  const phone = normalizePhPhone(String(record.phone));
  if (!phone) {
    return {
      ok: false,
      httpStatus: 400,
      code: "invalid_phone",
      message: "Enter a valid 11-digit mobile number starting with 09.",
    };
  }

  return { ok: true, phone };
}

export function isPhoneOnTestAllowlist(
  phone: string,
  allowlist: Set<string>,
): boolean {
  if (allowlist.size === 0) return false;
  return allowlist.has(phone);
}

export function mapRateClaimToResponse(claim: TestSmsRateClaim): {
  httpStatus: number;
  code: string;
  message: string;
} | null {
  switch (claim) {
    case "ok":
      return null;
    case "cooldown":
      return {
        httpStatus: 429,
        code: "rate_limited",
        message: "Wait a minute before sending another test SMS.",
      };
    case "user_daily":
      return {
        httpStatus: 429,
        code: "daily_quota",
        message: "You reached today’s test SMS limit for your account.",
      };
    case "global_daily":
      return {
        httpStatus: 429,
        code: "daily_quota",
        message: "Today’s platform test SMS limit has been reached.",
      };
    case "error":
      return {
        httpStatus: 503,
        code: "unavailable",
        message: "Could not complete the SMS test.",
      };
  }
}

export async function writeTestSmsAuditLog(
  service: SupabaseClient,
  params: {
    actorId: string;
    status: "success" | "failed" | "blocked";
    summary: string;
    details?: Record<string, unknown>;
  },
): Promise<void> {
  try {
    const { error } = await service.rpc("write_admin_audit_log", {
      p_category: "system_security",
      p_event_type: "unisms_test_sms",
      p_status: params.status,
      p_summary: params.summary,
      p_actor: params.actorId,
      p_target_type: "phone",
      p_target_id: null,
      p_details: params.details ?? {},
    });
    if (error) {
      console.error("unisms_test_sms audit log failed", error.message);
    }
  } catch (error) {
    console.error("unisms_test_sms audit log threw", error);
  }
}

export type TestUnismsSmsDeps = {
  getUser: () => Promise<{ id: string } | null>;
  loadUserProfile: (
    userId: string,
  ) => Promise<{ role: string | null; account_status: string | null } | null>;
  claimSend: (actorId: string) => Promise<TestSmsRateClaim>;
  sendSms: (phone: string, message: string) => Promise<SmsSendResult>;
  writeAudit: (
    actorId: string,
    status: "success" | "failed" | "blocked",
    summary: string,
    details?: Record<string, unknown>,
  ) => Promise<void>;
  featureEnabled: boolean;
  allowlist: Set<string>;
  fixedMessage: string;
  log: (message: string, fields?: Record<string, unknown>) => void;
};

export async function handleTestUnismsSmsRequest(
  body: unknown,
  deps: TestUnismsSmsDeps,
): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!deps.featureEnabled) {
    return {
      status: 404,
      body: {
        error: "SMS connectivity testing is not enabled on this environment.",
        code: "disabled",
      },
    };
  }

  const user = await deps.getUser();
  if (!user) {
    return {
      status: 401,
      body: { error: "Sign in first.", code: "unauthenticated" },
    };
  }

  const actorId = user.id;
  const profile = await deps.loadUserProfile(actorId);
  const auth = authorizeTestUnismsSmsUser({
    role: profile?.role,
    accountStatus: profile?.account_status,
  });

  if (!auth.allowed) {
    await deps.writeAudit(actorId, "blocked", "Blocked UniSMS connectivity test", {
      reason: auth.code,
      role: profile?.role ?? null,
    });
    return {
      status: auth.httpStatus,
      body: { error: auth.message, code: auth.code },
    };
  }

  const parsed = parseTestSmsRequestBody(body);
  if (!parsed.ok) {
    await deps.writeAudit(actorId, "blocked", "Blocked UniSMS connectivity test", {
      reason: parsed.code,
    });
    return {
      status: parsed.httpStatus,
      body: { error: parsed.message, code: parsed.code },
    };
  }

  const phone = parsed.phone;
  if (!isPhoneOnTestAllowlist(phone, deps.allowlist)) {
    await deps.writeAudit(actorId, "blocked", "Blocked UniSMS connectivity test", {
      reason: "recipient_not_allowed",
      phone: maskPhMobile(phone),
    });
    return {
      status: 403,
      body: {
        error: "That number is not approved for SMS connectivity tests.",
        code: "recipient_not_allowed",
      },
    };
  }

  const claim = await deps.claimSend(actorId);
  const rateResponse = mapRateClaimToResponse(claim);
  if (rateResponse) {
    await deps.writeAudit(actorId, "blocked", "Blocked UniSMS connectivity test", {
      reason: rateResponse.code,
      claim,
      phone: maskPhMobile(phone),
    });
    return {
      status: rateResponse.httpStatus,
      body: { error: rateResponse.message, code: rateResponse.code },
    };
  }

  deps.log("test-unisms-sms send", {
    admin: actorId.slice(0, 8),
    phone: maskPhMobile(phone),
  });

  const result = await deps.sendSms(phone, deps.fixedMessage);

  if (result.accepted) {
    await deps.writeAudit(actorId, "success", "Sent UniSMS connectivity test SMS", {
      phone: maskPhMobile(phone),
      delivery_status: result.deliveryStatus ?? null,
      reference_id: result.referenceId ?? null,
    });
    return {
      status: 200,
      body: {
        ok: true,
        http_status: result.status,
        reference_id: result.referenceId ?? null,
        delivery_status: result.deliveryStatus ?? null,
        code: result.code ?? null,
        error: null,
      },
    };
  }

  await deps.writeAudit(actorId, "failed", "UniSMS connectivity test failed", {
    phone: maskPhMobile(phone),
    provider_code: result.code ?? null,
    http_status: result.status,
  });

  return {
    status: 502,
    body: {
      ok: false,
      http_status: result.status,
      reference_id: result.referenceId ?? null,
      delivery_status: result.deliveryStatus ?? null,
      code: result.code ?? null,
      error: result.userMessage,
    },
  };
}

export function defaultTestUnismsDeps(
  service: SupabaseClient,
  userId: string | null,
  getProfile: TestUnismsSmsDeps["loadUserProfile"],
): TestUnismsSmsDeps {
  return {
    getUser: async () => (userId ? { id: userId } : null),
    loadUserProfile: getProfile,
    claimSend: async (actorId) => {
      const { data, error } = await service.rpc("claim_unisms_test_sms_send", {
        p_actor: actorId,
      });
      if (error) {
        console.error("claim_unisms_test_sms_send failed", error.message);
        return "error";
      }
      const claim = typeof data === "string" ? data : "";
      if (
        claim === "ok" ||
        claim === "cooldown" ||
        claim === "user_daily" ||
        claim === "global_daily"
      ) {
        return claim;
      }
      return "error";
    },
    sendSms: sendUnisms,
    writeAudit: (actorId, status, summary, details) =>
      writeTestSmsAuditLog(service, { actorId, status, summary, details }),
    featureEnabled: isTestSmsFeatureEnabled(
      Deno.env.get("UNISMS_TEST_SMS_ENABLED"),
    ),
    allowlist: parseTestPhoneAllowlist(
      Deno.env.get("UNISMS_TEST_PHONE_ALLOWLIST"),
    ),
    fixedMessage: FIXED_TEST_SMS_CONTENT,
    log: (message, fields) => console.log(message, fields ?? {}),
  };
}
