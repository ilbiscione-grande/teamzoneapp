import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  classifyFcmError,
  fcmMessage,
  isStale,
  parseServiceAccount,
  safeRoute,
  serviceAccountJwt,
  staleAfterMs,
} from "../_shared/fcm.ts";

Deno.test("the message carries title, body and a safe in-app route only", () => {
  const message = fcmMessage("device-token", {
    title: "Ny kallelse",
    body: "Träning · P2012 · lör 17 okt 18:00",
    route: "/calendar/event/30000000-0000-4000-8000-000000000001",
  });
  assertEquals(message.message.token, "device-token");
  assertEquals(message.message.notification, {
    title: "Ny kallelse",
    body: "Träning · P2012 · lör 17 okt 18:00",
  });
  assertEquals(
    message.message.data.route,
    "/calendar/event/30000000-0000-4000-8000-000000000001",
  );
});

Deno.test("an answerable callup is a data message on Android only", () => {
  const callup = {
    title: "Ny kallelse",
    body: "Träning · P2012 · lör 17 okt 18:00",
    route: "/calendar/event/30000000-0000-4000-8000-000000000001",
    response: { callup_id: "60000000-0000-4000-8000-000000000001", token: "a".repeat(64) },
    language: "sv",
  };
  const android = fcmMessage("device-token", callup, "android").message as Record<string, unknown>;
  assertEquals(android.notification, undefined, "the app draws it with its buttons");
  assertEquals(android.data, {
    kind: "callup",
    title: "Ny kallelse",
    body: "Träning · P2012 · lör 17 okt 18:00",
    route: "/calendar/event/30000000-0000-4000-8000-000000000001",
    callup_id: "60000000-0000-4000-8000-000000000001",
    response_token: "a".repeat(64),
    language: "sv",
  });
  const ios = fcmMessage("device-token", callup, "ios").message as Record<string, unknown>;
  assertEquals((ios.data as Record<string, string>).response_token, undefined, "no token without iOS actions");
  const malformed = fcmMessage("device-token", { ...callup, response: { callup_id: "x", token: "y" } });
  assertEquals((malformed.message as Record<string, unknown>).notification !== undefined, true);
});

Deno.test("a message one can reply to is a data message on Android only", () => {
  const message = {
    title: "Nytt meddelande",
    body: "P2012",
    route: "/inbox?thread=40000000-0000-4000-8000-000000000001",
    reply: { thread_id: "40000000-0000-4000-8000-000000000001", token: "b".repeat(64) },
    language: "en",
  };
  const android = fcmMessage("device-token", message, "android").message as Record<string, unknown>;
  assertEquals(android.notification, undefined);
  assertEquals(android.data, {
    kind: "message",
    title: "Nytt meddelande",
    body: "P2012",
    route: "/inbox?thread=40000000-0000-4000-8000-000000000001",
    thread_id: "40000000-0000-4000-8000-000000000001",
    reply_token: "b".repeat(64),
    language: "en",
  });
  const ios = fcmMessage("device-token", message, "ios").message as Record<string, unknown>;
  assertEquals((ios.data as Record<string, string>).reply_token, undefined);
});

Deno.test("routes outside the app's own paths fall back to the inbox", () => {
  assertEquals(safeRoute("/inbox?thread=40000000-0000-4000-8000-000000000001"),
    "/inbox?thread=40000000-0000-4000-8000-000000000001");
  assertEquals(safeRoute("https://evil.example"), "/inbox");
  assertEquals(safeRoute("/calendar/event/../../admin"), "/inbox");
  assertEquals(safeRoute(null), "/inbox");
});

Deno.test("FCM errors decide between disabling, retrying and giving up", () => {
  assertEquals(classifyFcmError(404, {}), { kind: "unregistered" });
  assertEquals(
    classifyFcmError(400, { error: { status: "INVALID_ARGUMENT", details: [{ errorCode: "UNREGISTERED" }] } }),
    { kind: "unregistered" },
  );
  assertEquals(classifyFcmError(503, { error: { status: "UNAVAILABLE" } }), {
    kind: "retryable",
    code: "UNAVAILABLE",
  });
  assertEquals(classifyFcmError(429, {}), { kind: "retryable", code: "http_429" });
  assertEquals(classifyFcmError(400, { error: { status: "INVALID_ARGUMENT" } }), {
    kind: "rejected",
    code: "INVALID_ARGUMENT",
  });
});

Deno.test("old notifications are stale and never sent", () => {
  const now = Date.parse("2026-10-13T12:00:00Z");
  assert(!isStale(new Date(now - 60_000).toISOString(), now));
  assert(isStale(new Date(now - staleAfterMs - 1).toISOString(), now));
  assert(isStale("not a date", now));
});

Deno.test("the service account needs project, e-mail and key", () => {
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount("not json"), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: "p" })), null);
  assertEquals(
    parseServiceAccount(JSON.stringify({ project_id: "p", client_email: "e", private_key: "k" })),
    { projectId: "p", clientEmail: "e", privateKey: "k" },
  );
});

Deno.test("the service account JWT is signed with the account's key", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  // Service account JSON stores the PEM with escaped newlines.
  const pem = "-----BEGIN PRIVATE KEY-----\\n" +
    btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, "$1\\n") +
    "\\n-----END PRIVATE KEY-----\\n";
  const jwt = await serviceAccountJwt(
    { projectId: "p", clientEmail: "worker@p.iam.gserviceaccount.com", privateKey: pem },
    1_800_000_000,
  );
  const [header, claims, signature] = jwt.split(".");
  const decode = (part: string) =>
    Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    pair.publicKey,
    decode(signature),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert(verified);
  const payload = JSON.parse(new TextDecoder().decode(decode(claims)));
  assertEquals(payload.iss, "worker@p.iam.gserviceaccount.com");
  assertEquals(payload.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(payload.exp - payload.iat, 3600);
});
