import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { basicAuthHeader, isPaymongoCheckoutUrl } from "../_shared/paymongo.ts";

const PAYMONGO_CHECKOUT_URL = "https://api.paymongo.com/v2/checkout_sessions";

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
  if (!paymongoSecret) {
    return json(500, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { success: false, error: "Please sign in to pay." });
  }

  let orderId = "";
  let channel = "";
  try {
    const body = await req.json();
    orderId = typeof body?.order_id === "string" ? body.order_id.trim() : "";
    const rawChannel = typeof body?.payment_method === "string"
      ? body.payment_method
      : typeof body?.channel === "string"
      ? body.channel
      : "";
    channel = rawChannel.trim().toLowerCase();
  } catch {
    return json(400, { success: false, error: "Order not found." });
  }
  if (!orderId) {
    return json(400, { success: false, error: "Order not found." });
  }
  if (channel !== "card" && channel !== "gcash") {
    return json(400, { success: false, error: "Choose Card or GCash." });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { success: false, error: "Please sign in to pay." });
  }
  const buyerId = userData.user.id;

  const prepared = await supabase.rpc("prepare_paymongo_checkout", {
    p_order_id: orderId,
    p_channel: channel,
  });
  if (prepared.error) {
    console.error("prepare_paymongo_checkout", prepared.error.message);
    return json(400, { success: false, error: "Order not found." });
  }

  const prep = (prepared.data ?? {}) as Record<string, unknown>;
  if (prep.success === false) {
    return json(400, {
      success: false,
      error: String(
        prep.error ?? "Unable to start payment right now. Please try again.",
      ),
    });
  }
  if (prep.already_paid === true) {
    return json(200, {
      success: true,
      already_paid: true,
      order_id: prep.order_id,
    });
  }
  if (prep.reuse === true && typeof prep.checkout_url === "string") {
    return json(200, {
      success: true,
      already_paid: false,
      checkout_url: prep.checkout_url,
      session_id: prep.session_id,
      payment_id: prep.payment_id,
    });
  }

  const amountCentavos = Number(prep.amount_centavos);
  const paymentId = String(prep.payment_id ?? "");
  const orderNumber = String(prep.order_number ?? "ThriftLine order");
  const orderCount = Number(prep.order_count ?? 1);
  if (!Number.isInteger(amountCentavos) || amountCentavos < 1 || !paymentId) {
    return json(400, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }

  const previousSession = typeof prep.previous_session_id === "string"
    ? prep.previous_session_id
    : "";
  if (previousSession) {
    try {
      await fetch(`${PAYMONGO_CHECKOUT_URL}/${previousSession}/expire`, {
        method: "POST",
        headers: {
          Authorization: basicAuthHeader(paymongoSecret),
          Accept: "application/json",
        },
      });
    } catch {
      console.error("expire previous checkout session failed");
    }
  }

  const successUrl = Deno.env.get("PAYMONGO_SUCCESS_URL") ??
    `${supabaseUrl}/functions/v1/paymongo-return?status=success`;
  const cancelUrl = Deno.env.get("PAYMONGO_CANCEL_URL") ??
    `${supabaseUrl}/functions/v1/paymongo-return?status=cancel`;

  let paymongoRes: Response;
  try {
    paymongoRes = await fetch(PAYMONGO_CHECKOUT_URL, {
      method: "POST",
      headers: {
        Authorization: basicAuthHeader(paymongoSecret),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        data: {
          attributes: {
            description: orderCount > 1
              ? `ThriftLine checkout (${orderCount} shops)`
              : `ThriftLine ${orderNumber}`,
            line_items: [
              {
                name: orderCount > 1
                  ? `ThriftLine checkout (${orderCount} shops)`
                  : orderNumber,
                amount: amountCentavos,
                currency: "PHP",
                quantity: 1,
              },
            ],
            payment_method_types: [channel],
            send_email_receipt: false,
            show_description: true,
            show_line_items: true,
            reference_number: orderNumber.slice(0, 100),
            success_url:
              `${successUrl}${successUrl.includes("?") ? "&" : "?"}order_id=${orderId}`,
            cancel_url:
              `${cancelUrl}${cancelUrl.includes("?") ? "&" : "?"}order_id=${orderId}`,
            metadata: {
              order_id: orderId,
              payment_id: paymentId,
              paymongo_channel: channel,
              checkout_group_id: typeof prep.checkout_group_id === "string"
                ? prep.checkout_group_id
                : "",
              order_count: String(orderCount),
            },
          },
        },
      }),
    });
  } catch {
    console.error("paymongo create session network error");
    return json(502, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }

  const paymongoText = await paymongoRes.text();
  let paymongoJson: Record<string, unknown> = {};
  try {
    paymongoJson = JSON.parse(paymongoText) as Record<string, unknown>;
  } catch {
    paymongoJson = {};
  }

  if (!paymongoRes.ok) {
    console.error("paymongo create session failed", paymongoRes.status);
    return json(502, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }

  const data = (paymongoJson.data ?? {}) as Record<string, unknown>;
  const attributes = (data.attributes ?? {}) as Record<string, unknown>;
  const sessionId = typeof data.id === "string" ? data.id : "";
  const checkoutUrl =
    typeof attributes.checkout_url === "string" ? attributes.checkout_url : "";
  if (!sessionId.startsWith("cs_") || !isPaymongoCheckoutUrl(checkoutUrl)) {
    return json(502, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const attached = await service.rpc("attach_paymongo_checkout", {
    p_payment_id: paymentId,
    p_session_id: sessionId,
    p_checkout_url: checkoutUrl,
    p_buyer_id: buyerId,
  });
  if (attached.error) {
    console.error("attach_paymongo_checkout", attached.error.message);
    return json(400, {
      success: false,
      error: "Unable to start payment right now. Please try again.",
    });
  }
  const attachMap = (attached.data ?? {}) as Record<string, unknown>;
  if (attachMap.success === false) {
    return json(400, {
      success: false,
      error: String(
        attachMap.error ??
          "Unable to start payment right now. Please try again.",
      ),
    });
  }
  if (attachMap.already_paid === true) {
    return json(200, {
      success: true,
      already_paid: true,
      order_id: attachMap.order_id,
    });
  }

  return json(200, {
    success: true,
    already_paid: false,
    checkout_url: checkoutUrl,
    session_id: sessionId,
    payment_id: paymentId,
  });
});
