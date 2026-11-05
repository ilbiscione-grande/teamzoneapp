import assert from "node:assert/strict";
import test from "node:test";
import { tacticsboardOnlyRedirect } from "../lib/site-scope.ts";

test("the start page and the other apps lead to Tacticsboard", () => {
  for (const path of ["/", "/bokningar", "/bokningar/abc", "/turneringar", "/turneringar/abc", "/turnering/abc",
    "/aviseringar", "/appar/video-analyzer", "/appar/bokningshanterare"]) {
    assert.equal(tacticsboardOnlyRedirect(path), "/tacticsboard", path);
  }
});

test("Tacticsboard and the account stay", () => {
  for (const path of ["/tacticsboard", "/tacticsboard/bibliotek", "/appar/tacticsboard", "/konto", "/logga-in",
    "/delad/abc", "/live/ABCDEF", "/bokningarna"]) {
    assert.equal(tacticsboardOnlyRedirect(path), null, path);
  }
});
