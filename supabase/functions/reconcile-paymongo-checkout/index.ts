import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import {
  basicAuthHeader,
  checkoutSessionOutcome,
  reconcileHostedCheckoutOutcome,
  paymentIntentIdFromCheckout,
  type CheckoutSessionOutcome,
} from "../_shared/paymongo.ts";

const PAYMONGO_API = "https://api.paymongo.com";

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function betterOutcome(
  current: CheckoutSessionOutcome,
  next: CheckoutSessionOutcome | null,
): CheckoutSessionOutcome {
  if (!next) return current;
  const rank = { paid: 3, failed: 2, expired: 2, pending: 1 };
  return rank[next.outcome] >= rank[current.outcome] ? next : current;
}

async function paymongoGet(
  secret: string,
  path: string,
): Promise<unknown | null> {
  const res = await fetch(`${PAYMONGO_API}${path}`, {
    headers: {
      Authorization: basicAuthHeader(secret),
      Accept: "application/json",
    },
  });
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch {
    return null;
  }
}

async function readPaymongoCheckout(
  secret: string,
  sessionId: string,
): Promise<CheckoutSessionOutcome> {
  let parsed = checkoutSessionOutcome(null);
  let sessionPayload: unknown = null;
  let v1: unknown = null;
  const v2 = await paymongoGet(secret, `/v2/checkout_sessions/${sessionId}`);
  if (v2) {
    sessionPayload = v2;
    parsed = betterOutcome(parsed, checkoutSessionOutcome(v2));
  }
  const terminal = (o: CheckoutSessionOutcome["outcome"]) =>
    o === "paid" || o === "failed" || o === "expired";

  async function enrichFromPaymentIntent(
    checkoutPayload: unknown,
  ): Promise<void> {
    const intentId = paymentIntentIdFromCheckout(checkoutPayload);
    if (!intentId) return;
    const intent = await paymongoGet(
      secret,
      `/v1/payment_intents/${intentId}`,
    );
    if (intent) {
      parsed = betterOutcome(parsed, checkoutSessionOutcome(intent));
    }
  }

  if (!terminal(parsed.outcome)) {
    await enrichFromPaymentIntent(v2);
  }
  if (!terminal(parsed.outcome)) {
    v1 = await paymongoGet(secret, `/v1/checkout_sessions/${sessionId}`);
    if (v1) {
      sessionPayload = sessionPayload ?? v1;
      parsed = betterOutcome(parsed, checkoutSessionOutcome(v1));
    }
  }
  if (!terminal(parsed.outcome)) {
    await enrichFromPaymentIntent(v1 ?? v2);
  }
  if (sessionPayload != null) {
    parsed = reconcileHostedCheckoutOutcome(parsed, sessionPayload);
  }
  if (!parsed.sessionId) parsed = { ...parsed, sessionId };
  return parsed;
}

