/** Decode selected GoTrue JWT payload fields without verifying the signature.
 *  Only use on tokens just issued by GoTrue over TLS from our own backend. */

export function decodeJwtPayload(
  accessToken: string,
): Record<string, unknown> | null {
  const parts = accessToken.split(".");
  if (parts.length < 2) return null;
  try {
    let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = payload.length % 4;
    if (pad !== 0) payload += "=".repeat(4 - pad);
    const json = atob(payload);
    const parsed = JSON.parse(json);
    return parsed && typeof parsed === "object"
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export function sessionIdFromAccessToken(accessToken: string): string | null {
  const payload = decodeJwtPayload(accessToken);
  if (!payload) return null;
  const raw = payload.session_id ?? payload.sessionId;
  if (typeof raw !== "string" || raw.trim().length === 0) return null;
  return raw.trim();
}
