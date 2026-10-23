import { assertEquals } from "jsr:@std/assert@1.0.14";

Deno.test("sign-in endpoint separates operational failures from denied credentials", async () => {
  const originalFetch = globalThis.fetch;
  const originalServe = Deno.serve;
  const environment: Record<string, string> = {
    SUPABASE_URL: "https://auth-test.invalid",
    SUPABASE_PUBLISHABLE_KEYS: '{"default":"test-publishable"}',
    SUPABASE_SECRET_KEYS: '{"default":"test-secret"}',
    TEAMZONE_EXTRA_WEB_ORIGINS: "",
  };
  const previous = Object.fromEntries(
    Object.keys(environment).map((key) => [key, Deno.env.get(key)]),
  );
  let handler: (request: Request) => Promise<Response>;
  let authStatus = 400;
  let authCode = "invalid_credentials";
  const calls: { name: string; body: Record<string, unknown> }[] = [];
  try {
    for (const [key, value] of Object.entries(environment)) {
      Deno.env.set(key, value);
    }
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: (fn: typeof handler) => {
        handler = fn;
      },
    });
    globalThis.fetch = (input, init) => {
      const url = String(input);
      if (!url.startsWith("https://auth-test.invalid/")) {
        throw new Error("unexpected_test_url");
      }
      if (url.includes("/auth/v1/token")) {
        const body = authStatus === 200
          ? {
            access_token: "test-access",
            refresh_token: "test-refresh",
            token_type: "bearer",
            expires_in: 3600,
            user: { id: "test-user" },
          }
          : { code: authCode, error_code: authCode, msg: "test error" };
        return Promise.resolve(Response.json(body, { status: authStatus }));
      }
      const name = url.split("/").pop()!;
      calls.push({ name, body: JSON.parse(String(init?.body)) });
      return Promise.resolve(
        Response.json(name === "sign_in_attempt_allowed" ? true : null),
      );
    };
    await import("../auth-password-sign-in/index.ts");
    for (
      const scenario of [
        {
          status: 400,
          code: "invalid_credentials",
          response: 401,
          counter: null,
          limit: false,
        },
        {
          status: 400,
          code: "email_not_confirmed",
          response: 401,
          counter: null,
          limit: false,
        },
        {
          status: 429,
          code: "over_request_rate_limit",
          response: 429,
          counter: null,
          limit: null,
        },
        {
          status: 500,
          code: "unexpected_failure",
          response: 503,
          counter: "failed",
          limit: null,
        },
        {
          status: 400,
          code: "new_unknown_error",
          response: 503,
          counter: "failed",
          limit: null,
        },
        {
          status: 200,
          code: "",
          response: 200,
          counter: "succeeded",
          limit: true,
        },
      ]
    ) {
      authStatus = scenario.status;
      authCode = scenario.code;
      calls.length = 0;
      const response = await handler!(
        new Request("https://function.invalid/", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            email: "test@example.invalid",
            password: "test-password",
          }),
        }),
      );
      assertEquals(response.status, scenario.response, scenario.code);
      const outcomes = calls.filter((call) =>
        call.name === "record_critical_flow_outcome"
      );
      assertEquals(
        outcomes.map((call) => call.body.target_result),
        scenario.counter ? [scenario.counter] : [],
      );
      const limits = calls.filter((call) =>
        call.name === "record_sign_in_result"
      );
      assertEquals(
        limits.map((call) => call.body.succeeded),
        scenario.limit === null ? [] : [scenario.limit],
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
    Object.defineProperty(Deno, "serve", {
      configurable: true,
      value: originalServe,
    });
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
