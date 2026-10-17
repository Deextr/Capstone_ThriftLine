import { basicAuthHeader } from "./paymongo.ts";

export const PAYMONGO_API_BASE = "https://api.paymongo.com/v1";
/** PayMongo documents a separate host for QR Ph refunds (returns a transfer link). */
export const PAYMONGO_QRPH_REFUNDS_BASE = "https://refunds-api.paymongo.com/v1";

export type RefundSnapshot = {
  id: string;
  status: string;
  amountCentavos: number | null;
  paymentId: string | null;
  transferLink: string | null;
  transferLinkExpiresAt: string | null;
};

export type RefundOutcome =
  | {
    kind: "accepted";
    action: "create" | "adopt";
    httpStatus: number | null;
    refund: RefundSnapshot;
  }
  | { kind: "rejected"; httpStatus: number; errorCode: string }
  | { kind: "unknown"; httpStatus: number | null; errorCode: string };

type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

type Json = Record<string, unknown>;

function asRecord(value: unknown): Json | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Json;
  }
  return null;
}

function readString(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  return null;
}

function readAmount(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.round(parsed);
  }
  return null;
}

function readTimestamp(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    const ms = value < 1e12 ? value * 1000 : value;
    return new Date(ms).toISOString();
  }
  const text = readString(value);
  if (!text) return null;
  if (/^\d+$/.test(text)) return readTimestamp(Number(text));
  const parsed = Date.parse(text);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}

