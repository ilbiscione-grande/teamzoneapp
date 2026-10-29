import assert from "node:assert/strict";
import { test } from "node:test";
import { createBookingCommands, bookingRevisions } from "../lib/booking-command.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Booking } from "../lib/booking.ts";

test("an uncertain response keeps its command ID; a new intent gets a new ID", async () => {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  let fail = true;
  let sequence = 0;
  const execute = createBookingCommands(() => `command-${++sequence}`);
  const client = { schema: () => ({ rpc: async (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args });
    return { data: fail ? null : { id: "booking" }, error: fail ? { message: "lost response" } : null };
  } }) } as unknown as SupabaseClient;
  const payload = { target_resource_id: "resource", booking_starts_at: "start" };
  await execute(client, "create_booking", payload);
  fail = false;
  await execute(client, "create_booking", payload);
  assert.equal(calls[0].args.command_id, calls[1].args.command_id);
  await execute(client, "create_booking", payload);
  assert.notEqual(calls[1].args.command_id, calls[2].args.command_id);
  await execute(client, "create_booking_group", { dry_run: true });
  assert.equal(calls[3].name, "create_booking_group", "preview never enters command ledger");
});

test("single decisions send one revision; group and series decisions send the whole vector", () => {
  const booking = { id: "one", revision: 3, revisions: { one: 3, two: 5 } } as unknown as Booking;
  assert.deepEqual(bookingRevisions(booking, "decide_booking"), { one: 3 });
  assert.deepEqual(bookingRevisions(booking, "cancel_booking_group"), { one: 3, two: 5 });
  assert.deepEqual(bookingRevisions(booking, "decide_booking_series"), { one: 3, two: 5 });
});
