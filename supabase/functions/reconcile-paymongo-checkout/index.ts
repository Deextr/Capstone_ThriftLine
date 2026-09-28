import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { basicAuthHeader } from "../_shared/paymongo.ts";

const PAYMONGO_CHECKOUT_URL = "https://api.paymongo.com/v2/checkout_sessions";

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function sessionOutcome(payload: unknown): "paid" | "expired" | "failed" | "pending" {
  const root = asRecord(payload);
  const data = asRecord(root?.data);
  const attrs = asRecord(data?.attributes);
  const status = readString(attrs?.status);
  if (status === "paid") return "paid";
  if (status === "expired" || status === "inactive") return "expired";

  const payments = attrs?.payments;
  if (Array.isArray(payments)) {
    for (const raw of payments) {
      const payment = asRecord(raw);
      const inner = asRecord(payment?.data) ?? payment;
      const payAttrs = asRecord(inner?.attributes) ?? inner;
      const payStatus = readString(payAttrs?.status);
      if (payStatus === "paid") return "paid";
      if (payStatus === "failed" || payStatus === "expired") {
        return payStatus === "expired" ? "expired" : "failed";
      }
    }
  }
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
  if (!orderId) {
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
    .select("order_id, buyer_id, order_status")
    .eq("order_id", orderId)
    .maybeSingle();
  const order = asRecord(orderRes.data);
  if (!order || String(order.buyer_id) !== userData.user.id) {
    return json(400, { success: false, error: "Order not found." });
  }

  const paymentRes = await supabase
    .from("payments")
    .select("payment_id, payment_status, checkout_session_id")
    .eq("order_id", orderId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const payment = asRecord(paymentRes.data);
  const paymentStatus = readString(payment?.payment_status);
  const orderStatus = readString(order.order_status);

  if (paymentStatus === "paid" || orderStatus === "paid") {
    return json(200, { success: true, outcome: "paid" });
  }
  if (orderStatus === "cancelled" || paymentStatus === "failed") {
    return json(200, {
      success: true,
      outcome: paymentStatus === "failed" ? "failed" : "expired",
    });
  }

  let outcome: "paid" | "expired" | "failed" | "pending" = "pending";
  const sessionId = typeof payment?.checkout_session_id === "string"
    ? payment.checkout_session_id.trim()
    : "";
  if (sessionId.startsWith("cs_") && paymongoSecret) {
    try {
      const res = await fetch(`${PAYMONGO_CHECKOUT_URL}/${sessionId}`, {
        headers: {
          Authorization: basicAuthHeader(paymongoSecret),
          Accept: "application/json",
        },
      });
      if (res.ok) {
        outcome = sessionOutcome(await res.json());
      } else if (res.status === 404) {
        outcome = "expired";
      }
    } catch {
      console.error("paymongo session reconcile failed");
    }
  }

  if (outcome === "expired" || outcome === "failed") {
    const service = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const voided = await service.rpc("void_unpaid_checkout", {
      p_order_id: orderId,
    });
    if (voided.error) {
      console.error("void_unpaid_checkout", voided.error.message);
    }
  }

  return json(200, { success: true, outcome });
});
