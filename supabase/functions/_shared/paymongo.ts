const encoder = new TextEncoder();

export async function hmacSha256Hex(
  secret: string,
  payload: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

export function parsePaymongoSignatureHeader(
  header: string | null,
): { t: string; te: string; li: string } | null {
  if (!header) return null;
  const parts: Record<string, string> = { t: "", te: "", li: "" };
  for (const piece of header.split(",")) {
    const idx = piece.indexOf("=");
    if (idx <= 0) continue;
    const key = piece.slice(0, idx).trim();
    const value = piece.slice(idx + 1).trim();
    if (key === "t" || key === "te" || key === "li") parts[key] = value;
  }
  if (!parts.t) return null;
  return { t: parts.t, te: parts.te, li: parts.li };
}

export async function verifyPaymongoSignature(opts: {
  rawBody: string;
  header: string | null;
  secret: string;
}): Promise<boolean> {
  const parsed = parsePaymongoSignatureHeader(opts.header);
  if (!parsed) return false;
  const secret = opts.secret.trim();
  if (!secret) return false;
  const signedWithTimestamp = await hmacSha256Hex(
    secret,
    `${parsed.t}.${opts.rawBody}`,
  );
  const signedBodyOnly = await hmacSha256Hex(secret, opts.rawBody);
  const te = parsed.te.toLowerCase();
  const li = parsed.li.toLowerCase();
  const candidates = [signedWithTimestamp.toLowerCase(), signedBodyOnly.toLowerCase()];
  return candidates.some(
    (got) =>
      (te.length > 0 && timingSafeEqual(te, got)) ||
      (li.length > 0 && timingSafeEqual(li, got)),
  );
}

export type PaymongoEvent = {
  eventKey: string;
  eventType: string;
  sessionId: string | null;
  paymentId: string | null;
  amountCentavos: number | null;
  currency: string;
  metadataOrderId: string | null;
};

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function readString(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  return null;
}

function readUuid(value: unknown): string | null {
  const text = readString(value);
  if (!text) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(text)
    ? text
    : null;
}

function firstPayment(attrs: Record<string, unknown> | null): Record<string, unknown> | null {
  if (!attrs) return null;
  const payments = attrs.payments;
  if (!Array.isArray(payments) || payments.length === 0) return null;
  const first = asRecord(payments[0]);
  if (!first) return null;
  return asRecord(first.data) ?? first;
}

function readAmount(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.round(parsed);
  }
  return null;
}

function lineItemsAmount(attrs: Record<string, unknown> | null): number | null {
  if (!attrs || !Array.isArray(attrs.line_items)) return null;
  let total = 0;
  let found = false;
  for (const raw of attrs.line_items) {
    const item = asRecord(raw);
    if (!item) continue;
    const amount = readAmount(item.amount);
    if (amount == null) continue;
    const qty = readAmount(item.quantity) ?? 1;
    total += amount * qty;
    found = true;
  }
  return found ? total : null;
}

export function parsePaymongoEvent(raw: unknown): PaymongoEvent | null {
  const root = asRecord(raw);
  if (!root) return null;

  const data = asRecord(root.data);
  const attributesWrapper = asRecord(data?.attributes);

  const attrType = readString(attributesWrapper?.type);
  const dataType = readString(data?.type);
  const eventType =
    attrType && attrType.includes(".")
      ? attrType
      : dataType && dataType.includes(".")
      ? dataType
      : attrType ?? dataType ?? readString(root.type) ?? "";

  const sessionFromNew = asRecord(data?.data);
  const sessionFromClassic = asRecord(attributesWrapper?.data);
  const session =
    (sessionFromNew && (readString(sessionFromNew.id)?.startsWith("cs_") ||
      sessionFromNew.type === "checkout_session"))
      ? sessionFromNew
      : sessionFromClassic &&
          (readString(sessionFromClassic.id)?.startsWith("cs_") ||
            sessionFromClassic.type === "checkout_session")
      ? sessionFromClassic
      : sessionFromNew ?? sessionFromClassic;

  const sessionAttrs = asRecord(session?.attributes);
  const paymentObj = firstPayment(sessionAttrs) ?? asRecord(session);
  const paymentAttrs = asRecord(paymentObj?.attributes) ?? paymentObj;

  const sessionId =
    readString(session?.id)?.startsWith("cs_")
      ? readString(session?.id)
      : readString(sessionAttrs?.checkout_session_id) ??
        readString(paymentAttrs?.checkout_session_id);

  const paymentId =
    readString(paymentObj?.id)?.startsWith("pay_")
      ? readString(paymentObj?.id)
      : readString(paymentAttrs?.id)?.startsWith("pay_")
      ? readString(paymentAttrs?.id)
      : null;

  const amountCentavos =
    readAmount(paymentAttrs?.amount) ??
    readAmount(sessionAttrs?.amount) ??
    lineItemsAmount(sessionAttrs);

  const currency =
    readString(paymentAttrs?.currency) ??
    readString(sessionAttrs?.currency) ??
    "PHP";

  const metadata = asRecord(sessionAttrs?.metadata) ?? asRecord(paymentAttrs?.metadata);
  const metadataOrderId = readUuid(metadata?.order_id);

  const eventId =
    readString(data?.id) ??
    readString(root.id) ??
    `${eventType}:${sessionId ?? "none"}:${paymentId ?? "none"}`;

  if (!eventType) return null;

  return {
    eventKey: eventId,
    eventType,
    sessionId: sessionId,
    paymentId,
    amountCentavos,
    currency: currency.toUpperCase(),
    metadataOrderId,
  };
}

export function isPaymongoCheckoutUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return (
      parsed.protocol === "https:" &&
      (parsed.hostname === "checkout.paymongo.com" ||
        parsed.hostname.endsWith(".paymongo.com"))
    );
  } catch {
    return false;
  }
}

export function basicAuthHeader(secretKey: string): string {
  return `Basic ${btoa(`${secretKey.trim()}:`)}`;
}
