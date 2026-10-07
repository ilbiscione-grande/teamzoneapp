import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  ImageMagick, initializeImageMagick, MagickFormat, MagickImageInfo, MagickReadSettings,
} from "npm:@imagemagick/magick-wasm@0.0.42";
import { correlationId, sanitizedLog, withCorrelation } from "../_shared/observability.ts";
import {
  acceptableSourceSize, detectImageFormat, fitWithin, isWebp, MAX_VARIANT_BYTES,
} from "../_shared/public_media.ts";

// Processes uploaded public media in TeamZone's own function: the source is
// identified by its signature, decoded by ImageMagick (WebAssembly) within
// strict limits, turned upright, stripped of every profile and comment
// (EXIF, GPS, XMP), scaled to at most 2048 px and stored as a new WebP. Only
// that variant is ever served. Called by the uploader right after an upload
// (gateway-verified JWT); it drains the pending queue, so a missed call is
// picked up by the next one.

// Called from the browser (public site admin, also on club domains) with the
// user's bearer token and no cookies, so any origin may ask; the gateway
// still requires a valid JWT. Without these headers the browser's preflight
// failed and uploads were never processed.
const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
const jsonHeaders = { ...corsHeaders, "content-type": "application/json" };
const magickFormats = { jpeg: MagickFormat.Jpeg, png: MagickFormat.Png, webp: MagickFormat.WebP } as const;

let magickReady: Promise<void> | null = null;
function ensureImageMagick(): Promise<void> {
  magickReady ??= (async () => {
    // 0.0.42 ships one WebAssembly build next to its entry point (later
    // versions ship two and would double the function size).
    const base = import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.42");
    let wasm: Uint8Array | null = null;
    for (const candidate of ["magick.wasm", "x86/magick.wasm"]) {
      try { wasm = await Deno.readFile(new URL(candidate, base)); break; } catch { /* next layout */ }
    }
    if (!wasm) throw new Error("imagemagick_unavailable");
    await initializeImageMagick(wasm);
  })();
  return magickReady;
}

function toVariant(source: Uint8Array): { bytes: Uint8Array; width: number; height: number } {
  const format = detectImageFormat(source);
  if (!format) throw new Error("unsupported_format");
  // Dimensions come from the header, before anything is decoded: this is
  // the guard against decompression bombs.
  const info = MagickImageInfo.create(source);
  if (!acceptableSourceSize(info.width, info.height)) throw new Error("source_too_large");
  return ImageMagick.read(source, new MagickReadSettings({ format: magickFormats[format], frameCount: 1 }), image => {
    image.autoOrient();
    image.strip();
    const target = fitWithin(image.width, image.height);
    if (target.width !== image.width || target.height !== image.height) image.resize(target.width, target.height);
    image.quality = 82;
    return image.write(MagickFormat.WebP, data => ({ bytes: new Uint8Array(data), width: image.width, height: image.height }));
  });
}

Deno.serve(async (request) => {
  const requestId = correlationId(request);
  const respond = (response: Response) => withCorrelation(response, requestId);
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return respond(new Response("Method not allowed", { status: 405, headers: corsHeaders }));
  const url = Deno.env.get("SUPABASE_URL");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const secret = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) {
    sanitizedLog("worker.unavailable", "error", requestId, { component: "public_media", result: "not_configured" });
    return respond(new Response(JSON.stringify({ error: "worker_not_configured" }), { status: 503, headers: jsonHeaders }));
  }
  try { await ensureImageMagick(); } catch {
    magickReady = null;
    sanitizedLog("worker.unavailable", "error", requestId, { component: "public_media", result: "imagemagick_unavailable" });
    return respond(new Response(JSON.stringify({ error: "worker_not_configured" }), { status: 503, headers: jsonHeaders }));
  }
  const client = createClient(url, secret, { auth: { persistSession: false } });
  const { data: items, error: claimError } = await client.schema("api").rpc("claim_public_media_batch", { batch_size: 5 });
  if (claimError) return respond(new Response(JSON.stringify({ error: "claim_failed" }), { status: 500, headers: jsonHeaders }));
  let ready = 0, rejected = 0, failed = 0;
  for (const item of items ?? []) {
    let scanState = "rejected", variantState = "failed", variantKey: string | null = null;
    let width: number | null = null, height: number | null = null;
    try {
      const { data: blob, error: downloadError } = await client.storage.from(item.source_bucket).download(item.source_object_key);
      if (downloadError || !blob) throw new Error("source_unavailable");
      let variant;
      try { variant = toVariant(new Uint8Array(await blob.arrayBuffer())); }
      catch {
        // Not a decodable, acceptable image: never published.
        variantState = "removed";
        rejected++;
        throw new Error("rejected");
      }
      if (!isWebp(variant.bytes) || variant.bytes.length > MAX_VARIANT_BYTES) throw new Error("invalid_variant");
      variantKey = `${item.club_id}/${item.public_token}.webp`;
      width = variant.width;
      height = variant.height;
      const { error: uploadError } = await client.storage.from("public-media-variants")
        .upload(variantKey, variant.bytes, { contentType: "image/webp", upsert: false });
      if (uploadError) throw new Error("variant_upload_failed");
      scanState = "clean";
      variantState = "ready";
      ready++;
    } catch (error) {
      if ((error as Error).message !== "rejected") failed++;
      variantKey = null; width = null; height = null;
    }
    const { error: finishError } = await client.schema("api").rpc("finish_public_media_processing", {
      asset_id: item.asset_id, scan_state: scanState, variant_state: variantState, variant_object_key: variantKey, width, height,
    });
    if (!finishError) await client.storage.from(item.source_bucket).remove([item.source_object_key]);
  }
  sanitizedLog("worker.completed", "info", requestId, { component: "public_media", result: "completed" });
  return respond(new Response(JSON.stringify({ claimed: (items ?? []).length, ready, rejected, failed }), { status: 200, headers: jsonHeaders }));
});
