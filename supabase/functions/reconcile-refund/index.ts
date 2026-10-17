import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import {
  createOrAdoptRefund,
  liveRefund,
  lookupExistingRefunds,
  retrieveRefund,
} from "../_shared/paymongo_refund.ts";
import type { ServiceClient } from "../_shared/supabase_client.ts";

type RpcMap = Record<string, unknown>;
type Client = ServiceClient;

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

/**
 * Admin-only refund follow-up.
 * - `check`: reads the PayMongo refund status (or looks for an unconfirmed one).
 * - `retry`: creates a new PayMongo refund for a refund that needs action,
 *   after confirming no live refund already exists.
 */
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

  let escrowId = "";
  let action = "";
  try {
    const body = await req.json();
    escrowId = readString(body?.escrow_id);
    action = readString(body?.action).toLowerCase();
  } catch {
    return json(400, { success: false, error: "Refund not found." });
  }
  if (!escrowId || (action !== "check" && action !== "retry")) {
    return json(400, { success: false, error: "Refund not found." });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return json(401, { success: false, error: "Please sign in." });
  }
  const adminCheck = await supabase.rpc("is_admin");
  if (adminCheck.error || adminCheck.data !== true) {
    return json(403, { success: false, error: "Only an admin can do this." });
  }
  if (!paymongoSecret) {
    return json(400, {
      success: false,
      error: "PayMongo is not configured on the server. Record a manual GCash refund instead.",
    });
  }

  try {
    return action === "check"
      ? await checkRefund(supabase, escrowId, paymongoSecret)
      : await retryRefund(supabase, escrowId, paymongoSecret);
  } catch (e) {
    console.error("reconcile-refund", e instanceof Error ? e.message : String(e));
    return json(500, { success: false, error: "Could not check this refund. Try again." });
  }
});

async function loadRefundContext(supabase: Client, escrowId: string) {
  const escrow = await supabase
    .from("escrow")
    .select("escrow_id, payment_id, status, refund_state, paymongo_refund_id, refund_lock_at")
    .eq("escrow_id", escrowId)
    .maybeSingle();
  if (escrow.error || !escrow.data) return null;
  const row = asMap(escrow.data);
  const payment = await supabase
    .from("payments")
    .select("paymongo_payment_id, paymongo_channel")
    .eq("payment_id", readString(row.payment_id))
    .maybeSingle();
  const pay = asMap(payment.data);
  return {
    status: readString(row.status),
    refundState: readString(row.refund_state),
    refundId: readString(row.paymongo_refund_id),
    locked: row.refund_lock_at != null,
    paymentId: readString(pay.paymongo_payment_id),
    channel: readString(pay.paymongo_channel) || null,
  };
}

async function recordAttempt(
  supabase: Client,
  escrowId: string,
  fields: {
    source: string;
    action: string;
    outcome: string;
    refundId?: string | null;
    httpStatus?: number | null;
    providerStatus?: string | null;
    errorCode?: string | null;
    hasTransferLink?: boolean;
  },
) {
  const res = await supabase.rpc("record_refund_attempt", {
    p_escrow_id: escrowId,
    p_source: fields.source,
    p_action: fields.action,
    p_outcome: fields.outcome,
    p_paymongo_refund_id: fields.refundId ?? null,
    p_http_status: fields.httpStatus ?? null,
    p_provider_status: fields.providerStatus ?? null,
    p_error_code: fields.errorCode ?? null,
    p_has_transfer_link: fields.hasTransferLink ?? false,
  });
  if (res.error) console.error("record_refund_attempt", res.error.message);
}

