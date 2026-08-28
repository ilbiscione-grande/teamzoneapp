import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parseCheckoutRequest } from "../_shared/billing_contract.ts";

const valid = {
  clubId: "a1100000-0000-4000-8000-000000000001",
  planKey: "plan.small",
  interval: "year",
  idempotencyKey: "a1500000-0000-4000-8000-000000000001",
};

Deno.test("accepts only server-known checkout selectors", () => {
  assertEquals(parseCheckoutRequest(valid), valid);
  assertEquals(parseCheckoutRequest({ ...valid, planKey: "plan.custom_xl" }), null);
  assertEquals(parseCheckoutRequest({ ...valid, price: 1 }), null);
});

Deno.test("rejects invalid identifiers and intervals", () => {
  assertEquals(parseCheckoutRequest({ ...valid, clubId: "club" }), null);
  assertEquals(parseCheckoutRequest({ ...valid, interval: "weekly" }), null);
  assertEquals(parseCheckoutRequest({ ...valid, idempotencyKey: "retry" }), null);
});
