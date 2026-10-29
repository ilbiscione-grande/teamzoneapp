import type { SupabaseClient } from "@supabase/supabase-js";
import type { Booking } from "./booking";

export function bookingRevisions(booking: Booking, command: string): Record<string, number> {
  return command.endsWith("_group") || command.endsWith("_series")
    ? booking.revisions : { [booking.id]: booking.revision };
}

/** One key per unchanged intent, retained when a response is lost. */
export function createBookingCommands(newId: () => string = () => crypto.randomUUID()) {
  const pending = new Map<string, string>();
  return async (client: Pick<SupabaseClient, "schema">, command: string, payload: Record<string, unknown>, revisions?: Record<string, number>) => {
    if (payload.dry_run === true) return client.schema("api").rpc(command, payload);
    const fingerprint = JSON.stringify([command, payload, revisions]);
    let id = pending.get(fingerprint);
    if (!id) { id = newId(); pending.set(fingerprint, id); }
    const response = await client.schema("api").rpc("execute_booking_command", {
      command_id: id, command_type: command, payload, expected_revisions: revisions ?? null,
    });
    if (!response.error) pending.delete(fingerprint);
    return response;
  };
}

// Keep retries isolated between clients/accounts. A new signed-in actor also
// has a separate server-side namespace for command IDs.
const clients = new WeakMap<SupabaseClient, ReturnType<typeof createBookingCommands>>();
export function bookingCommand(client: SupabaseClient, command: string, payload: Record<string, unknown>, revisions?: Record<string, number>) {
  let execute = clients.get(client);
  if (!execute) { execute = createBookingCommands(); clients.set(client, execute); }
  return execute(client, command, payload, revisions);
}
