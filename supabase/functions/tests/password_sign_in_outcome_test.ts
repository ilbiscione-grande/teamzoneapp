import { assertEquals } from "jsr:@std/assert@1.0.14";
import { passwordSignInOutcome } from "../_shared/password_sign_in_outcome.ts";

Deno.test("only a session without an error is a successful sign-in", () => {
  assertEquals(passwordSignInOutcome(null, true), "succeeded");
  assertEquals(passwordSignInOutcome(null, false), "failed");
  assertEquals(
    passwordSignInOutcome({ code: "unexpected_failure", status: 500 }, true),
    "failed",
  );
});

Deno.test("credential and account rejections are not availability failures", () => {
  for (
    const code of [
      "invalid_credentials",
      "email_not_confirmed",
      "phone_not_confirmed",
      "user_banned",
    ]
  ) {
    assertEquals(
      passwordSignInOutcome({ code, status: 400 }, false),
      "rejected",
    );
  }
});

Deno.test("rate limits remain separate from outages", () => {
  assertEquals(
    passwordSignInOutcome(
      { code: "over_request_rate_limit", status: 429 },
      false,
    ),
    "limited",
  );
});

Deno.test("transport, server, configuration and unknown errors remain failures", () => {
  for (
    const error of [
      { status: 0 },
      { status: 502 },
      { status: 504 },
      { code: "unexpected_failure", status: 500 },
      { code: "request_timeout", status: 408 },
      { code: "email_provider_disabled", status: 400 },
      { code: "new_unknown_error", status: 400 },
      { code: "invalid_credentials", status: 503 },
      {},
    ]
  ) {
    assertEquals(passwordSignInOutcome(error, false), "failed");
  }
});
