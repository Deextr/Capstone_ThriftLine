/// Hashing for trusted-device tokens. The raw token never belongs in the
/// database or in logs. Keep this prefix identical everywhere it is used.

export function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

export function trustedPlatform(value: unknown): string | null {
  if (value === "android" || value === "ios" || value === "other") return value;
  return null;
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashDeviceToken(
  userId: string,
  token: string,
): Promise<string> {
  const pepper = Deno.env.get("OTP_PEPPER") ?? "";
  return sha256Hex(`${pepper}:trusted-device:${userId}:${token}`);
}
