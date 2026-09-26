import assert from "node:assert/strict";
import test from "node:test";
import { isLocalPublicView } from "../lib/local-public-view.ts";

test("local public view needs explicit development opt-in and exact loopback host", () => {
  const enabled = { NODE_ENV: "development", TEAMZONE_LOCAL_PUBLIC_VIEW: "1" } as const;
  for (const host of ["localhost:5001", "[::1]:5001", "127.0.0.1:5001"]) {
    assert.equal(isLocalPublicView(host, enabled), true);
    assert.equal(isLocalPublicView(host, { ...enabled, NODE_ENV: "production" }), false);
    assert.equal(isLocalPublicView(host, { NODE_ENV: "development" }), false);
  }
  for (const host of [null, "teamzoneapp.se", "localhost:5000", "localhost.example:5001", "0.0.0.0:5001"]) {
    assert.equal(isLocalPublicView(host, enabled), false);
  }
});
