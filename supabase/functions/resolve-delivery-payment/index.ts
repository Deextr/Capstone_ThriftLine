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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const paymongoSecret = (Deno.env.get("PAYMONGO_SECRET_KEY") ?? "").trim();
  if (!supabaseUrl || !anonKey) {
    return json(500, { success: false, error: "Missing Supabase configuration" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { success: false, error: "Please sign in." });
  }

  let disputeId = "";
  let adminNote = "";
  let returnRequired = false;
  try {
    const body = await req.json();
    disputeId = typeof body?.dispute_id === "string" ? body.dispute_id.trim() : "";
    adminNote = typeof body?.admin_note === "string" ? body.admin_note : "";
    returnRequired = body?.return_required === true;
  } catch {
    return json(400, { success: false, error: "Delivery problem not found." });
  }
  if (!disputeId) {
    return json(400, { success: false, error: "Delivery problem not found." });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { success: false, error: "Please sign in." });
  }

  const prepared = await supabase.rpc("prepare_delivery_refund", {
    p_dispute_id: disputeId,
    p_admin_note: adminNote.trim() || null,
  });
  if (prepared.error) {
    console.error("prepare_delivery_refund", prepared.error.message);
    return json(400, {
      success: false,
      error: "Could not start this refund.",
    });
  }

  const prep = asMap(prepared.data);
  if (prep.success === false) {
    return json(400, {
      success: false,
      error: String(prep.error ?? "Could not start this refund."),
    });
  }
  if (prep.already_decided === true) {
    const recorded = await recordRefundReturn(supabase, disputeId, returnRequired);
    if (recorded.error) {
      return json(400, recorded.body);
    }
    return json(200, {
      success: true,
      already_decided: true,
      decision: "refund",
      status: "refunded",
      refund_provider: String(prep.refund_provider ?? "internal"),
      amount_centavos: prep.amount_centavos,
      ...recorded.fields,
    });
  }

  const amountCentavos = readInt(prep.amount_centavos);
  const paymongoPaymentId = readString(prep.paymongo_payment_id);
  const escrowId = readString(prep.escrow_id);
  if (amountCentavos == null || amountCentavos < 1) {
    await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
    return json(400, {
      success: false,
      error: "No held payment was found for this order.",
    });
  }

  let provider: "paymongo" | "internal" = "internal";
  let refundId = "";
  let providerStatus = "internal";

  const canCallPaymongo = paymongoPaymentId.startsWith("pay_") &&
    paymongoSecret.length > 0;

  if (canCallPaymongo) {
    let paymongoRes: Response;
    try {
      paymongoRes = await fetch(PAYMONGO_REFUNDS_URL, {
        method: "POST",
        headers: {
          Authorization: basicAuthHeader(paymongoSecret),
          "Content-Type": "application/json",
          Accept: "application/json",
          "Idempotency-Key": escrowId || disputeId,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount: amountCentavos,
              payment_id: paymongoPaymentId,
              reason: "requested_by_customer",
              notes: "ThriftLine delivery-problem refund",
            },
          },
        }),
      });
    } catch {
      console.error("paymongo refund network error");
      await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
      return json(502, {
        success: false,
        error: "Could not reach the payment provider. Try again.",
      });
    }

    const paymongoText = await paymongoRes.text();
    let paymongoJson: RpcMap = {};
    try {
      paymongoJson = asMap(JSON.parse(paymongoText));
    } catch {
      paymongoJson = {};
    }

    if (paymongoRes.status >= 500 || paymongoRes.status === 429) {
      console.error("paymongo refund retryable", paymongoRes.status);
      await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
      return json(502, {
        success: false,
        error: "The payment provider is busy. Try again.",
      });
    }

    if (paymongoRes.status === 401 || paymongoRes.status === 403) {
      console.error("paymongo refund auth failed");
      await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
      return json(502, {
        success: false,
        error: "Could not reach the payment provider. Try again.",
      });
    }

    if (paymongoRes.ok) {
      const data = asMap(paymongoJson.data);
      const attributes = asMap(data.attributes);
      const id = readString(data.id);
      const status = readString(attributes.status).toLowerCase();
      if (!id.startsWith("ref_") || status === "failed") {
        await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
        return json(502, {
          success: false,
          error: "The payment provider did not accept this refund. Try again.",
        });
      }
      provider = "paymongo";
      refundId = id;
      providerStatus = status || "succeeded";
    } else if (providerCannotRefund(paymongoRes.status, paymongoErrorCode(paymongoJson))) {
      provider = "internal";
      providerStatus = paymongoErrorCode(paymongoJson) || "provider_not_refundable";
    } else {
      console.error("paymongo refund rejected", paymongoRes.status);
      await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
      return json(400, {
        success: false,
        error: "The payment provider did not accept this refund.",
      });
    }
  } else {
    provider = "internal";
    providerStatus = paymongoPaymentId.startsWith("pay_")
      ? "provider_key_missing"
      : "no_paymongo_payment_id";
  }

  const finalized = await supabase.rpc("finalize_delivery_refund", {
    p_dispute_id: disputeId,
    p_provider: provider,
    p_paymongo_refund_id: refundId || null,
    p_provider_status: providerStatus,
    p_admin_note: adminNote.trim() || null,
  });
  if (finalized.error) {
    console.error("finalize_delivery_refund", finalized.error.message);
    return json(400, {
      success: false,
      error: "Refund was started but could not be recorded. Try again.",
    });
  }

  const fin = asMap(finalized.data);
  if (fin.success === false) {
    return json(400, {
      success: false,
      error: String(fin.error ?? "Could not record this refund."),
    });
  }

  const recorded = await recordRefundReturn(supabase, disputeId, returnRequired);
  if (recorded.error) {
    return json(400, {
      success: false,
      refund_recorded: true,
      error: recorded.body.error,
    });
  }

  return json(200, {
    success: true,
    already_decided: fin.already_decided === true,
    decision: "refund",
    status: "refunded",
    refund_provider: String(fin.refund_provider ?? provider),
    amount_centavos: fin.amount_centavos ?? amountCentavos,
    ...recorded.fields,
  });
});

async function recordRefundReturn(
  supabase: ReturnType<typeof createClient>,
  disputeId: string,
  returnRequired: boolean,
): Promise<{ error: boolean; body: RpcMap; fields: RpcMap }> {
  const recorded = await supabase.rpc("record_refund_return", {
    p_dispute_id: disputeId,
    p_return_required: returnRequired,
  });
  if (recorded.error) {
    console.error("record_refund_return", recorded.error.message);
    return {
      error: true,
      body: {
        success: false,
        error: "The refund was recorded, but the return choice could not be saved. Try again.",
      },
      fields: {},
    };
  }
  const map = asMap(recorded.data);
  if (map.success === false) {
    return {
      error: true,
      body: {
        success: false,
        error: String(
          map.error ??
            "The refund was recorded, but the return choice could not be saved. Try again.",
        ),
      },
      fields: {},
    };
  }
  return {
    error: false,
    body: {},
    fields: {
      return_required: map.return_required === true,
      return_status: map.return_status ?? null,
      return_already_recorded: map.already_recorded === true,
    },
  };
}
