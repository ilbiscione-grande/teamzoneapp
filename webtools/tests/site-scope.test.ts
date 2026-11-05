import assert from "node:assert/strict";
import test from "node:test";
import { tacticsboardOnlyRedirect } from "../lib/site-scope.ts";

test("the other apps lead back to the start page", () => {
  for (const path of ["/bokningar", "/bokningar/abc", "/turneringar", "/turneringar/abc", "/turnering/abc",
    "/aviseringar", "/appar/video-analyzer", "/appar/bokningshanterare"]) {
    assert.equal(tacticsboardOnlyRedirect(path), "/", path);
  }
});

test("the start page, Tacticsboard and the account stay", () => {
  for (const path of ["/", "/tacticsboard", "/tacticsboard/bibliotek", "/appar/tacticsboard", "/konto", "/logga-in",
    "/delad/abc", "/live/ABCDEF", "/bokningarna"]) {
    assert.equal(tacticsboardOnlyRedirect(path), null, path);
  }
});
