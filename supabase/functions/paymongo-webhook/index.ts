import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/cors.ts";
import {
  basicAuthHeader,
  parsePaymongoEvent,
  verifyPaymongoSignature,
  type PaymongoEvent,
} from "../_shared/paymongo.ts";

const PAYMONGO_CHECKOUT_URL = "https://api.paymongo.com/v2/checkout_sessions";

async function enrichFromCheckoutSession(
  secret: string,
  event: PaymongoEvent,
): Promise<PaymongoEvent> {
  if (event.amountCentavos != null || !event.sessionId) return event;
  try {
    const res = await fetch(`${PAYMONGO_CHECKOUT_URL}/${event.sessionId}`, {
      headers: {
        Authorization: basicAuthHeader(secret),
        Accept: "application/json",
      },
    });
    if (!res.ok) return event;
    const payload = await res.json();
    const parsed = parsePaymongoEvent({
      data: {
        id: event.eventKey,
        type: event.eventType,
        data: payload.data,
      },
    });
    if (!parsed) return event;
    return {
      ...event,
      sessionId: parsed.sessionId ?? event.sessionId,
      paymentId: parsed.paymentId ?? event.paymentId,
      amountCentavos: parsed.amountCentavos ?? event.amountCentavos,
      currency: parsed.currency || event.currency,
      metadataOrderId: parsed.metadataOrderId ?? event.metadataOrderId,
    };
  } catch {
    console.error("paymongo checkout session lookup failed");
    return event;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json(200, { ok: true });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "Method not allowed" });
  }

  const rawBody = await req.text();
  const webhookSecret = (Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "").trim();
  if (!webhookSecret) {
    console.error("PAYMONGO_WEBHOOK_SECRET is not configured");
    return json(500, { success: false, error: "Webhook is not configured." });
  }

  const signatureHeader = req.headers.get("Paymongo-Signature") ??
    req.headers.get("paymongo-signature");
  const verified = await verifyPaymongoSignature({
    rawBody,
    header: signatureHeader,
    secret: webhookSecret,
  });
  if (!verified) {
    console.error("paymongo webhook signature rejected");
    return json(401, { success: false, error: "Invalid signature." });
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(rawBody);
  } catch {
    return json(400, { success: false, error: "Invalid payload." });
  }

  let event = parsePaymongoEvent(parsedJson);
  if (!event) {
    return json(200, { success: true, ignored: true });
  }

  const paymongoSecret = (Deno.env.get("PAYMONGO_SECRET_KEY") ?? "").trim();
  if (paymongoSecret) {
    event = await enrichFromCheckoutSession(paymongoSecret, event);
  }

  console.log(
    JSON.stringify({
      msg: "paymongo webhook",
      event_type: event.eventType,
      session_id: event.sessionId,
      payment_id: event.paymentId,
    }),
  );

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json(500, { success: false, error: "Missing Supabase configuration" });
  }

  const service = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const applied = await service.rpc("apply_paymongo_event", {
    p_event_key: event.eventKey,
    p_event_type: event.eventType,
    p_session_id: event.sessionId,
    p_paymongo_payment_id: event.paymentId,
    p_amount_centavos: event.amountCentavos,
    p_currency: event.currency,
    p_metadata_order_id: event.metadataOrderId,
  });

  if (applied.error) {
    console.error("apply_paymongo_event", applied.error.message);
    return json(500, { success: false, error: "Could not apply payment event." });
  }

  const result = (applied.data ?? {}) as Record<string, unknown>;
  if (result.success === false) {
    console.error("apply_paymongo_event rejected", result.error);
    return json(400, {
      success: false,
      error: String(result.error ?? "Could not apply payment event."),
    });
  }

  return json(200, {
    success: true,
    duplicate: result.duplicate === true,
    paid: result.paid === true,
    failed: result.failed === true,
    ignored: result.ignored === true,
  });
});
