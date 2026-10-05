import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  maskPhMobile,
  normalizePhPhone,
  sendUnisms,
} from "../_shared/phone_otp.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_TEST_CONTENT = "ThriftLine UniSMS connectivity test.";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

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
      return json(401, { error: "Sign in first.", code: "unauthenticated" });
    }

    const { data: profile, error: profileError } = await service
      .from("users")
      .select("role")
      .eq("user_id", userData.user.id)
      .maybeSingle();

    if (profileError) throw profileError;
    if (profile?.role !== "admin") {
      return json(403, {
        error: "Admin access required for SMS connectivity tests.",
        code: "forbidden",
      });
    }

    const body = await req.json();
    const phone = normalizePhPhone(String(body.phone ?? ""));
    if (!phone) {
      return json(400, {
        error: "Enter a valid 11-digit mobile number starting with 09.",
        code: "invalid_phone",
      });
    }

    const content =
      typeof body.content === "string" && body.content.trim().length > 0
        ? body.content.trim().slice(0, 670)
        : DEFAULT_TEST_CONTENT;

    console.log("test-unisms-sms request", {
      admin: userData.user.id.slice(0, 8),
      phone: maskPhMobile(phone),
    });

    const result = await sendUnisms(phone, content);

    return json(result.accepted ? 200 : 502, {
      ok: result.accepted,
      http_status: result.status,
      reference_id: result.referenceId ?? null,
      delivery_status: result.deliveryStatus ?? null,
      code: result.code ?? null,
      error: result.accepted ? null : result.userMessage,
    });
  } catch (error) {
    console.error("test-unisms-sms", error);
    return json(500, {
      error: "Could not complete the SMS test.",
      code: "unavailable",
    });
  }
});
