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

const PAID_STATUSES = new Set(["paid", "succeeded"]);
const FAILED_STATUSES = new Set(["failed", "cancelled", "canceled"]);
const EXPIRED_STATUSES = new Set(["expired"]);
const IN_FLIGHT_STATUSES = new Set([
  "pending",
  "processing",
  "awaiting_next_action",
  "awaiting_payment_method",
  "unpaid",
]);

export type CheckoutSessionOutcome = {
  outcome: "paid" | "expired" | "failed" | "pending";
  sessionId: string | null;
  paymentId: string | null;
  amountCentavos: number | null;
  currency: string;
  metadataOrderId: string | null;
  sessionStatus: string;
};

function unwrapResource(
  raw: unknown,
): Record<string, unknown> | null {
  const value = asRecord(raw);
  if (!value) return null;
  return asRecord(value.data) ?? value;
}

function resourceAttrs(
  raw: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!raw) return null;
  return asRecord(raw.attributes) ?? raw;
}

function asPaymentList(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  const wrapped = asRecord(value);
  if (wrapped && Array.isArray(wrapped.data)) return wrapped.data;
  return [];
}

function collectPaymentRecords(
  attrs: Record<string, unknown> | null,
): unknown[] {
  const records: unknown[] = [];
  if (!attrs) return records;
  records.push(...asPaymentList(attrs.payments));
  const intent = unwrapResource(attrs.payment_intent);
  const intentAttrs = resourceAttrs(intent);
  if (intentAttrs) records.push(...asPaymentList(intentAttrs.payments));
  return records;
}

export function paymentIntentIdFromCheckout(
  payload: unknown,
): string | null {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? root;
  const attrs = asRecord(data?.attributes);
  const raw = attrs?.payment_intent;
  if (typeof raw === "string" && raw.startsWith("pi_")) return raw;
  const intent = unwrapResource(raw);
  const id = readString(intent?.id);
  return id?.startsWith("pi_") ? id : null;
}

function intentStatusOf(attrs: Record<string, unknown> | null): string {
  const intent = unwrapResource(attrs?.payment_intent);
  const intentAttrs = resourceAttrs(intent);
  return (readString(intentAttrs?.status) ?? "").toLowerCase();
}

function intentAmountOf(attrs: Record<string, unknown> | null): number | null {
  const intent = unwrapResource(attrs?.payment_intent);
  const intentAttrs = resourceAttrs(intent);
  return readAmount(intentAttrs?.amount);
}

/** PayMongo resets the intent to awaiting_payment_method after a failed attempt. */
function intentHasRecordedFailure(attrs: Record<string, unknown> | null): boolean {
  const intent = unwrapResource(attrs?.payment_intent);
  const intentAttrs = resourceAttrs(intent);
  const err = intentAttrs?.last_payment_error;
  return err != null && typeof err === "object";
}

function paymentRecordStatus(raw: unknown): string {
  const resource = unwrapResource(raw);
  const attrs = resourceAttrs(resource);
  return (readString(attrs?.status) ?? "").toLowerCase();
}

function paymentRecordId(raw: unknown): string | null {
  const resource = unwrapResource(raw);
  const id = readString(resource?.id);
  if (id?.startsWith("pay_")) return id;
  const attrs = resourceAttrs(resource);
  const attrId = readString(attrs?.id);
  return attrId?.startsWith("pay_") ? attrId : null;
}

function paymentRecordAmount(raw: unknown): number | null {
  const attrs = resourceAttrs(unwrapResource(raw));
  return readAmount(attrs?.amount);
}

function paymentRecordCurrency(raw: unknown): string | null {
  const attrs = resourceAttrs(unwrapResource(raw));
  return readString(attrs?.currency);
}

/**
 * PayMongo checkout sessions are `active` or `expired`. Payment success lives
 * on `payments[].status` / `payment_intent.status`, not the session status.
 * `inactive` means the session can no longer accept payment — it is not
 * proof of expiry or failure, and a paid payment may already exist.
 */
