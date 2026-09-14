const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readOrderId(url: URL): string {
  const raw = (url.searchParams.get("order_id") ?? "").trim();
  return UUID.test(raw) ? raw : "";
}

function readStatus(url: URL): "success" | "cancel" {
  const raw = (url.searchParams.get("status") ?? "").trim().toLowerCase();
  return raw === "cancel" || raw === "cancelled" ? "cancel" : "success";
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const status = readStatus(url);
  const orderId = readOrderId(url);
  const query = `status=${status}${orderId ? `&order_id=${orderId}` : ""}`;
  const appUrl = `thriftline://paymongo-return?${query}`;
  const intentUrl =
    `intent://paymongo-return?${query}#Intent;scheme=thriftline;package=com.example.thriftline;end`;
  const title = status === "cancel"
    ? "Returning to ThriftLine"
    : "Returning to ThriftLine";
  const body = status === "cancel"
    ? "Payment was not completed. Opening ThriftLine…"
    : "Opening ThriftLine to confirm your payment…";

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta http-equiv="refresh" content="0;url=${appUrl}" />
  <title>${title}</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 32px; color: #0f172a; }
    h1 { font-size: 20px; }
    p, a { color: #0d9488; }
  </style>
  <script>
    (function () {
      var appUrl = ${JSON.stringify(appUrl)};
      var intentUrl = ${JSON.stringify(intentUrl)};
      function openApp() {
        window.location.replace(appUrl);
        setTimeout(function () { window.location.replace(intentUrl); }, 120);
      }
      openApp();
    })();
  </script>
</head>
<body>
  <h1>${title}</h1>
  <p>${body}</p>
  <p><a href="${appUrl}">Open ThriftLine</a></p>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
});
