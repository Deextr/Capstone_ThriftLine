const APP_PACKAGE = "com.example.thriftline";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/**
 * After /auth/v1/verify, GoTrue redirects here with session tokens in the URL
 * hash. Gmail's browser cannot open thriftline:// directly (blank tab). This
 * page moves tokens into query parameters and opens the app via intent:// so
 * Android passes them to Flutter (fragments are often dropped on intents).
 */
Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Opening ThriftLine</title>
</head>
<body style="margin:0;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#F8FAFC;color:#0F172A;">
  <div style="max-width:420px;margin:48px auto;padding:24px;text-align:center;">
    <p style="font-size:18px;font-weight:600;">Opening ThriftLine…</p>
    <p style="font-size:14px;color:#64748B;line-height:1.5;">
      Return to the app to choose a new password.
    </p>
    <p id="fallback" style="display:none;margin-top:24px;">
      <a id="open-app" href="#" style="color:#0D9488;font-weight:600;">Open ThriftLine</a>
    </p>
  </div>
  <script>
(function () {
  var hash = (window.location.hash || "").replace(/^#/, "");
  var search = (window.location.search || "").replace(/^\\?/, "");
  var paramString = hash || search;
  if (!paramString) {
    document.body.insertAdjacentHTML("beforeend",
      '<p style="text-align:center;color:#64748B;">This link is invalid or has expired. Request a new reset email from the app.</p>');
    return;
  }
  var appUrl = "thriftline://reset-password?" + paramString;
  var intentUrl =
    "intent://reset-password?" + paramString +
    "#Intent;scheme=thriftline;package=${APP_PACKAGE};end";
  try { window.location.replace(intentUrl); } catch (e) {}
  setTimeout(function () {
    try { window.location.replace(appUrl); } catch (e) {}
  }, 150);
  setTimeout(function () {
    var link = document.getElementById("open-app");
    var fb = document.getElementById("fallback");
    if (link) link.href = appUrl;
    if (fb) fb.style.display = "block";
  }, 900);
})();
  </script>
</body>
</html>`;

  return new Response(req.method === "HEAD" ? null : html, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
});
