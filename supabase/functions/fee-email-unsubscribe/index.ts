import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { correlationId, sanitizedLog, withCorrelation } from "../_shared/observability.ts";
import { verifiedUnsubscribe } from "../_shared/fee_mail.ts";

// Avregistrering från avgiftsmejl (club-members-and-fees.md, step 5). The
// link in a fee e-mail names the e-mail and is signed. GET shows a page with
// a button (so a mail scanner opening the link changes nothing); POST - the
// button, or a mail app's one-click List-Unsubscribe - stops fee e-mail to
// that address. Nothing about the address is logged or shown.

const page = (title: string, body: string, form = "") =>
  `<!doctype html><html lang="sv"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:3rem auto;padding:0 1rem;color:#14231c}
button{font:inherit;padding:.7rem 1.2rem;border:0;border-radius:.6rem;background:#1f7a4d;color:#fff;cursor:pointer}</style>
</head><body><h1>${title}</h1><p>${body}</p>${form}</body></html>`;

const html = (requestId: string, content: string, status = 200) =>
  withCorrelation(new Response(content, { status, headers: { "content-type": "text/html; charset=utf-8" } }), requestId);

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const url = new URL(request.url);
  const linkSecret = Deno.env.get("CONTACT_REPLY_SECRET") ?? "";
  const emailId = await verifiedUnsubscribe(linkSecret, url.searchParams.get("id"), url.searchParams.get("s"));
  if (!emailId) {
    return html(requestId, page("Länken fungerar inte", "Länken är ogiltig. Kontakta klubben om du inte vill få mejl."), 400);
  }
  if (request.method === "GET") {
    const action = `?id=${emailId}&s=${encodeURIComponent(url.searchParams.get("s") ?? "")}`;
    return html(
      requestId,
      page(
        "Avregistrera dig",
        "Vill du sluta få påminnelser om avgifter via e-post? Du kan fortfarande se dina avgifter i TeamZone.",
        `<form method="post" action="${action}"><button type="submit">Avregistrera mig</button></form>`,
      ),
    );
  }
  if (request.method !== "POST") return html(requestId, page("Fel", "Metoden stöds inte."), 405);

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !secret) return html(requestId, page("Fel", "Försök igen senare."), 503);
  const api = createClient(projectUrl, secret, { auth: { persistSession: false } }).schema("api");
  const { error } = await api.rpc("opt_out_fee_email_by_id", { target_email_id: emailId });
  if (error) {
    sanitizedLog("unsubscribe.failed", "error", requestId, {
      component: "fee_email",
      error_type: error.code ?? "database",
    });
    return html(requestId, page("Fel", "Det gick inte just nu. Försök igen senare."), 500);
  }
  sanitizedLog("unsubscribe.completed", "info", requestId, { component: "fee_email" });
  return html(requestId, page("Klart", "Du får inte längre påminnelser om avgifter via e-post."));
});
