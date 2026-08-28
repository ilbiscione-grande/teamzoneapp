const test = require("node:test");
const assert = require("node:assert/strict");
const {sanitizedBreach} = require("./bridge");

test("accepts only the approved aggregate fields", () => {
  assert.deepEqual(sanitizedBreach({
    flow: "checkout", attempts: 20, failure_rate_percent: 5, window_minutes: 5,
    email: "must-not-pass@example.com", payload: "must-not-pass",
  }), {
    event: "teamzone.alert.critical_flow", flow: "checkout", attempts: 20,
    failure_rate_percent: 5, window_minutes: 5,
  });
});

test("rejects unknown flows, sub-threshold rates and wrong windows", () => {
  assert.equal(sanitizedBreach({flow: "other", attempts: 1, failure_rate_percent: 100, window_minutes: 5}), null);
  assert.equal(sanitizedBreach({flow: "auth", attempts: 20, failure_rate_percent: 4.99, window_minutes: 5}), null);
  assert.equal(sanitizedBreach({flow: "auth", attempts: 20, failure_rate_percent: 5, window_minutes: 10}), null);
});
