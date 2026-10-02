export const DITO_UNAVAILABLE_MESSAGE =
  "SMS verification for DITO numbers is currently unavailable due to provider maintenance. Please use a supported mobile network or try again later.";

export const RESEND_COOLDOWN_MS = 60_000;
export const OTP_TTL_MS = 5 * 60_000;
export const MAX_VERIFY_ATTEMPTS = 5;
export const MAX_SENDS_PER_USER_HOUR = 5;
export const MAX_SENDS_PER_PHONE_HOUR = 5;
export const MAX_SENDS_PER_IP_HOUR = 10;
export const FMCSMS_TIMEOUT_MS = 15_000;

export const DEFAULT_FMCSMS_URL =
  "https://www.fortmed.org/web/FMCSMS/api/messages.php";

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
  | "dito_unavailable"
  | "provider_auth"
  | "provider_credits"
  | "provider_error"
  | "provider_timeout"
  | "send_failed"
  | "unavailable";

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

/** FMCSMS dashboard sample uses E.164: +639XXXXXXXXX */
export function toFmcsmsNumber(raw: string): string {
  const local = normalizePhPhone(raw);
  if (!local) return raw.replace(/\D/g, "");
  return `+63${local.slice(1)}`;
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

export type FmcsmsSendResult = {
  accepted: boolean;
  status: number;
  code?: PhoneOtpErrorCode;
  userMessage?: string;
};

function providerText(
  parsed: Record<string, unknown> | null,
  raw: string,
): string {
  const parts = [
    parsed?.error,
    parsed?.message,
    parsed?.detail,
    parsed?.status,
    raw,
  ]
    .filter((value) => typeof value === "string" && value.trim().length > 0)
    .join(" ");
  return parts.toLowerCase();
}

export function classifyFmcsmsFailure(
  status: number,
  parsed: Record<string, unknown> | null,
  raw: string,
): { code: PhoneOtpErrorCode; userMessage: string } {
  const text = providerText(parsed, raw);

  if (/\bdito\b/.test(text)) {
    return { code: "dito_unavailable", userMessage: DITO_UNAVAILABLE_MESSAGE };
  }
  if (
    /unsupported network|network not supported|network is not supported|not supported on this network/.test(
      text,
    )
  ) {
    return { code: "dito_unavailable", userMessage: DITO_UNAVAILABLE_MESSAGE };
  }
  if (
    status === 401 ||
    status === 403 ||
    /unauthorized|invalid api key|revoked|missing api key/.test(text)
  ) {
    return {
      code: "provider_auth",
      userMessage:
        "SMS verification is temporarily unavailable. Please try again later.",
    };
  }
  if (/credit|balance|insufficient|no sms|out of/.test(text)) {
    return {
      code: "provider_credits",
      userMessage:
        "SMS verification is temporarily unavailable. Please try again later.",
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
        "SMS verification is temporarily unavailable. Please try again later.",
    };
  }
  return {
    code: "send_failed",
    userMessage: "We could not send the verification code. Please try again.",
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

export async function sendFmcsms(
  phone: string,
  message: string,
): Promise<FmcsmsSendResult> {
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
        "SMS verification is temporarily unavailable. Please try again later.",
    };
  }
  if (!fromNumber.trim()) {
    console.error("send-phone-otp fmcsms skipped: from number missing");
    return {
      accepted: false,
      status: 0,
      code: "unavailable",
      userMessage:
        "SMS verification is temporarily unavailable. Please try again later.",
    };
  }

  const payload = {
    SenderName: senderName,
    ToNumber: toFmcsmsNumber(phone),
    MessageBody: message,
    FromNumber: toFmcsmsNumber(fromNumber),
  };

  console.log("send-phone-otp fmcsms attempted", {
    endpoint,
    to: maskPhMobile(phone),
  });

  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), FMCSMS_TIMEOUT_MS);

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
        : "SMS verification is temporarily unavailable. Please try again later.",
    };
  } finally {
    clearTimeout(timer);
  }
}
