export const NETWORK_UNAVAILABLE_MESSAGE =
  "SMS verification is currently unavailable for this mobile number. Please use another supported number or try again later.";

/** @deprecated Use [NETWORK_UNAVAILABLE_MESSAGE] for new provider errors. */
export const DITO_UNAVAILABLE_MESSAGE = NETWORK_UNAVAILABLE_MESSAGE;

export const RESEND_COOLDOWN_MS = 60_000;
export const OTP_TTL_MS = 5 * 60_000;
export const MAX_VERIFY_ATTEMPTS = 5;
export const MAX_SENDS_PER_USER_HOUR = 5;
export const MAX_SENDS_PER_PHONE_HOUR = 5;
export const MAX_SENDS_PER_IP_HOUR = 10;
export const SMS_PROVIDER_TIMEOUT_MS = 15_000;

export const DEFAULT_FMCSMS_URL =
  "https://www.fortmed.org/web/FMCSMS/api/messages.php";

export const DEFAULT_UNISMS_API_URL = "https://unismsapi.com/api";

export type PhoneOtpErrorCode =
  | "invalid_phone"
  | "unauthenticated"
  | "resend_cooldown"
  | "rate_limited"
  | "too_many_attempts"
  | "expired"
  | "invalid_code"
  | "already_used"
  | "no_active_code"
  | "phone_already_in_use"
  | "dito_unavailable"
  | "network_unavailable"
  | "provider_auth"
  | "provider_credits"
  | "provider_error"
  | "provider_timeout"
  | "send_failed"
  | "unavailable";

export const PHONE_ALREADY_IN_USE_MESSAGE =
  "This phone number is already in use. Please use a different phone number.";

export class PhoneOtpHttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: PhoneOtpErrorCode,
    readonly userMessage: string,
    readonly retryAfterSeconds?: number,
  ) {
    super(userMessage);
    this.name = "PhoneOtpHttpError";
  }

  toBody(): Record<string, unknown> {
    return {
      error: this.userMessage,
      code: this.code,
      ...(this.retryAfterSeconds != null
        ? { retry_after_seconds: this.retryAfterSeconds }
        : {}),
    };
  }
}

export function normalizePhPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  if (digits.startsWith("63") && digits.length === 12) {
    return `0${digits.slice(2)}`;
  }
  if (digits.startsWith("0") && digits.length === 11 && digits[1] === "9") {
    return digits;
  }
  if (digits.length === 10 && digits.startsWith("9")) return `0${digits}`;
  return null;
}

/** True when another account already verified this normalized mobile. */
export async function isPhoneVerifiedByOtherAccount(
  // Service-role client from the OTP Edge Functions.
  // deno-lint-ignore no-explicit-any
  service: any,
  phone: string,
  userId: string,
): Promise<boolean> {
  const { data, error } = await service.rpc("is_phone_verified_by_other_user", {
    p_phone: phone,
    p_user_id: userId,
  });
  if (!error && typeof data === "boolean") return data;

  if (error) {
    console.warn("is_phone_verified_by_other_user rpc fallback", {
      message: error.message,
    });
  }

  const { data: row, error: queryError } = await service
    .from("users")
    .select("user_id")
    .eq("phone_number", phone)
    .eq("is_phone_verified", true)
    .neq("user_id", userId)
    .limit(1)
    .maybeSingle();
  if (queryError) throw queryError;
  return row != null;
}

/** Current user's verified canonical mobile, if any. */
export async function currentVerifiedPhoneForUser(
  // deno-lint-ignore no-explicit-any
  service: any,
  userId: string,
): Promise<string | null> {
  const { data, error } = await service
    .from("users")
    .select("phone_number, is_phone_verified")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data?.is_phone_verified) return null;
  return normalizePhPhone(String(data.phone_number ?? ""));
}

/** E.164 Philippines: +639XXXXXXXXX (UniSMS, FMCSMS). */
export function toE164Ph(raw: string): string {
  const local = normalizePhPhone(raw);
  if (!local) return raw.replace(/\D/g, "");
  return `+63${local.slice(1)}`;
}

