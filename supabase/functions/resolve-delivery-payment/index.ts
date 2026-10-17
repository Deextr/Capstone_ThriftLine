import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { internalManualRefundOutcome } from "../_shared/internal_manual_refund.ts";
import type { ServiceClient } from "../_shared/supabase_client.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
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
      refund_state: prep.refund_state ?? null,
      amount_centavos: prep.amount_centavos,
      ...recorded.fields,
    });
  }

  const amountCentavos = readInt(prep.amount_centavos);
  const escrowId = readString(prep.escrow_id);
  if (amountCentavos == null || amountCentavos < 1 || !escrowId) {
    await supabase.rpc("abort_delivery_refund", { p_dispute_id: disputeId });
    return json(400, {
      success: false,
      error: "No held payment was found for this order.",
    });
  }

  const manual = internalManualRefundOutcome();

  const finalized = await supabase.rpc("finalize_delivery_refund", {
    p_dispute_id: disputeId,
    p_provider: manual.provider,
    p_paymongo_refund_id: manual.paymongoRefundId,
    p_provider_status: manual.providerStatus,
    p_admin_note: adminNote.trim() || null,
    p_transfer_link: manual.transferLink,
    p_transfer_link_expires_at: manual.transferLinkExpiresAt,
    p_provider_error: manual.providerError,
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
    refund_provider: String(fin.refund_provider ?? manual.provider),
    refund_state: fin.refund_state ?? null,
    amount_centavos: fin.amount_centavos ?? amountCentavos,
    ...recorded.fields,
  });
});

async function recordRefundReturn(
  supabase: ServiceClient,
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
