import assert from "node:assert/strict";
import test from "node:test";
import { createRequire } from "node:module";
import { invalidServerActionResponse } from "../lib/server-action-request.ts";

const require = createRequire(import.meta.url);
const { mightBeServerReferenceId } = require("next/dist/shared/lib/server-reference-info.js");

test("rejects the reported cachefn probe before parsing its body", async () => {
  const request = new Request("https://teamzoneapp.se/?_rsc=probe", {
    method: "POST", headers: { "next-action": "cachefn" }, body: "not valid JSON",
  });
  const response = invalidServerActionResponse(request);
  assert.equal(response?.status, 400);
  assert.equal(response?.headers.get("cache-control"), "no-store");
  assert.equal(await response?.text(), "Bad Request");
  assert.equal(request.bodyUsed, false);
});

test("boundary matches the installed Next version's reference format check", () => {
  for (const id of ["", "x", "cachefn", "a".repeat(41), "0".repeat(42), "a".repeat(43), "x".repeat(10000)]) {
    const request = new Request("https://teamzoneapp.se/", {
      method: "POST", headers: { "next-action": id },
    });
    assert.equal(invalidServerActionResponse(request) === null, mightBeServerReferenceId(id));
  }
});

test("ordinary navigation, API posts and forms without action headers pass through", () => {
  for (const method of ["GET", "HEAD", "POST", "OPTIONS"]) {
    const request = new Request("https://teamzoneapp.se/api/public/v1/contact", { method });
    assert.equal(invalidServerActionResponse(request), null);
  }
  const navigation = new Request("https://teamzoneapp.se/", { headers: { "next-action": "cachefn" } });
  assert.equal(invalidServerActionResponse(navigation), null);
});
