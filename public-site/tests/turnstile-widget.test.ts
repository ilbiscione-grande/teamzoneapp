import { test } from "node:test";
import assert from "node:assert/strict";
import { mountTurnstile, type TurnstileApi } from "../lib/turnstile-widget.ts";

test("a second person gets a fresh widget and cannot reuse callbacks from the first", () => {
  const options: Record<string, unknown>[] = [];
  const removed: string[] = [];
  const reset: string[] = [];
  const api: TurnstileApi = {
    render: (_, settings) => { options.push(settings); return String(options.length); },
    remove: id => { removed.push(id); }, reset: id => { reset.push(id); },
  };
  let token = "";
  const mount = () => mountTurnstile(api, {} as HTMLElement, "key", "intake", value => { token = value; });
  const first = mount();
  (options[0].callback as (value: string) => void)("first");
  assert.equal(token, "first");
  first.dispose();
  first.dispose();
  const second = mount();
  assert.equal(token, "");
  (options[0].callback as (value: string) => void)("stale");
  assert.equal(token, "");
  (options[1].callback as (value: string) => void)("second");
  assert.equal(token, "second");
  second.reset();
  assert.equal(token, "");
  assert.deepEqual(reset, ["2"]);
  second.dispose();
  assert.deepEqual(removed, ["1", "2"]);
});
