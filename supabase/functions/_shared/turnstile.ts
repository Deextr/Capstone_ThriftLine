const SITEVERIFY_URL =
  "https://challenges.cloudflare.com/turnstile/v0/siteverify";

export type TurnstileVerifyResult = {
  success: boolean;
  "error-codes"?: string[];
  action?: string;
  hostname?: string;
};

export type TurnstileVerifyOptions = {
  expectedAction?: string;
  timeoutMs?: number;
};

/** Validates a Turnstile token with Cloudflare Siteverify. Secret stays server-side. */
export async function verifyTurnstileToken(
  token: string,
  remoteIp: string | null,
  options: TurnstileVerifyOptions = {},
): Promise<TurnstileVerifyResult> {
  const secret = (Deno.env.get("TURNSTILE_SECRET_KEY") ?? "").trim();
  if (!secret) {
    console.error("TURNSTILE_SECRET_KEY is not configured");
    return { success: false, "error-codes": ["internal-error"] };
  }

  const trimmed = token.trim();
  if (!trimmed || trimmed.length > 2048) {
    return { success: false, "error-codes": ["invalid-input-response"] };
  }

  const timeoutMs = options.timeoutMs ?? 10_000;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const form = new FormData();
    form.append("secret", secret);
    form.append("response", trimmed);
    if (remoteIp) form.append("remoteip", remoteIp);

    const response = await fetch(SITEVERIFY_URL, {
      method: "POST",
      body: form,
      signal: controller.signal,
    });

    const result = (await response.json()) as TurnstileVerifyResult;
    if (!result.success) {
      return result;
    }

    const expectedAction = options.expectedAction?.trim();
    if (expectedAction && result.action !== expectedAction) {
      return { success: false, "error-codes": ["action_mismatch"] };
    }

    return result;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return { success: false, "error-codes": ["internal-error"] };
    }
    console.error("Turnstile siteverify request failed");
    return { success: false, "error-codes": ["internal-error"] };
  } finally {
    clearTimeout(timeoutId);
  }
}

export function turnstileUserMessage(codes: string[] | undefined): string {
  const list = codes ?? [];
  if (list.includes("timeout-or-duplicate")) {
    return "Verification expired. Complete the check again and try once more.";
  }
  if (list.includes("internal-error")) {
    return "Verification is temporarily unavailable. Please try again.";
  }
  return "Human verification failed. Please try again.";
}
