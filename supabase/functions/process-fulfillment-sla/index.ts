import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { basicAuthHeader } from "../_shared/paymongo.ts";

const PAYMONGO_REFUNDS_URL = "https://api.paymongo.com/v1/refunds";

type RpcMap = Record<string, unknown>;

function asMap(value: unknown): RpcMap {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as RpcMap;
  }
  return {};
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isInteger(parsed)) return parsed;
  }
  return null;
}

function paymongoErrorCode(payload: unknown): string {
  const root = asMap(payload);
  const errors = root.errors;
  if (!Array.isArray(errors) || errors.length === 0) return "";
  return readString(asMap(errors[0]).code).toLowerCase();
}

function providerCannotRefund(status: number, code: string): boolean {
  if (status === 404) return true;
  return [
    "payment_not_found",
    "payment_not_refundable",
    "resource_not_found",
    "invalid_payment",
  ].includes(code);
}

function jobSecretAllowed(req: Request): boolean {
  const expected = (Deno.env.get("FULFILLMENT_SLA_JOB_SECRET") ?? "").trim();
  if (!expected) return true;
  const header = req.headers.get("x-fulfillment-sla-secret") ?? "";
  const bearer = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  return header === expected || bearer === expected;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { error: "Method not allowed" });
  }
  if (!jobSecretAllowed(req)) {
    return json(401, { error: "Unauthorized" });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const paymongoSecret = (Deno.env.get("PAYMONGO_SECRET_KEY") ?? "").trim();
  if (!url || !serviceKey) {
    return json(500, { error: "Missing Supabase service configuration" });
  }

  const service = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const nudges = await service.rpc("process_fulfillment_sla");
    if (nudges.error) {
      console.error("process_fulfillment_sla", nudges.error.message);
      return json(500, { error: nudges.error.message });
    }

    const candidates = await service.rpc(
      "list_fulfillment_sla_refund_candidates",
    );
    if (candidates.error) {
      console.error(
        "list_fulfillment_sla_refund_candidates",
        candidates.error.message,
      );
      return json(500, { error: candidates.error.message });
    }

    const rows = Array.isArray(candidates.data) ? candidates.data : [];
    const refunds: Array<Record<string, unknown>> = [];
    for (const row of rows) {
      const orderId = readString(asMap(row).order_id);
      if (!orderId) continue;
      refunds.push(await refundStuckOrder(service, orderId, paymongoSecret));
    }

    return json(200, {
      success: true,
      nudges: nudges.data ?? 0,
      refunds,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});

async function refundStuckOrder(
  service: ReturnType<typeof createClient>,
  orderId: string,
  paymongoSecret: string,
): Promise<Record<string, unknown>> {
  const prepared = await service.rpc("prepare_fulfillment_sla_refund", {
    p_order_id: orderId,
  });
  if (prepared.error) {
    return { order_id: orderId, success: false, error: prepared.error.message };
  }
  const prep = asMap(prepared.data);
  if (prep.success === false) {
    return {
      order_id: orderId,
      success: false,
      error: String(prep.error ?? "Could not start this refund."),
    };
  }
  if (prep.already_decided === true) {
    return { order_id: orderId, success: true, already_decided: true };
  }

  const amountCentavos = readInt(prep.amount_centavos);
  const paymongoPaymentId = readString(prep.paymongo_payment_id);
  const escrowId = readString(prep.escrow_id);
  if (amountCentavos == null || amountCentavos < 1) {
    await service.rpc("abort_fulfillment_sla_refund", { p_order_id: orderId });
    return { order_id: orderId, success: false, error: "No held payment." };
  }

  let provider: "paymongo" | "internal" = "internal";
  let refundId = "";
  let providerStatus = "internal";
  const canCallPaymongo = paymongoPaymentId.startsWith("pay_") &&
    paymongoSecret.length > 0;

  if (canCallPaymongo) {
    try {
      const paymongoRes = await fetch(PAYMONGO_REFUNDS_URL, {
        method: "POST",
        headers: {
          Authorization: basicAuthHeader(paymongoSecret),
          "Content-Type": "application/json",
          Accept: "application/json",
          "Idempotency-Key": escrowId || orderId,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount: amountCentavos,
              payment_id: paymongoPaymentId,
              reason: "requested_by_customer",
              notes: "ThriftLine 72-hour fulfillment SLA auto-cancel refund",
            },
          },
        }),
      });
      const paymongoText = await paymongoRes.text();
      let paymongoJson: RpcMap = {};
      try {
        paymongoJson = asMap(JSON.parse(paymongoText));
      } catch {
        paymongoJson = {};
      }

      if (paymongoRes.status >= 500 || paymongoRes.status === 429) {
        await service.rpc("abort_fulfillment_sla_refund", {
          p_order_id: orderId,
        });
        return { order_id: orderId, success: false, error: "PayMongo busy." };
      }
      if (paymongoRes.ok) {
        const data = asMap(paymongoJson.data);
        const attributes = asMap(data.attributes);
        const id = readString(data.id);
        const status = readString(attributes.status).toLowerCase();
        if (!id.startsWith("ref_") || status === "failed") {
          await service.rpc("abort_fulfillment_sla_refund", {
            p_order_id: orderId,
          });
          return {
            order_id: orderId,
            success: false,
            error: "PayMongo rejected this refund.",
          };
        }
        provider = "paymongo";
        refundId = id;
        providerStatus = status || "succeeded";
      } else if (
        providerCannotRefund(
          paymongoRes.status,
          paymongoErrorCode(paymongoJson),
        )
      ) {
        provider = "internal";
        providerStatus = paymongoErrorCode(paymongoJson) ||
          "provider_not_refundable";
      } else {
        await service.rpc("abort_fulfillment_sla_refund", {
          p_order_id: orderId,
        });
        return {
          order_id: orderId,
          success: false,
          error: "PayMongo did not accept this refund.",
        };
      }
    } catch {
      await service.rpc("abort_fulfillment_sla_refund", { p_order_id: orderId });
      return { order_id: orderId, success: false, error: "PayMongo network error." };
    }
  } else {
    providerStatus = paymongoPaymentId.startsWith("pay_")
      ? "provider_key_missing"
      : "no_paymongo_payment_id";
  }

  const finalized = await service.rpc("finalize_fulfillment_sla_refund", {
    p_order_id: orderId,
    p_provider: provider,
    p_paymongo_refund_id: refundId || null,
    p_provider_status: providerStatus,
  });
  if (finalized.error) {
    return { order_id: orderId, success: false, error: finalized.error.message };
  }
  const fin = asMap(finalized.data);
  if (fin.success === false) {
    return {
      order_id: orderId,
      success: false,
      error: String(fin.error ?? "Could not record this refund."),
    };
  }
  return {
    order_id: orderId,
    success: true,
    refund_provider: String(fin.refund_provider ?? provider),
  };
}