/** @deprecated Use [toE164Ph]. */
export function toFmcsmsNumber(raw: string): string {
  return toE164Ph(raw);
}

export function maskPhMobile(raw: string): string {
  const local = normalizePhPhone(raw);
  if (!local) return "09••• ••••";
  return `${local.slice(0, 2)}••• ••••${local.slice(-3)}`;
}

export function randomOtp(): string {
  const bytes = new Uint8Array(6);
  let code = "";
  while (code.length < 6) {
    crypto.getRandomValues(bytes);
    for (const byte of bytes) {
      if (byte < 250) code += String(byte % 10);
      if (code.length === 6) break;
    }
  }
  return code;
}

export async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function clientIp(req: Request): string | null {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  if (forwarded) return forwarded;
  const real = req.headers.get("x-real-ip")?.trim();
  return real || null;
}

export function secondsUntil(fromMs: number, cooldownMs: number): number {
  return Math.max(1, Math.ceil((cooldownMs - fromMs) / 1000));
}

export type SmsSendResult = {
  accepted: boolean;
  status: number;
  code?: PhoneOtpErrorCode;
  userMessage?: string;
  referenceId?: string;
  deliveryStatus?: string;
};

/** @deprecated Use [SmsSendResult]. */
export type FmcsmsSendResult = SmsSendResult;

function providerText(
  parsed: Record<string, unknown> | null,
  raw: string,
): string {
  const message = parsed?.message;
  const failReason =
    message && typeof message === "object" && message !== null
      ? (message as Record<string, unknown>).fail_reason
      : null;
  const parts = [
    parsed?.error,
    parsed?.errors,
    parsed?.message,
    parsed?.detail,
    parsed?.status,
    failReason,
    raw,
  ]
    .filter((value) => typeof value === "string" && value.trim().length > 0)
    .join(" ");
  return parts.toLowerCase();
}

function isNetworkUnavailableText(text: string): boolean {
  return (
    /\bdito\b/.test(text) ||
    /\bsmart\b/.test(text) ||
    /\btnt\b/.test(text) ||
    /unsupported network|network not supported|network is not supported|not supported on this network|unsupported recipient|carrier|telco/.test(
      text,
    )
  );
}

export function classifyNetworkUnavailableFailure(): {
  code: PhoneOtpErrorCode;
  userMessage: string;
} {
  return {
    code: "network_unavailable",
    userMessage: NETWORK_UNAVAILABLE_MESSAGE,
  };
}

