// Firebase Cloud Messaging (HTTP v1) for notification-worker. The service
// account JSON comes from the FCM_SERVICE_ACCOUNT_JSON secret; nothing here
// logs tokens, titles or bodies.

export type ServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

/// response: the single-use token for answering a callup from the
/// notification (internal.push_message_for_outbox), when it can be answered.
export type PushContent = {
  title: string;
  body: string;
  route: string;
  response?: { callup_id: string; token: string } | null;
  /// The single-use token for replying to a message from its notification.
  reply?: { thread_id: string; token: string } | null;
  language?: string;
};

export type SendResult =
  | { kind: "sent"; name: string }
  | { kind: "unregistered" }
  | { kind: "retryable"; code: string }
  | { kind: "rejected"; code: string };

/// Notifications older than this are not sent any more (a backlog must
/// never reach phones when push is switched on).
export const staleAfterMs = 6 * 60 * 60 * 1000;

export function isStale(createdAt: string, now = Date.now()): boolean {
  const created = Date.parse(createdAt);
  return !Number.isFinite(created) || now - created > staleAfterMs;
}

export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const json = JSON.parse(raw);
    if (
      typeof json.project_id !== "string" ||
      typeof json.client_email !== "string" ||
      typeof json.private_key !== "string"
    ) return null;
    return {
      projectId: json.project_id,
      clientEmail: json.client_email,
      privateKey: json.private_key,
    };
  } catch {
    return null;
  }
}

/// Only in-app routes the app itself understands are passed on.
export function safeRoute(route: unknown): string {
  return typeof route === "string" &&
      /^\/(calendar\/event\/[0-9a-fA-F-]{36}|inbox(\?thread=[0-9a-fA-F-]{36})?)$/
        .test(route)
    ? route
    : "/inbox";
}

const CALLUP_ID = /^[0-9a-fA-F-]{36}$/;
const RESPONSE_TOKEN = /^[0-9a-f]{64}$/;

/// An answerable callup or a message one can reply to is a data message on
/// Android: the app draws it with its buttons ("Kommer" / "Kan inte…",
/// "Svara"). Everything else (and iOS, until its actions exist) is a plain
/// notification.
export function fcmMessage(token: string, content: PushContent, platform = "android") {
  const response = content.response;
  const reply = content.reply;
  if (
    platform === "android" && reply &&
    CALLUP_ID.test(reply.thread_id) && RESPONSE_TOKEN.test(reply.token)
  ) {
    return {
      message: {
        token,
        data: {
          kind: "message",
          title: content.title,
          body: content.body,
          route: safeRoute(content.route),
          thread_id: reply.thread_id,
          reply_token: reply.token,
          language: content.language === "en" ? "en" : "sv",
        },
        android: { priority: "HIGH" },
      },
    };
  }
  if (
    platform === "android" && response &&
    CALLUP_ID.test(response.callup_id) && RESPONSE_TOKEN.test(response.token)
  ) {
    return {
      message: {
        token,
        data: {
          kind: "callup",
          title: content.title,
          body: content.body,
          route: safeRoute(content.route),
          callup_id: response.callup_id,
          response_token: response.token,
          language: content.language === "en" ? "en" : "sv",
        },
        android: { priority: "HIGH" },
      },
    };
  }
  return {
    message: {
      token,
      notification: { title: content.title, body: content.body },
      data: { route: safeRoute(content.route) },
      android: { priority: "HIGH" },
      apns: { payload: { aps: { sound: "default" } } },
    },
  };
}

/// Maps an FCM error response to what the worker does next.
export function classifyFcmError(status: number, body: unknown): SendResult {
  const error = (body as { error?: { status?: string; details?: unknown[] } })
    ?.error;
  const detailCodes = (error?.details ?? [])
    .map((detail) => (detail as { errorCode?: string })?.errorCode)
    .filter((code): code is string => typeof code === "string");
  const code = detailCodes[0] ?? error?.status ?? `http_${status}`;
  if (status === 404 || detailCodes.includes("UNREGISTERED")) {
    return { kind: "unregistered" };
  }
  if (status === 429 || status >= 500) return { kind: "retryable", code };
  return { kind: "rejected", code };
}

function base64Url(bytes: Uint8Array | string): string {
  const binary = typeof bytes === "string"
    ? bytes
    : String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0)).buffer;
}

/// The signed JWT that Google exchanges for an FCM access token.
export async function serviceAccountJwt(
  account: ServiceAccount,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: account.clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(account.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  return `${header}.${claims}.${base64Url(signature)}`;
}

/// An OAuth access token for FCM from the service account (JWT bearer).
export async function fcmAccessToken(account: ServiceAccount): Promise<string> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await serviceAccountJwt(account),
    }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || typeof json.access_token !== "string") {
    throw new Error(`fcm_auth_${response.status}`);
  }
  return json.access_token;
}

export async function sendFcm(
  account: ServiceAccount,
  accessToken: string,
  token: string,
  content: PushContent,
  platform = "android",
): Promise<SendResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(fcmMessage(token, content, platform)),
    },
  );
  const json = await response.json().catch(() => ({}));
  if (response.ok && typeof json.name === "string") {
    return { kind: "sent", name: json.name };
  }
  return classifyFcmError(response.status, json);
}