function readHttpsUrl(value: unknown): string | null {
  const text = readString(value);
  if (!text) return null;
  try {
    const url = new URL(text);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

export function refundsBaseFor(channel: string | null | undefined): string {
  return (channel ?? "").trim().toLowerCase() === "qrph"
    ? PAYMONGO_QRPH_REFUNDS_BASE
    : PAYMONGO_API_BASE;
}

export function paymongoErrorCode(payload: unknown): string {
  const root = asRecord(payload);
  const errors = root?.errors;
  if (!Array.isArray(errors) || errors.length === 0) return "";
  return (readString(asRecord(errors[0])?.code) ?? "").toLowerCase();
}

/** Parses a PayMongo refund resource (wrapped in `data` or bare). */
export function parseRefundResource(raw: unknown): RefundSnapshot | null {
  const root = asRecord(raw);
  if (!root) return null;
  const resource = asRecord(root.data) && readString(asRecord(root.data)?.id)
    ? asRecord(root.data)!
    : root;
  const id = readString(resource.id);
  if (!id || !id.startsWith("ref_")) return null;
  const attrs = asRecord(resource.attributes) ?? resource;
  return {
    id,
    status: (readString(attrs.status) ?? "").toLowerCase(),
    amountCentavos: readAmount(attrs.amount),
    paymentId: readString(attrs.payment_id),
    transferLink: readHttpsUrl(attrs.transfer_link),
    transferLinkExpiresAt: readTimestamp(
      attrs.transfer_link_expires_at ??
        attrs.transfer_link_expiry ??
        attrs.expires_at,
    ),
  };
}

/** Refunds from a refund list (`data: [...]`) or a payment resource (`attributes.refunds`). */
export function parseRefundList(payload: unknown): RefundSnapshot[] {
  const root = asRecord(payload);
  if (!root) return [];
  let items: unknown[] = [];
  if (Array.isArray(root.data)) {
    items = root.data;
  } else {
    const data = asRecord(root.data) ?? root;
    const attrs = asRecord(data.attributes);
    const refunds = attrs?.refunds;
    if (Array.isArray(refunds)) items = refunds;
    else if (Array.isArray(asRecord(refunds)?.data)) {
      items = asRecord(refunds)!.data as unknown[];
    }
  }
  return items
    .map((item) => parseRefundResource(item))
    .filter((item): item is RefundSnapshot => item != null);
}

/** A refund that may still return money. Only `failed` is terminal without payout. */
export function liveRefund(refunds: RefundSnapshot[]): RefundSnapshot | null {
  return refunds.find((r) => r.status !== "failed") ?? null;
}

export function classifyCreateResponse(
  httpStatus: number,
  payload: unknown,
): RefundOutcome {
  if (httpStatus >= 200 && httpStatus < 300) {
    const refund = parseRefundResource(payload);
    if (!refund) {
      return { kind: "unknown", httpStatus, errorCode: "missing_refund_id" };
    }
    return { kind: "accepted", action: "create", httpStatus, refund };
  }
  const code = paymongoErrorCode(payload);
  if (
    httpStatus >= 500 || httpStatus === 429 || httpStatus === 408 ||
    httpStatus === 401 || httpStatus === 403
  ) {
    return {
      kind: "unknown",
      httpStatus,
      errorCode: code || `http_${httpStatus}`,
    };
  }
  return { kind: "rejected", httpStatus, errorCode: code || `http_${httpStatus}` };
}

async function readJson(res: Response): Promise<unknown> {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function authHeaders(secret: string): HeadersInit {
  return {
    Authorization: basicAuthHeader(secret),
    Accept: "application/json",
  };
}

/** Lists refunds already attached to a PayMongo payment. */
export async function lookupExistingRefunds(opts: {
  secret: string;
  paymentId: string;
  channel: string | null;
  fetchImpl?: FetchLike;
}): Promise<{ ok: true; refunds: RefundSnapshot[] } | { ok: false }> {
  const doFetch = opts.fetchImpl ?? fetch;
  const id = encodeURIComponent(opts.paymentId);
  const attempts = [
    `${PAYMONGO_API_BASE}/payments/${id}`,
    `${refundsBaseFor(opts.channel)}/refunds?payment_id=${id}`,
  ];
  for (const url of attempts) {
    try {
      const res = await doFetch(url, { headers: authHeaders(opts.secret) });
      if (!res.ok) {
        await res.body?.cancel();
        continue;
      }
      return { ok: true, refunds: parseRefundList(await readJson(res)) };
    } catch {
      continue;
    }
  }
  return { ok: false };
}

export async function retrieveRefund(opts: {
  secret: string;
  refundId: string;
  channel: string | null;
  fetchImpl?: FetchLike;
}): Promise<{ ok: true; refund: RefundSnapshot } | { ok: false; httpStatus: number | null }> {
  const doFetch = opts.fetchImpl ?? fetch;
  const id = encodeURIComponent(opts.refundId);
  const primary = refundsBaseFor(opts.channel);
  const bases = primary === PAYMONGO_API_BASE
    ? [PAYMONGO_API_BASE]
    : [primary, PAYMONGO_API_BASE];
  let lastStatus: number | null = null;
  for (const base of bases) {
    try {
      const res = await doFetch(`${base}/refunds/${id}`, {
        headers: authHeaders(opts.secret),
      });
      lastStatus = res.status;
      if (!res.ok) {
        await res.body?.cancel();
        continue;
      }
      const refund = parseRefundResource(await readJson(res));
      if (refund) return { ok: true, refund };
    } catch {
      continue;
    }
  }
  return { ok: false, httpStatus: lastStatus };
}

/**
 * Creates a refund only after confirming PayMongo has no live refund for the
 * payment. An existing non-failed refund is adopted instead of duplicated.
 */
export async function createOrAdoptRefund(opts: {
  secret: string;
  paymentId: string;
  channel: string | null;
  amountCentavos: number;
  idempotencyKey: string;
  notes: string;
  fetchImpl?: FetchLike;
}): Promise<RefundOutcome> {
  const doFetch = opts.fetchImpl ?? fetch;
  const existing = await lookupExistingRefunds(opts);
  if (!existing.ok) {
    return { kind: "unknown", httpStatus: null, errorCode: "lookup_failed" };
  }
  const live = liveRefund(existing.refunds);
  if (live) {
    return { kind: "accepted", action: "adopt", httpStatus: null, refund: live };
  }

  let res: Response;
  try {
    res = await doFetch(`${refundsBaseFor(opts.channel)}/refunds`, {
      method: "POST",
      headers: {
        ...authHeaders(opts.secret),
        "Content-Type": "application/json",
        "Idempotency-Key": opts.idempotencyKey,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            amount: opts.amountCentavos,
            payment_id: opts.paymentId,
            reason: "others",
            notes: opts.notes.slice(0, 250),
          },
        },
      }),
    });
  } catch {
    return { kind: "unknown", httpStatus: null, errorCode: "network_error" };
  }
  return classifyCreateResponse(res.status, await readJson(res));
}

export type RefundWebhookUpdate = {
  refundId: string;
  status: string;
  transferLink: string | null;
  transferLinkExpiresAt: string | null;
};

export const REFUND_WEBHOOK_EVENTS = new Set([
  "payment.refunded",
  "payment.refund.updated",
]);

export function webhookEventType(raw: unknown): string {
  const root = asRecord(raw);
  const data = asRecord(root?.data);
  const attrs = asRecord(data?.attributes);
  return (
    readString(attrs?.type) ??
    readString(data?.type) ??
    readString(root?.type) ??
    ""
  ).toLowerCase();
}

/** Refund updates carried by `payment.refunded` / `payment.refund.updated`. */
export function refundUpdatesFromWebhook(raw: unknown): RefundWebhookUpdate[] {
  const root = asRecord(raw);
  const data = asRecord(root?.data);
  const attrs = asRecord(data?.attributes);
  const resource = attrs?.data ?? data?.data;
  const direct = parseRefundResource(resource);
  const refunds = direct ? [direct] : parseRefundList({ data: resource });
  return refunds.map((r) => ({
    refundId: r.id,
    status: r.status,
    transferLink: r.transferLink,
    transferLinkExpiresAt: r.transferLinkExpiresAt,
  }));
}
