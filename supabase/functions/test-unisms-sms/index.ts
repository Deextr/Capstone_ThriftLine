import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/cors.ts";
import {
  MAX_TEST_SMS_BODY_BYTES,
  defaultTestUnismsDeps,
  handleTestUnismsSmsRequest,
} from "../_shared/unisms_test_sms.ts";

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

  const contentLength = Number(req.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_TEST_SMS_BODY_BYTES) {
    return json(413, {
      error: "Request body is too large.",
      code: "invalid_body",
    });
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
    const userId = !userError && userData.user ? userData.user.id : null;

    let body: unknown = {};
    try {
      const raw = await req.text();
      if (raw.length > MAX_TEST_SMS_BODY_BYTES) {
        return json(413, {
          error: "Request body is too large.",
          code: "invalid_body",
        });
      }
      body = raw.trim().length > 0 ? JSON.parse(raw) : {};
    } catch {
      return json(400, {
        error: "Request body must be valid JSON.",
        code: "invalid_body",
      });
    }

    const deps = defaultTestUnismsDeps(service, userId, async (actorId) => {
      const { data: profile, error: profileError } = await service
        .from("users")
        .select("role, account_status")
        .eq("user_id", actorId)
        .maybeSingle();
      if (profileError) throw profileError;
      if (!profile) return null;
      return {
        role: profile.role as string | null,
        account_status: profile.account_status as string | null,
      };
    });

    const outcome = await handleTestUnismsSmsRequest(body, deps);
    return new Response(JSON.stringify(outcome.body), {
      status: outcome.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("test-unisms-sms", error);
    return json(500, {
      error: "Could not complete the SMS test.",
      code: "unavailable",
    });
  }
});
