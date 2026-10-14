import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import {
  getFcmAccessToken,
  loadServiceAccountFromEnv,
  sendFcmToDevice,
} from "../_shared/fcm.ts";

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function dispatchSecretAllowed(req: Request): boolean {
  const expected = (Deno.env.get("PUSH_DISPATCH_SECRET") ?? "").trim();
  if (!expected) return true;
  const header = req.headers.get("x-push-dispatch-secret") ?? "";
  return header === expected;
}

function pushEnabledForAudience(
  audience: string,
  settings: Record<string, unknown>,
): boolean {
  const buyer =
    settings.buyer_push_notifications_enabled ??
    settings.push_notifications_enabled;
  const seller = settings.seller_push_notifications_enabled ??
    settings.push_notifications_enabled;
  const buyerOn = buyer !== false;
  const sellerOn = seller !== false;
  switch (audience) {
    case "buyer":
      return buyerOn;
    case "seller":
      return sellerOn;
    default:
      return buyerOn || sellerOn;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!dispatchSecretAllowed(req)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const serviceAccount = loadServiceAccountFromEnv();
  if (!serviceAccount) {
    return json({ skipped: true, reason: "FCM not configured" });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const notificationId = readString(body.notification_id);
  if (!notificationId) {
    return json({ error: "notification_id required" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: existingDelivery } = await admin
    .from("push_notification_deliveries")
    .select("notification_id")
    .eq("notification_id", notificationId)
    .maybeSingle();

  if (existingDelivery) {
    return json({ skipped: true, reason: "already_dispatched" });
  }

  const { data: notification, error: notifErr } = await admin
    .from("notifications")
    .select("notification_id, user_id, type, title, body, audience, data")
    .eq("notification_id", notificationId)
    .maybeSingle();

  if (notifErr || !notification) {
    return json({ error: "Notification not found" }, 404);
  }

  const userId = readString(notification.user_id);
  const audience = readString(notification.audience) || "system";

  const { data: settingsRow } = await admin
    .from("user_settings")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();

  if (
    settingsRow &&
    !pushEnabledForAudience(audience, settingsRow as Record<string, unknown>)
  ) {
    await admin.from("push_notification_deliveries").insert({
      notification_id: notificationId,
      success_count: 0,
      failure_count: 0,
      detail: { skipped: "user_push_disabled", audience },
    });
    return json({ skipped: true, reason: "user_push_disabled" });
  }

  const { data: tokens, error: tokenErr } = await admin
    .from("push_device_tokens")
    .select("device_token")
    .eq("user_id", userId)
    .is("revoked_at", null);

  if (tokenErr) {
    return json({ error: tokenErr.message }, 500);
  }

  const deviceTokens = (tokens ?? [])
    .map((row) => readString((row as Record<string, unknown>).device_token))
    .filter(Boolean);

  if (deviceTokens.length === 0) {
    await admin.from("push_notification_deliveries").insert({
      notification_id: notificationId,
      success_count: 0,
      failure_count: 0,
      detail: { skipped: "no_device_tokens" },
    });
    return json({ skipped: true, reason: "no_device_tokens" });
  }

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(serviceAccount);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "FCM auth failed";
    return json({ error: msg }, 502);
  }

  const dataPayload: Record<string, string> = {
    notification_id: notificationId,
    type: readString(notification.type),
    audience,
  };
  const rawData = notification.data;
  if (rawData && typeof rawData === "object" && !Array.isArray(rawData)) {
    for (const [key, value] of Object.entries(rawData as Record<string, unknown>)) {
      if (value == null) continue;
      const k = readString(key);
      if (!k) continue;
      if (["order_id", "conversation_id", "auction_id", "report_id", "post_id"]
        .includes(k)) {
        dataPayload[k] = readString(String(value));
      }
    }
  }

  let successCount = 0;
  let failureCount = 0;
  const results: Record<string, unknown>[] = [];

  for (const deviceToken of deviceTokens) {
    const result = await sendFcmToDevice({
      projectId: serviceAccount.project_id,
      accessToken,
      deviceToken,
      title: readString(notification.title) || "ThriftLine",
      body: readString(notification.body) || "You have a new update.",
      data: dataPayload,
    });
    if (result.ok) {
      successCount += 1;
    } else {
      failureCount += 1;
      if (result.status === 404 || result.detail.includes("UNREGISTERED")) {
        await admin
          .from("push_device_tokens")
          .update({ revoked_at: new Date().toISOString() })
          .eq("device_token", deviceToken);
      }
    }
    results.push({
      token_suffix: deviceToken.slice(-8),
      ok: result.ok,
      status: result.status,
    });
  }

  await admin.from("push_notification_deliveries").insert({
    notification_id: notificationId,
    success_count: successCount,
    failure_count: failureCount,
    detail: { results },
  });

  return json({
    ok: true,
    notification_id: notificationId,
    success_count: successCount,
    failure_count: failureCount,
  });
});
