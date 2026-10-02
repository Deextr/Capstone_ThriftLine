const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function readRecoveryParams(url: URL): { tokenHash: string; type: string } {
  const tokenHash = (url.searchParams.get("token_hash") ?? "").trim();
  const type = (url.searchParams.get("type") ?? "recovery").trim() ||
    "recovery";
  return { tokenHash, type };
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }

  const { tokenHash, type } = readRecoveryParams(new URL(req.url));
  const hasToken = tokenHash.length > 0;
  console.log(
    `password-recovery-return method=${req.method} has_token_hash=${hasToken} type=${type}`,
  );

  if (!hasToken) {
    const body =
      "This password reset link is invalid or has expired. Please request a new password reset email from the ThriftLine app.\n";
    return new Response(req.method === "HEAD" ? null : body, {
      status: 400,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  }

  const paramString = new URLSearchParams({
    token_hash: tokenHash,
    type,
  }).toString();
  const appUrl = `thriftline://reset-password?${paramString}`;

  // 200 + Refresh (not 302). A 302 to a custom scheme is followed by Gmail
  // and shown as a blank page; the gateway also strips 302 bodies.
  return new Response(
    req.method === "HEAD"
      ? null
      : "Opening ThriftLine...\n\nIf the app does not open, go back to the email and tap Open ThriftLine.\n",
    {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        Refresh: `0;url=${appUrl}`,
      },
    },
  );
});