async function checkRefund(
  supabase: Client,
  escrowId: string,
  secret: string,
): Promise<Response> {
  const ctx = await loadRefundContext(supabase, escrowId);
  if (!ctx || ctx.status !== "refunded") {
    return json(404, { success: false, error: "Refund not found." });
  }

  if (
    (ctx.refundState === "provider_pending" ||
      ctx.refundState === "awaiting_buyer_claim") && ctx.refundId
  ) {
    const retrieved = await retrieveRefund({
      secret,
      refundId: ctx.refundId,
      channel: ctx.channel,
    });
    await recordAttempt(supabase, escrowId, {
      source: "admin_retry",
      action: "retrieve",
      outcome: retrieved.ok ? "updated" : "unknown",
      refundId: ctx.refundId,
      httpStatus: retrieved.ok ? 200 : retrieved.httpStatus,
      providerStatus: retrieved.ok ? retrieved.refund.status : null,
      errorCode: retrieved.ok ? null : "retrieve_failed",
      hasTransferLink: retrieved.ok && retrieved.refund.transferLink != null,
    });
    if (!retrieved.ok) {
      return json(502, {
        success: false,
        error: "PayMongo did not return this refund. Nothing was changed. Try again later.",
      });
    }
    const applied = await supabase.rpc("apply_refund_provider_update", {
      p_paymongo_refund_id: ctx.refundId,
      p_provider_status: retrieved.refund.status,
      p_transfer_link: retrieved.refund.transferLink,
      p_transfer_link_expires_at: retrieved.refund.transferLinkExpiresAt,
      p_provider_error: retrieved.refund.status === "failed" ? "provider_failed" : null,
    });
    const map = asMap(applied.data);
    if (applied.error || map.success === false) {
      return json(400, {
        success: false,
        error: String(map.error ?? "Could not save the PayMongo status."),
      });
    }
    return json(200, {
      success: true,
      provider_status: retrieved.refund.status,
      refund_state: map.refund_state ?? ctx.refundState,
    });
  }

  if (ctx.refundState === "manual_required" && ctx.locked) {
    if (!ctx.paymentId.startsWith("pay_")) {
      await supabase.rpc("clear_unverified_refund_lock", { p_escrow_id: escrowId });
      return json(200, { success: true, refund_state: "manual_required" });
    }
    const lookup = await lookupExistingRefunds({
      secret,
      paymentId: ctx.paymentId,
      channel: ctx.channel,
    });
    if (!lookup.ok) {
      await recordAttempt(supabase, escrowId, {
        source: "admin_retry",
        action: "lookup",
        outcome: "unknown",
        errorCode: "lookup_failed",
      });
      return json(502, {
        success: false,
        error:
          "PayMongo could not be checked. The last attempt is still unconfirmed, so manual GCash stays blocked. Try again later.",
      });
    }
    const live = liveRefund(lookup.refunds);
    await recordAttempt(supabase, escrowId, {
      source: "admin_retry",
      action: "lookup",
      outcome: live ? "accepted" : "not_found",
      refundId: live?.id ?? null,
      providerStatus: live?.status ?? null,
      hasTransferLink: live?.transferLink != null,
    });
    if (live) {
      const applied = await supabase.rpc("apply_refund_retry_result", {
        p_escrow_id: escrowId,
        p_outcome: "accepted",
        p_paymongo_refund_id: live.id,
        p_provider_status: live.status,
        p_transfer_link: live.transferLink,
        p_transfer_link_expires_at: live.transferLinkExpiresAt,
        p_provider_error: null,
      });
      const map = asMap(applied.data);
      return json(applied.error || map.success === false ? 400 : 200, {
        success: !applied.error && map.success !== false,
        adopted_refund_id: live.id,
        refund_state: map.refund_state ?? null,
        error: map.error ?? undefined,
      });
    }
    await supabase.rpc("clear_unverified_refund_lock", { p_escrow_id: escrowId });
    return json(200, {
      success: true,
      verified_no_refund: true,
      refund_state: "manual_required",
    });
  }

  return json(200, {
    success: true,
    nothing_to_check: true,
    refund_state: ctx.refundState || null,
  });
}

async function retryRefund(
  supabase: Client,
  escrowId: string,
  secret: string,
): Promise<Response> {
  const prepared = await supabase.rpc("prepare_refund_retry", {
    p_escrow_id: escrowId,
  });
  const prep = asMap(prepared.data);
  if (prepared.error || prep.success === false) {
    return json(400, {
      success: false,
      error: String(prep.error ?? "Could not start this retry."),
    });
  }

  const amountCentavos = readInt(prep.amount_centavos);
  const paymentId = readString(prep.paymongo_payment_id);
  if (amountCentavos == null || amountCentavos < 1 || !paymentId) {
    await supabase.rpc("apply_refund_retry_result", {
      p_escrow_id: escrowId,
      p_outcome: "rejected",
      p_provider_error: "invalid_refund_context",
    });
    return json(400, { success: false, error: "This refund cannot be retried." });
  }

  const outcome = await createOrAdoptRefund({
    secret,
    paymentId,
    channel: readString(prep.paymongo_channel) || null,
    amountCentavos,
    idempotencyKey: `${escrowId}-retry-${Date.now()}`,
    notes: "ThriftLine refund retry",
  });

  await recordAttempt(supabase, escrowId, {
    source: "admin_retry",
    action: outcome.kind === "accepted" ? outcome.action : "create",
    outcome: outcome.kind,
    refundId: outcome.kind === "accepted" ? outcome.refund.id : null,
    httpStatus: outcome.httpStatus,
    providerStatus: outcome.kind === "accepted" ? outcome.refund.status : null,
    errorCode: outcome.kind === "accepted" ? null : outcome.errorCode,
    hasTransferLink: outcome.kind === "accepted" && outcome.refund.transferLink != null,
  });

  const applied = await supabase.rpc("apply_refund_retry_result", {
    p_escrow_id: escrowId,
    p_outcome: outcome.kind,
    p_paymongo_refund_id: outcome.kind === "accepted" ? outcome.refund.id : null,
    p_provider_status: outcome.kind === "accepted" ? outcome.refund.status : null,
    p_transfer_link: outcome.kind === "accepted" ? outcome.refund.transferLink : null,
    p_transfer_link_expires_at: outcome.kind === "accepted"
      ? outcome.refund.transferLinkExpiresAt
      : null,
    p_provider_error: outcome.kind === "accepted" ? null : outcome.errorCode,
  });
  const map = asMap(applied.data);
  if (applied.error || map.success === false) {
    return json(400, {
      success: false,
      error: String(map.error ?? "Could not save the retry result."),
    });
  }

  if (outcome.kind === "unknown") {
    return json(502, {
      success: false,
      unverified: true,
      refund_state: map.refund_state ?? "manual_required",
      error:
        "PayMongo did not confirm the retry. Use Check PayMongo status before doing anything else.",
    });
  }
  if (outcome.kind === "rejected") {
    return json(200, {
      success: true,
      rejected: true,
      error_code: outcome.errorCode,
      refund_state: "manual_required",
    });
  }
  return json(200, {
    success: true,
    adopted: outcome.action === "adopt",
    provider_status: outcome.refund.status,
    refund_state: map.refund_state ?? null,
  });
}
