import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { internalManualRefundOutcome } from "../_shared/internal_manual_refund.ts";
import { retrieveRefund } from "../_shared/paymongo_refund.ts";
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
      refunds.push(await refundStuckOrder(service, orderId));
    }

    const reconciled = await reconcilePendingRefunds(service, paymongoSecret);

    return json(200, {
      success: true,
      nudges: nudges.data ?? 0,
      refunds,
      reconciled,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});

async function refundStuckOrder(
  service: ServiceClient,
  orderId: string,
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
  if (amountCentavos == null || amountCentavos < 1) {
    await service.rpc("abort_fulfillment_sla_refund", { p_order_id: orderId });
    return { order_id: orderId, success: false, error: "No held payment." };
  }

  const manual = internalManualRefundOutcome();

  const finalized = await service.rpc("finalize_fulfillment_sla_refund", {
    p_order_id: orderId,
    p_provider: manual.provider,
    p_paymongo_refund_id: manual.paymongoRefundId,
    p_provider_status: manual.providerStatus,
    p_transfer_link: manual.transferLink,
    p_transfer_link_expires_at: manual.transferLinkExpiresAt,
    p_provider_error: manual.providerError,
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
    refund_provider: String(fin.refund_provider ?? manual.provider),
    refund_state: fin.refund_state ?? null,
  };
}

async function reconcilePendingRefunds(
  service: ServiceClient,
  paymongoSecret: string,
): Promise<Array<Record<string, unknown>>> {
  if (!paymongoSecret) return [];
  const listed = await service.rpc("list_refunds_to_reconcile", { p_limit: 25 });
  if (listed.error) {
    console.error("list_refunds_to_reconcile", listed.error.message);
    return [];
  }
  const rows = Array.isArray(listed.data) ? listed.data : [];
  const results: Array<Record<string, unknown>> = [];
  for (const raw of rows) {
    const row = asMap(raw);
    const escrowId = readString(row.escrow_id);
    const refundId = readString(row.paymongo_refund_id);
    if (!escrowId || !refundId) continue;
    const retrieved = await retrieveRefund({
      secret: paymongoSecret,
      refundId,
      channel: readString(row.paymongo_channel) || null,
    });
    await service.rpc("record_refund_attempt", {
      p_escrow_id: escrowId,
      p_source: "reconcile",
      p_action: "retrieve",
      p_outcome: retrieved.ok ? "updated" : "unknown",
      p_paymongo_refund_id: refundId,
      p_http_status: retrieved.ok ? 200 : retrieved.httpStatus,
      p_provider_status: retrieved.ok ? retrieved.refund.status : null,
      p_error_code: retrieved.ok ? null : "retrieve_failed",
      p_has_transfer_link: retrieved.ok && retrieved.refund.transferLink != null,
    });
    if (!retrieved.ok) {
      results.push({ escrow_id: escrowId, success: false });
      continue;
    }
    const applied = await service.rpc("apply_refund_provider_update", {
      p_paymongo_refund_id: refundId,
      p_provider_status: retrieved.refund.status,
      p_transfer_link: retrieved.refund.transferLink,
      p_transfer_link_expires_at: retrieved.refund.transferLinkExpiresAt,
      p_provider_error: retrieved.refund.status === "failed"
        ? "provider_failed"
        : null,
    });
    const map = asMap(applied.data);
    results.push({
      escrow_id: escrowId,
      success: !applied.error && map.success !== false,
      refund_state: map.refund_state ?? null,
    });
  }
  return results;
}