export function checkoutSessionOutcome(
  payload: unknown,
): CheckoutSessionOutcome {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? root;
  const attrs = asRecord(data?.attributes);
  const sessionId = readString(data?.id)?.startsWith("cs_")
    ? readString(data?.id)
    : null;
  const sessionStatus = (readString(attrs?.status) ?? "").toLowerCase();
  const metadata = asRecord(attrs?.metadata);
  const metadataOrderId = readUuid(metadata?.order_id);
  const payments = collectPaymentRecords(attrs);
  const intentStatus = intentStatusOf(attrs);
  const paidPayment = payments.find((item) =>
    PAID_STATUSES.has(paymentRecordStatus(item))
  );
  const currency = (
    (paidPayment ? paymentRecordCurrency(paidPayment) : null) ??
    readString(resourceAttrs(unwrapResource(attrs?.payment_intent))?.currency) ??
    readString(attrs?.currency) ??
    "PHP"
  ).toUpperCase();
  const amountCentavos = (paidPayment
    ? paymentRecordAmount(paidPayment)
    : null) ??
    intentAmountOf(attrs) ??
    readAmount(attrs?.amount) ??
    lineItemsAmount(attrs);
  const paymentId = (paidPayment ? paymentRecordId(paidPayment) : null) ??
    payments.map(paymentRecordId).find((id) => id != null) ??
    null;

  const base = {
    sessionId,
    paymentId,
    amountCentavos,
    currency,
    metadataOrderId,
    sessionStatus,
  };

  if (
    paidPayment ||
    PAID_STATUSES.has(intentStatus) ||
    PAID_STATUSES.has(sessionStatus)
  ) {
    return { ...base, outcome: "paid" };
  }

  const sessionExpired = sessionStatus === "expired";
  const hasFailed = FAILED_STATUSES.has(intentStatus) ||
    payments.some((item) => FAILED_STATUSES.has(paymentRecordStatus(item))) ||
    intentHasRecordedFailure(attrs);
  const hasExpiredPayment = EXPIRED_STATUSES.has(intentStatus) ||
    payments.some((item) => EXPIRED_STATUSES.has(paymentRecordStatus(item)));

  const inFlight = !hasFailed && !hasExpiredPayment &&
    (IN_FLIGHT_STATUSES.has(intentStatus) ||
      payments.some((item) => IN_FLIGHT_STATUSES.has(paymentRecordStatus(item))));
  if (inFlight) {
    return { ...base, outcome: "pending" };
  }

  // Active sessions stay retryable in PayMongo, but a terminal failed/expired
  // attempt must still be reported for merchant reconciliation.
  if (!sessionExpired && sessionStatus !== "inactive") {
    if (hasFailed) {
      const failedPayment = payments.find((item) =>
        FAILED_STATUSES.has(paymentRecordStatus(item))
      );
      return {
        ...base,
        outcome: "failed",
        paymentId: paymentId ?? paymentRecordId(failedPayment ?? null),
      };
    }
    if (hasExpiredPayment || sessionStatus === "expired") {
      return { ...base, outcome: "expired" };
    }
    return { ...base, outcome: "pending" };
  }

  if (sessionExpired && (hasExpiredPayment || payments.length === 0)) {
    return { ...base, outcome: "expired" };
  }
  if (hasFailed) {
    return { ...base, outcome: "failed" };
  }
  if (sessionExpired || hasExpiredPayment) {
    return { ...base, outcome: "expired" };
  }

  // `inactive` with no payments yet is a race after authorization, not expiry.
  return { ...base, outcome: "pending" };
}

/**
 * After the buyer returns from hosted PayMongo checkout, a failed attempt may
 * still leave the session `active` (retryable in PayMongo). ThriftLine must
 * still release inventory once the payment record is terminal failed.
 */
export function reconcileHostedCheckoutOutcome(
  parsed: CheckoutSessionOutcome,
  sessionPayload: unknown,
): CheckoutSessionOutcome {
  if (
    parsed.outcome === "paid" ||
    parsed.outcome === "expired" ||
    parsed.outcome === "failed"
  ) {
    return parsed;
  }

  const root = asRecord(sessionPayload);
  const data = asRecord(root?.data) ?? root;
  const attrs = asRecord(data?.attributes);
  const payments = collectPaymentRecords(attrs);
  const intentStatus = intentStatusOf(attrs);
  const sessionStatus = (readString(attrs?.status) ?? parsed.sessionStatus)
    .toLowerCase();

  const hasPaid = PAID_STATUSES.has(intentStatus) ||
    payments.some((item) => PAID_STATUSES.has(paymentRecordStatus(item)));
  if (hasPaid) {
    return { ...parsed, outcome: "paid" };
  }

  const inFlight = IN_FLIGHT_STATUSES.has(intentStatus) ||
    payments.some((item) => IN_FLIGHT_STATUSES.has(paymentRecordStatus(item)));
  if (inFlight) {
    return parsed;
  }

  const hasFailed = FAILED_STATUSES.has(intentStatus) ||
    payments.some((item) => FAILED_STATUSES.has(paymentRecordStatus(item))) ||
    intentHasRecordedFailure(attrs);
  if (hasFailed) {
    const failedPayment = payments.find((item) =>
      FAILED_STATUSES.has(paymentRecordStatus(item))
    );
    return {
      ...parsed,
      outcome: "failed",
      paymentId: parsed.paymentId ?? paymentRecordId(failedPayment ?? null),
    };
  }

  const hasExpired = EXPIRED_STATUSES.has(intentStatus) ||
    payments.some((item) => EXPIRED_STATUSES.has(paymentRecordStatus(item)));
  if (hasExpired || sessionStatus === "expired") {
    return { ...parsed, outcome: "expired" };
  }

  return parsed;
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