async function findCheckoutPayment(
  supabase: SupabaseClient,
  orderId: string,
  checkoutGroupId: string,
): Promise<Record<string, unknown> | null> {
  const direct = await supabase
    .from("payments")
    .select("payment_id, payment_status, checkout_session_id, amount_centavos")
    .eq("order_id", orderId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const payment = asRecord(direct.data);
  const sessionId = readString(payment?.checkout_session_id);
  if (sessionId.startsWith("cs_")) return payment;

  if (!checkoutGroupId || !isUuid(checkoutGroupId)) return payment;

  const groupOrders = await supabase
    .from("orders")
    .select("order_id")
    .eq("checkout_group_id", checkoutGroupId);
  const orderIds = (groupOrders.data ?? [])
    .map((row) => readString(asRecord(row)?.order_id))
    .filter((id) => isUuid(id));
  if (orderIds.length === 0) return payment;

  const grouped = await supabase
    .from("payments")
    .select("payment_id, payment_status, checkout_session_id, amount_centavos")
    .in("order_id", orderIds)
    .not("checkout_session_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return asRecord(grouped.data) ?? payment;
}

async function expectedAmountCentavos(
  supabase: SupabaseClient,
  orderId: string,
  checkoutGroupId: string,
): Promise<number | null> {
  let orderIds = [orderId];
  if (checkoutGroupId && isUuid(checkoutGroupId)) {
    const group = await supabase
      .from("orders")
      .select("order_id")
      .eq("checkout_group_id", checkoutGroupId)
      .eq("order_status", "pending");
    const ids = (group.data ?? [])
      .map((row) => readString(asRecord(row)?.order_id))
      .filter((id) => isUuid(id));
    if (ids.length > 0) orderIds = ids;
  }
  const res = await supabase
    .from("payments")
    .select("amount_centavos")
    .in("order_id", orderIds)
    .eq("payment_status", "pending");
  if (res.error || !Array.isArray(res.data)) return null;
  let total = 0;
  for (const raw of res.data) {
    const amount = Number(asRecord(raw)?.amount_centavos);
    if (Number.isInteger(amount) && amount > 0) total += amount;
  }
  return total > 0 ? total : null;
}

async function applyReconcileEvent(
  service: SupabaseClient,
  opts: {
    outcome: "paid" | "expired" | "failed";
    sessionId: string | null;
    paymentId: string | null;
    amountCentavos: number | null;
    currency: string;
    metadataOrderId: string | null;
    orderId: string;
  },
): Promise<Record<string, unknown>> {
  const eventType = opts.outcome === "paid"
    ? "checkout_session.payment.paid"
    : opts.outcome === "expired"
    ? "checkout_session.expired"
    : "checkout_session.payment.failed";
  const eventKey =
    `reconcile:${opts.sessionId ?? "none"}:${opts.paymentId ?? "none"}:${opts.outcome}`;
  const metadataOrderId = opts.metadataOrderId && isUuid(opts.metadataOrderId)
    ? opts.metadataOrderId
    : opts.orderId;

  const applied = await service.rpc("apply_paymongo_event", {
    p_event_key: eventKey,
    p_event_type: eventType,
    p_session_id: opts.sessionId,
    p_paymongo_payment_id: opts.paymentId,
    p_amount_centavos: opts.amountCentavos,
    p_currency: opts.currency,
    p_metadata_order_id: metadataOrderId,
  });
  if (applied.error) {
    console.error("apply_paymongo_event reconcile", applied.error.message);
    return { success: false, error: applied.error.message };
  }
  return asRecord(applied.data) ?? {};
}

function dbOutcome(
  orderStatus: string,
  paymentStatus: string,
): "paid" | "expired" | "failed" | "pending" {
  if (paymentStatus === "paid" || orderStatus === "paid") return "paid";
  if (paymentStatus === "failed") return "failed";
  if (orderStatus === "cancelled") return "failed";
  return "pending";
}

/** DB rows use `failed`; PayMongo may report `expired` before void completes. */
function effectiveOutcome(
  db: "paid" | "expired" | "failed" | "pending",
  parsed: CheckoutSessionOutcome["outcome"],
): "paid" | "expired" | "failed" | "pending" {
  if (db === "paid" || parsed === "paid") return "paid";
  if (parsed === "expired" || parsed === "failed") return parsed;
  if (db === "failed") return "failed";
  return "pending";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const paymongoSecret = (Deno.env.get("PAYMONGO_SECRET_KEY") ?? "").trim();
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(500, { success: false, error: "Missing Supabase configuration" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { success: false, error: "Please sign in to pay." });
  }

  let orderId = "";
  try {
    const body = await req.json();
    orderId = typeof body?.order_id === "string" ? body.order_id.trim() : "";
  } catch {
    return json(400, { success: false, error: "Order not found." });
  }
  if (!orderId || !isUuid(orderId)) {
    return json(400, { success: false, error: "Order not found." });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { success: false, error: "Please sign in to pay." });
  }

  const orderRes = await supabase
    .from("orders")
    .select("order_id, buyer_id, order_status, checkout_group_id")
    .eq("order_id", orderId)
    .maybeSingle();
  const order = asRecord(orderRes.data);
  if (!order || String(order.buyer_id) !== userData.user.id) {
    return json(400, { success: false, error: "Order not found." });
  }

  const checkoutGroupId = readString(order.checkout_group_id);
  const payment = await findCheckoutPayment(
    supabase,
    orderId,
    checkoutGroupId,
  );
  let paymentStatus = readString(payment?.payment_status).toLowerCase();
  let orderStatus = readString(order.order_status).toLowerCase();
  const recorded = dbOutcome(orderStatus, paymentStatus);
  if (recorded === "paid") {
    return json(200, { success: true, outcome: "paid" });
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (
    (recorded === "failed" || recorded === "expired") &&
    orderStatus === "pending"
  ) {
    const sessionIdForVoid = readString(payment?.checkout_session_id);
    await applyReconcileEvent(service, {
      outcome: recorded,
      sessionId: sessionIdForVoid.startsWith("cs_") ? sessionIdForVoid : null,
      paymentId: null,
      amountCentavos: null,
      currency: "PHP",
      metadataOrderId: orderId,
      orderId,
    });
    const latestOrder = await supabase
      .from("orders")
      .select("order_status")
      .eq("order_id", orderId)
      .maybeSingle();
    const latestPayment = await findCheckoutPayment(
      supabase,
      orderId,
      checkoutGroupId,
    );
    orderStatus = readString(asRecord(latestOrder.data)?.order_status)
      .toLowerCase();
    paymentStatus = readString(latestPayment?.payment_status).toLowerCase();
    return json(200, {
      success: true,
      outcome: dbOutcome(orderStatus, paymentStatus),
    });
  }

  const sessionId = readString(payment?.checkout_session_id);
  let parsed = checkoutSessionOutcome(null);
  if (sessionId.startsWith("cs_") && paymongoSecret) {
    try {
      parsed = await readPaymongoCheckout(paymongoSecret, sessionId);
    } catch {
      console.error("paymongo session reconcile failed");
    }
  }

  const expectedAmount = await expectedAmountCentavos(
    supabase,
    orderId,
    checkoutGroupId,
  );
  const paymongoAmount = parsed.amountCentavos;
  const applyAmount = paymongoAmount ?? expectedAmount ?? null;

  console.log(JSON.stringify({
    msg: "paymongo reconcile",
    outcome: parsed.outcome,
    session_status: parsed.sessionStatus,
    session_id: parsed.sessionId ?? sessionId,
    payment_id: parsed.paymentId,
    paymongo_amount: paymongoAmount,
    expected_amount: expectedAmount,
  }));

  if (
    parsed.outcome === "paid" ||
    parsed.outcome === "expired" ||
    parsed.outcome === "failed"
  ) {
    const applyOpts = {
      outcome: parsed.outcome,
      sessionId: parsed.sessionId ??
        (sessionId.startsWith("cs_") ? sessionId : null),
      paymentId: parsed.paymentId,
      amountCentavos: applyAmount,
      currency: parsed.currency || "PHP",
      metadataOrderId: parsed.metadataOrderId,
      orderId,
    };
    let applied = await applyReconcileEvent(service, applyOpts);
    const applyError = readString(applied.error).toLowerCase();
    if (
      parsed.outcome === "paid" &&
      applied.success === false &&
      applyError.includes("amount") &&
      expectedAmount != null &&
      expectedAmount !== applyAmount
    ) {
      applied = await applyReconcileEvent(service, {
        ...applyOpts,
        amountCentavos: expectedAmount,
      });
    }
    if (applied.success === false) {
      console.error("apply_paymongo_event reconcile rejected", applied.error);
    }
  }

  const latestOrder = await supabase
    .from("orders")
    .select("order_status")
    .eq("order_id", orderId)
    .maybeSingle();
  const latestPayment = await findCheckoutPayment(
    supabase,
    orderId,
    checkoutGroupId,
  );
  orderStatus = readString(asRecord(latestOrder.data)?.order_status)
    .toLowerCase();
  paymentStatus = readString(latestPayment?.payment_status).toLowerCase();
  const db = dbOutcome(orderStatus, paymentStatus);
  const outcome = effectiveOutcome(db, parsed.outcome);
  if (outcome !== "pending") {
    return json(200, { success: true, outcome });
  }

  // PayMongo confirmed paid, but the order row has not updated yet.
  if (parsed.outcome === "paid") {
    return json(200, {
      success: true,
      outcome: "pending",
      error: "Payment is confirmed at PayMongo and is still being recorded.",
    });
  }
  return json(200, { success: true, outcome: "pending" });
});
