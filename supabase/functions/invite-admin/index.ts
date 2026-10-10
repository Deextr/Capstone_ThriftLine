import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
import { json } from "../_shared/cors.ts";

const BRAND_PRIMARY = "#0D9488";
const BRAND_TEXT = "#0F172A";
const BRAND_MUTED = "#64748B";

const buyerOrSellerMessage =
  "This email address is already registered in ThriftLine. Please use a different email address to create an administrator account.";
const existingAccountMessage =
  "This email address is already associated with an existing ThriftLine account.";
const pendingMessage =
  "An invitation has already been sent to this email address.";

function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

function isEmail(value: string): boolean {
  if (value.length === 0 || value.length > 320) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function adminPortalBase(): string {
  return (Deno.env.get("ADMIN_PORTAL_URL") ?? "").trim().replace(/\/$/, "");
}

function acceptUrl(): string {
  const base = adminPortalBase();
  if (!base.startsWith("https://") && !base.startsWith("http://localhost")) {
    return "";
  }
  return `${base}/admin/accept-invite`;
}

async function sendInviteEmail(
  to: string,
  fullName: string,
  actionLink: string,
): Promise<void> {
  const username = Deno.env.get("GMAIL_USER") ?? "";
  const password = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
  if (!username.trim() || !password.trim()) {
    throw new Error("gmail smtp is not configured");
  }

  const safeName = escapeHtml(fullName);
  const href = escapeHtml(actionLink);
  const html = `<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:0;background:#F8FAFC;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F8FAFC;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:480px;background:#FFFFFF;border-radius:12px;border:1px solid #E2E8F0;">
        <tr><td style="padding:32px 28px;">
          <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:${BRAND_TEXT};">ThriftLine</p>
          <p style="margin:0 0 16px;font-size:16px;line-height:1.5;color:${BRAND_TEXT};">
            Hello ${safeName}, you have been invited to administer ThriftLine.
          </p>
          <p style="margin:0 0 24px;font-size:15px;line-height:1.5;color:${BRAND_MUTED};">
            Open the admin portal and choose a password. This link expires in 7 days and can only be used once.
          </p>
          <table role="presentation" cellspacing="0" cellpadding="0">
            <tr><td style="border-radius:8px;background:${BRAND_PRIMARY};">
              <a href="${href}" style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:8px;">
                Set up your admin account
              </a>
            </td></tr>
          </table>
          <p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:${BRAND_MUTED};">
            Administrator accounts use the ThriftLine Admin web dashboard. If you were not expecting this invitation, you can ignore this email.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  const client = new SMTPClient({
    connection: {
      hostname: "smtp.gmail.com",
      port: 465,
      tls: true,
      auth: { username, password },
    },
  });

  try {
    await client.send({
      from: `ThriftLine <${username}>`,
      to,
      subject: "You are invited to ThriftLine Admin",
      content:
        `Hello ${fullName},\n\n` +
        "You have been invited to administer ThriftLine.\n\n" +
        "Open this link to choose a password:\n" +
        `${actionLink}\n\n` +
        "This link expires in 7 days and can only be used once.\n",
      html,
    });
  } finally {
    await client.close();
  }
}

async function signOutUser(
  service: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!base || !serviceKey || !userId) return;
  const response = await fetch(`${base}/auth/v1/admin/users/${userId}/logout`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      apikey: serviceKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ scope: "global" }),
  });
  if (!response.ok && response.status !== 404) {
    console.error(`invite-admin sign-out failed status=${response.status}`);
  }
  void service;
}

async function inviteLink(
  service: ReturnType<typeof createClient>,
  email: string,
  fullName: string,
  existingUser: boolean,
): Promise<{ actionLink: string; userId: string } | { error: string }> {
  const redirectTo = acceptUrl();
  const { data, error } = await service.auth.admin.generateLink({
    type: existingUser ? "recovery" : "invite",
    email,
    options: {
      redirectTo,
      data: { full_name: fullName },
    },
  });
  const actionLink = data?.properties?.action_link?.trim() ?? "";
  const userId = data?.user?.id ?? "";
  if (error || !actionLink.startsWith("http") || !userId) {
    const code = error && "code" in error ? String(error.code ?? "") : "";
    console.error(`invite-admin link failed code=${code}`);
    return { error: "link_failed" };
  }
  return { actionLink, userId };
}

function lookupMessage(result: string): { status: number; error: string; code: string } | null {
  switch (result) {
    case "available":
      return null;
    case "buyer_or_seller":
      return { status: 409, error: buyerOrSellerMessage, code: "buyer_or_seller" };
    case "administrator":
    case "auth_only":
      return { status: 409, error: existingAccountMessage, code: result };
    case "invitation_pending":
      return { status: 409, error: pendingMessage, code: "invitation_pending" };
    case "invalid_email":
      return { status: 400, error: "Enter a valid email address.", code: "invalid_email" };
    default:
      return { status: 500, error: "Could not check that email address.", code: "lookup_failed" };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
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
      return json(401, { error: "Sign in first.", code: "unauthorized" });
    }
    const actorId = userData.user.id;

    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }
    const action = typeof body.action === "string" ? body.action : "";

    if (action === "create") {
      const email = normalizeEmail(typeof body.email === "string" ? body.email : "");
      const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
      if (!isEmail(email)) {
        return json(400, { error: "Enter a valid email address.", code: "invalid_email" });
      }
      if (fullName.length < 2 || fullName.length > 80) {
        return json(400, { error: "Enter the administrator's full name.", code: "invalid_name" });
      }
      if (!acceptUrl()) {
        console.error("invite-admin ADMIN_PORTAL_URL is not configured");
        return json(500, {
          error: "Admin invitations are not configured yet.",
          code: "not_configured",
        });
      }

      const { data: lookup, error: lookupError } = await service.rpc(
        "lookup_admin_invite_email",
        { p_actor: actorId, p_email: email },
      );
      if (lookupError || !lookup || typeof lookup !== "object") {
        console.error("invite-admin lookup failed");
        return json(403, { error: "You cannot create administrator accounts.", code: "forbidden" });
      }
      const result = String((lookup as { result?: string }).result ?? "");
      const mapped = lookupMessage(result);
      if (mapped) {
        const invitationId = (lookup as { invitation_id?: string }).invitation_id;
        return json(mapped.status, {
          error: mapped.error,
          code: mapped.code,
          ...(invitationId ? { invitation_id: invitationId } : {}),
        });
      }

      const { data: invitationId, error: beginError } = await service.rpc(
        "begin_admin_invitation",
        { p_actor: actorId, p_email: email, p_full_name: fullName },
      );
      if (beginError || typeof invitationId !== "string") {
        const message = beginError?.message ?? "";
        if (message.includes("invitation pending")) {
          return json(409, { error: pendingMessage, code: "invitation_pending" });
        }
        if (message.includes("super admin")) {
          return json(403, { error: "You cannot create administrator accounts.", code: "forbidden" });
        }
        console.error("invite-admin begin failed");
        return json(500, { error: "Could not create the invitation.", code: "invite_failed" });
      }

      const link = await inviteLink(service, email, fullName, false);
      if ("error" in link) {
        await service.rpc("abandon_admin_invitation", {
          p_actor: actorId,
          p_invitation_id: invitationId,
        });
        return json(500, {
          error: "Could not create the administrator account.",
          code: "link_failed",
        });
      }

      let attached = false;
      let attachMessage = "";
      for (let attempt = 0; attempt < 5; attempt++) {
        const { error: attachError } = await service.rpc("attach_invited_admin", {
          p_actor: actorId,
          p_invitation_id: invitationId,
          p_auth_user_id: link.userId,
        });
        if (!attachError) {
          attached = true;
          break;
        }
        attachMessage = attachError.message ?? "";
        if (!attachMessage.includes("profile not ready")) break;
        await new Promise((resolve) => setTimeout(resolve, 300));
      }
      if (!attached) {
        await service.auth.admin.deleteUser(link.userId);
        await service.rpc("abandon_admin_invitation", {
          p_actor: actorId,
          p_invitation_id: invitationId,
        });
        console.error("invite-admin attach failed");
        return json(500, {
          error: "Could not create the administrator account.",
          code: "attach_failed",
        });
      }

      try {
        await sendInviteEmail(email, fullName, link.actionLink);
      } catch {
        console.error("invite-admin smtp failed");
        return json(502, {
          error: "The account was created, but the invitation email could not be sent. Use Resend.",
          code: "email_failed",
          invitation_id: invitationId,
        });
      }

      return json(200, { ok: true, invitation_id: invitationId });
    }

    if (action === "resend") {
      const invitationId = typeof body.invitation_id === "string" ? body.invitation_id : "";
      if (!invitationId) {
        return json(400, { error: "Choose an invitation to resend.", code: "invalid_request" });
      }
      if (!acceptUrl()) {
        return json(500, {
          error: "Admin invitations are not configured yet.",
          code: "not_configured",
        });
      }
      const { data: prepared, error: prepareError } = await service.rpc(
        "prepare_admin_invitation_resend",
        { p_actor: actorId, p_invitation_id: invitationId },
      );
      if (prepareError || !prepared || typeof prepared !== "object") {
        const message = prepareError?.message ?? "";
        if (message.includes("super admin")) {
          return json(403, { error: "You cannot manage administrator accounts.", code: "forbidden" });
        }
        return json(400, {
          error: "This invitation cannot be resent.",
          code: "resend_failed",
        });
      }
      const email = String((prepared as { email?: string }).email ?? "");
      const fullName = String((prepared as { full_name?: string }).full_name ?? "");
      const existingUser = Boolean((prepared as { auth_user_id?: string }).auth_user_id);
      const link = await inviteLink(service, email, fullName, existingUser);
      if ("error" in link) {
        return json(500, { error: "Could not resend the invitation.", code: "link_failed" });
      }
      try {
        await sendInviteEmail(email, fullName, link.actionLink);
      } catch {
        return json(502, {
          error: "Could not send the invitation email. Try again.",
          code: "email_failed",
        });
      }
      return json(200, { ok: true });
    }

    if (action === "revoke_invitation") {
      const invitationId = typeof body.invitation_id === "string" ? body.invitation_id : "";
      const { data: authUserId, error } = await service.rpc("revoke_admin_invitation", {
        p_actor: actorId,
        p_invitation_id: invitationId,
      });
      if (error) {
        const message = error.message ?? "";
        if (message.includes("super admin")) {
          return json(403, { error: "You cannot manage administrator accounts.", code: "forbidden" });
        }
        return json(400, { error: "This invitation cannot be revoked.", code: "revoke_failed" });
      }
      if (typeof authUserId === "string" && authUserId.length > 0) {
        await signOutUser(service, authUserId);
      }
      return json(200, { ok: true });
    }

    if (action === "deactivate" || action === "reactivate") {
      const targetId = typeof body.user_id === "string" ? body.user_id : "";
      const { error } = await service.rpc("set_admin_account_active", {
        p_actor: actorId,
        p_target: targetId,
        p_active: action === "reactivate",
      });
      if (error) {
        const message = error.message ?? "";
        if (message.includes("last active super admin")) {
          return json(409, {
            error: "The last active Super Admin cannot be deactivated.",
            code: "last_super_admin",
          });
        }
        if (message.includes("super admin") || message.includes("cannot be changed")) {
          return json(403, {
            error: "That administrator account cannot be changed.",
            code: "forbidden",
          });
        }
        return json(400, {
          error: "Could not update that administrator.",
          code: "status_failed",
        });
      }
      if (action === "deactivate") {
        await signOutUser(service, targetId);
      }
      return json(200, { ok: true });
    }

    return json(400, { error: "Unknown action.", code: "invalid_request" });
  } catch (error) {
    console.error("invite-admin failed", error);
    return json(500, { error: "Could not complete that request.", code: "unavailable" });
  }
});
