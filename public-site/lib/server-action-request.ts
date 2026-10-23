// Next 16.3.8's mightBeServerReferenceId checks for a 42-character ID.
// Keep this boundary check in sync when upgrading Next. It only rejects
// malformed fetch-action headers; Next still resolves and authorizes actions.
export function invalidServerActionResponse(request: Request): Response | null {
  const actionId = request.headers.get("next-action");
  if (request.method !== "POST" || actionId === null || actionId.length === 42) {
    return null;
  }
  // Do not reflect the supplied identifier or parse the untrusted body.
  return new Response("Bad Request", {
    status: 400,
    headers: { "Cache-Control": "no-store" },
  });
}