export function classifyFmcsmsFailure(
  status: number,
  parsed: Record<string, unknown> | null,
  raw: string,
): { code: PhoneOtpErrorCode; userMessage: string } {
  const text = providerText(parsed, raw);

  if (isNetworkUnavailableText(text)) {
    return classifyNetworkUnavailableFailure();
  }
  if (
    status === 401 ||
    status === 403 ||
    /unauthorized|invalid api key|revoked|missing api key/.test(text)
  ) {
    return {
      code: "provider_auth",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (/credit|balance|insufficient|no sms|out of/.test(text)) {
    return {
      code: "provider_credits",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (/invalid.*(number|phone|recipient)|unknown number|invalid to/.test(text)) {
    return {
      code: "invalid_phone",
      userMessage: "Enter a valid Philippine mobile number.",
    };
  }
  if (status >= 500) {
    return {
      code: "provider_error",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  return {
    code: "send_failed",
    userMessage: "We couldn't send the verification code right now. Please try again later.",
  };
}

export function classifyUnismsFailure(
  status: number,
  parsed: Record<string, unknown> | null,
  raw: string,
  failReason?: string | null,
): { code: PhoneOtpErrorCode; userMessage: string } {
  const text = [providerText(parsed, raw), failReason ?? ""]
    .join(" ")
    .toLowerCase();

  if (isNetworkUnavailableText(text)) {
    return classifyNetworkUnavailableFailure();
  }
  if (status === 401) {
    return {
      code: "provider_auth",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (status === 429) {
    return {
      code: "rate_limited",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (
    status === 422 ||
    status === 400 ||
    /invalid.*(number|phone|recipient)|unknown number|malformed/.test(text)
  ) {
    return {
      code: "invalid_phone",
      userMessage: "Enter a valid Philippine mobile number.",
    };
  }
  if (/credit|balance|insufficient|no sms|out of/.test(text)) {
    return {
      code: "provider_credits",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (status >= 500) {
    return {
      code: "provider_error",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  return {
    code: "send_failed",
    userMessage: "We couldn't send the verification code right now. Please try again later.",
  };
}

export function isFmcsmsAccepted(
  status: number,
  parsed: Record<string, unknown> | null,
): boolean {
  if (status < 200 || status >= 300) return false;
  if (!parsed) return true;
  if (parsed.success === false || parsed.status === "error") return false;
  if (parsed.error != null) return false;
  return true;
}

function unismsMessage(parsed: Record<string, unknown> | null): {
  status?: string;
  reference_id?: string;
  fail_reason?: string | null;
} | null {
  const msg = parsed?.message;
  if (!msg || typeof msg !== "object") return null;
  const m = msg as Record<string, unknown>;
  return {
    status: typeof m.status === "string" ? m.status : undefined,
    reference_id: typeof m.reference_id === "string" ? m.reference_id : undefined,
    fail_reason:
      m.fail_reason === null || typeof m.fail_reason === "string"
        ? (m.fail_reason as string | null)
        : undefined,
  };
}

export function isUnismsAccepted(
  status: number,
  parsed: Record<string, unknown> | null,
): boolean {
  if (status !== 201) return false;
  const message = unismsMessage(parsed);
  if (!message) return true;
  return message.status !== "failed";
}

function unismsBasicAuthHeader(secretKey: string): string {
  const token = btoa(`${secretKey}:`);
  return `Basic ${token}`;
}

export async function sendUnisms(
  phone: string,
  message: string,
): Promise<SmsSendResult> {
  const secretKey = Deno.env.get("UNISMS_API_SECRET_KEY") ?? "";
  const senderId = Deno.env.get("UNISMS_SENDER_ID") ?? "";
  const baseUrl = (Deno.env.get("UNISMS_API_URL") ?? DEFAULT_UNISMS_API_URL)
    .replace(/\/$/, "");

  if (!secretKey.trim()) {
    console.error("send-phone-otp unisms skipped: api secret missing");
    return {
      accepted: false,
      status: 0,
      code: "unavailable",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (!senderId.trim()) {
    console.error("send-phone-otp unisms skipped: sender id missing");
    return {
      accepted: false,
      status: 0,
      code: "unavailable",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }

  const payload = {
    recipient: toE164Ph(phone),
    content: message,
    sender_id: senderId,
    metadata: { purpose: "phone_otp" },
  };

  console.log("send-phone-otp unisms attempted", {
    endpoint: `${baseUrl}/sms`,
    to: maskPhMobile(phone),
  });

  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), SMS_PROVIDER_TIMEOUT_MS);

  try {
    const response = await fetch(`${baseUrl}/sms`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: unismsBasicAuthHeader(secretKey),
      },
      body: JSON.stringify(payload),
      signal: abort.signal,
    });

    const text = await response.text();
    let parsed: Record<string, unknown> | null = null;
    try {
      parsed = JSON.parse(text) as Record<string, unknown>;
    } catch {
      parsed = null;
    }

    const messageObj = unismsMessage(parsed);
    const accepted = isUnismsAccepted(response.status, parsed);

    console.log("send-phone-otp unisms response", {
      status: response.status,
      accepted,
      reference_id: messageObj?.reference_id,
      delivery_status: messageObj?.status,
      fail_reason: messageObj?.fail_reason,
    });

    if (accepted) {
      return {
        accepted: true,
        status: response.status,
        referenceId: messageObj?.reference_id,
        deliveryStatus: messageObj?.status,
      };
    }

    const classified = classifyUnismsFailure(
      response.status,
      parsed,
      text,
      messageObj?.fail_reason,
    );
    return {
      accepted: false,
      status: response.status,
      code: classified.code,
      userMessage: classified.userMessage,
      referenceId: messageObj?.reference_id,
      deliveryStatus: messageObj?.status,
    };
  } catch (error) {
    const timedOut =
      error instanceof DOMException && error.name === "AbortError";
    console.error("send-phone-otp unisms transport failed", {
      timeout: timedOut,
    });
    return {
      accepted: false,
      status: 0,
      code: timedOut ? "provider_timeout" : "provider_error",
      userMessage: timedOut
        ? "The SMS service took too long to respond. Please try again."
        : "We couldn't send the verification code right now. Please try again later.",
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function sendFmcsms(
  phone: string,
  message: string,
): Promise<SmsSendResult> {
  const apiKey = Deno.env.get("FMCSMS_API_KEY") ?? "";
  const endpoint = Deno.env.get("FMCSMS_API_URL") ?? DEFAULT_FMCSMS_URL;
  const senderName = Deno.env.get("FMCSMS_SENDER") ?? "ThriftLine";
  const fromNumber = Deno.env.get("FMCSMS_FROM_NUMBER") ?? "";

  if (!apiKey.trim()) {
    console.error("send-phone-otp fmcsms skipped: api key missing");
    return {
      accepted: false,
      status: 0,
      code: "unavailable",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }
  if (!fromNumber.trim()) {
    console.error("send-phone-otp fmcsms skipped: from number missing");
    return {
      accepted: false,
      status: 0,
      code: "unavailable",
      userMessage:
        "We couldn't send the verification code right now. Please try again later.",
    };
  }

  const payload = {
    SenderName: senderName,
    ToNumber: toE164Ph(phone),
    MessageBody: message,
    FromNumber: toE164Ph(fromNumber),
  };

  console.log("send-phone-otp fmcsms attempted", {
    endpoint,
    to: maskPhMobile(phone),
  });

  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), SMS_PROVIDER_TIMEOUT_MS);

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-Key": apiKey,
      },
      body: JSON.stringify(payload),
      signal: abort.signal,
    });

    const text = await response.text();
    let parsed: Record<string, unknown> | null = null;
    try {
      parsed = JSON.parse(text) as Record<string, unknown>;
    } catch {
      parsed = null;
    }

    const accepted = isFmcsmsAccepted(response.status, parsed);
    console.log("send-phone-otp fmcsms response", {
      status: response.status,
      accepted,
    });

    if (accepted) {
      return { accepted: true, status: response.status };
    }

    const classified = classifyFmcsmsFailure(response.status, parsed, text);
    return {
      accepted: false,
      status: response.status,
      code: classified.code,
      userMessage: classified.userMessage,
    };
  } catch (error) {
    const timedOut =
      error instanceof DOMException && error.name === "AbortError";
    console.error("send-phone-otp fmcsms transport failed", {
      timeout: timedOut,
    });
    return {
      accepted: false,
      status: 0,
      code: timedOut ? "provider_timeout" : "provider_error",
      userMessage: timedOut
        ? "The SMS service took too long to respond. Please try again."
        : "We couldn't send the verification code right now. Please try again later.",
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function sendSms(
  phone: string,
  message: string,
): Promise<SmsSendResult> {
  const provider = (Deno.env.get("SMS_PROVIDER") ?? "fmcsms").trim().toLowerCase();
  switch (provider) {
    case "unisms":
      return sendUnisms(phone, message);
    case "fmcsms":
      return sendFmcsms(phone, message);
    default:
      console.error("send-phone-otp unknown SMS_PROVIDER", { provider });
      return {
        accepted: false,
        status: 0,
        code: "unavailable",
        userMessage:
          "We couldn't send the verification code right now. Please try again later.",
      };
  }
}

export function buildPhoneOtpSmsMessage(otp: string): string {
  return `Your ThriftLine verification code is ${otp}. This code expires in 5 minutes. Do not share this code with anyone.`;
}
