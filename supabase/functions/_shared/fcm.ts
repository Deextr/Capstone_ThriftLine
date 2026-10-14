type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function base64UrlEncode(data: Uint8Array): string {
  const bin = Array.from(data, (b) => String.fromCharCode(b)).join("");
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(cleaned);
  const buffer = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buffer[i] = raw.charCodeAt(i);
  return buffer.buffer;
}

async function signJwt(
  payload: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const enc = new TextEncoder();
  const headerPart = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadPart = base64UrlEncode(enc.encode(JSON.stringify(payload)));
  const signingInput = `${headerPart}.${payloadPart}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export async function getFcmAccessToken(
  serviceAccount: ServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    {
      iss: serviceAccount.client_email,
      sub: serviceAccount.client_email,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    },
    serviceAccount.private_key,
  );

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    throw new Error(`FCM token exchange failed (${res.status})`);
  }
  const json = await res.json();
  const token = typeof json.access_token === "string" ? json.access_token : "";
  if (!token) throw new Error("FCM token exchange returned no access_token");
  return token;
}

export type FcmDataPayload = Record<string, string>;

export async function sendFcmToDevice(options: {
  projectId: string;
  accessToken: string;
  deviceToken: string;
  title: string;
  body: string;
  data: FcmDataPayload;
}): Promise<{ ok: boolean; status: number; detail: string }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${options.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${options.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: options.deviceToken,
          notification: {
            title: options.title,
            body: options.body,
          },
          data: options.data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "thriftline_alerts",
              icon: "ic_stat_thriftline",
              color: "#0D9488",
            },
          },
        },
      }),
    },
  );
  const text = await res.text();
  return { ok: res.ok, status: res.status, detail: text.slice(0, 500) };
}

export function loadServiceAccountFromEnv(): ServiceAccount | null {
  const raw = (Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "").trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}
