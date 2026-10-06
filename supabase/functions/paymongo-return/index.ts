const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP_PACKAGE = "com.example.thriftline";

function readOrderId(url: URL): string {
  const raw = (url.searchParams.get("order_id") ?? "").trim();
  return UUID.test(raw) ? raw : "";
}

function readStatus(url: URL): "success" | "cancel" | "failed" | "expired" {
  const raw = (url.searchParams.get("status") ?? "").trim().toLowerCase();
  if (raw === "cancel" || raw === "cancelled") return "cancel";
  if (raw === "failed" || raw === "fail") return "failed";
  if (raw === "expired") return "expired";
  return "success";
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const status = readStatus(url);
  const orderId = readOrderId(url);
  const query = `status=${status}${orderId ? `&order_id=${orderId}` : ""}`;
  const appUrl = `thriftline://paymongo-return?${query}`;
  const intentUrl =
    `intent://paymongo-return?${query}#Intent;scheme=thriftline;package=${APP_PACKAGE};end`;
  const message = status === "cancel"
    ? "Returning to ThriftLine…"
    : status === "failed" || status === "expired"
    ? "Returning to ThriftLine to confirm your payment…"
    : "Opening ThriftLine to confirm your payment…";

  // Shared *.supabase.co functions rewrite GET text/html → text/plain and add
  // X-Content-Type-Options: nosniff plus CSP sandbox. A bounce HTML page is
  // therefore shown as source and never opens the app. Redirect instead.
  return new Response(`${message}\n\n${appUrl}\n`, {
    status: 302,
    headers: {
      Location: intentUrl,
      Refresh: `0;url=${appUrl}`,
      "Cache-Control": "no-store",
      "Content-Type": "text/plain; charset=utf-8",
    },
  });
});
