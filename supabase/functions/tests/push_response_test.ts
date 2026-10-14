import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  parsePushResponseRequest,
  pushResponseStatus,
} from "../_shared/push_response.ts";

const token = "0123456789abcdef".repeat(4);
const key = "70000000-0000-4000-8000-000000000001";

Deno.test("only a well-formed token and idempotency key pass", () => {
  assertEquals(parsePushResponseRequest({ token, idempotency_key: key }), {
    token,
    idempotencyKey: key,
  });
  assertEquals(parsePushResponseRequest({ token: token.toUpperCase(), idempotency_key: key }), null);
  assertEquals(parsePushResponseRequest({ token: token.slice(1), idempotency_key: key }), null);
  assertEquals(parsePushResponseRequest({ token, idempotency_key: "not-a-uuid" }), null);
  assertEquals(parsePushResponseRequest({ token }), null);
  assertEquals(parsePushResponseRequest([token, key]), null);
  assertEquals(parsePushResponseRequest(null), null);
});

Deno.test("refusals map to what the app does next", () => {
  assertEquals(pushResponseStatus("invalid_input"), 400);
  assertEquals(pushResponseStatus("stale_revision"), 409);
  for (const gone of ["invalid_or_expired_token", "invalid_state", "not_found", "invalid_acting_as"]) {
    assertEquals(pushResponseStatus(gone), 410, gone);
  }
  assertEquals(pushResponseStatus("something else"), 500);
  assertEquals(pushResponseStatus(undefined), 500);
});
