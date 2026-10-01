import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/cors.ts";
import { hashDeviceToken, isDeviceToken } from "../_shared/trusted_device.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
    const service = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) {
      return json(401, { error: "Sign in first." });
    }

    let deviceToken: unknown;
    try {
      const body = await req.json();
      deviceToken = body?.device_token;
    } catch {
      deviceToken = null;
    }

    if (!isDeviceToken(deviceToken)) {
      return json(400, { error: "Could not forget this device. Please try again." });
    }

    const deviceHash = await hashDeviceToken(userData.user.id, deviceToken);
    const { error } = await service.rpc("revoke_trusted_device", {
      p_user_id: userData.user.id,
      p_device_token_hash: deviceHash,
    });
    if (error) {
      console.error("revoke-trusted-device failed");
      return json(500, { error: "Could not forget this device. Please try again." });
    }

    return json(200, { ok: true });
  } catch (_error) {
    console.error("revoke-trusted-device failed");
    return json(500, { error: "Could not forget this device. Please try again." });
  }
});
