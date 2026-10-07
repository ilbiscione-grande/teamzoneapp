// Browser side of news images. The browser turns the photo upright, scales it
// down and re-encodes it as JPEG before upload, which already drops metadata
// such as GPS position. public-media-worker then decodes, strips and converts
// it again on the server, so the published image never depends on the browser.

import type { SupabaseClient } from "@supabase/supabase-js";
import type { AdminRpc } from "./admin";

export const MAX_UPLOAD_SIDE = 2560;
export const MAX_ORIGINAL_BYTES = 30 * 1024 * 1024;
export const MAX_UPLOAD_BYTES = 10_485_760;

export type PreparedImage = { blob: Blob; width: number; height: number; bitmap: ImageBitmap };

/** Pixel size that fits within maxSide, never enlarging. */
export function scaledSize(width: number, height: number, maxSide = MAX_UPLOAD_SIDE): { width: number; height: number } {
  if (width <= maxSide && height <= maxSide) return { width, height };
  const scale = maxSide / Math.max(width, height);
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

export async function prepareImage(file: File): Promise<PreparedImage> {
  if (!file.type.startsWith("image/")) throw new Error("not_an_image");
  if (file.size > MAX_ORIGINAL_BYTES) throw new Error("too_large");
  let source: ImageBitmap;
  try { source = await createImageBitmap(file, { imageOrientation: "from-image" }); }
  catch { throw new Error("unsupported_format"); }
  const size = scaledSize(source.width, source.height);
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("unsupported_format");
  context.drawImage(source, 0, 0, size.width, size.height);
  source.close();
  const blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, "image/jpeg", 0.9));
  if (!blob) throw new Error("unsupported_format");
  if (blob.size > MAX_UPLOAD_BYTES) throw new Error("too_large");
  return { blob, width: size.width, height: size.height, bitmap: await createImageBitmap(canvas) };
}

export function imageErrorMessage(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  if (code === "too_large") return "Bilden är för stor. Välj en bild under 30 MB.";
  if (code === "not_an_image" || code === "unsupported_format") return "Bildformatet stöds inte. Välj en JPEG-, PNG- eller WebP-bild.";
  return "Bilden kunde inte laddas upp. Försök igen.";
}

/** Uploads a prepared image privately and starts processing; returns the asset id. */
export async function uploadNewsImage(client: SupabaseClient, rpc: AdminRpc, clubId: string, image: Blob): Promise<string> {
  const staged = await rpc("stage_public_media", { club_id: clubId, purpose: "editorial_hero", content_type: "image/jpeg", size_bytes: image.size });
  const data = staged.data as { asset_id?: string; bucket_id?: string; object_key?: string } | null;
  if (staged.error || data?.bucket_id !== "public-media-source" || !data.object_key || !data.asset_id) throw new Error("stage_failed");
  const { error } = await client.storage.from("public-media-source").upload(data.object_key, image, { contentType: "image/jpeg", upsert: false });
  if (error) throw new Error("upload_failed");
  return data.asset_id;
}

/** Asks the worker to process pending images now; failures are retried by later calls. */
export async function startImageProcessing(client: SupabaseClient): Promise<void> {
  try { await client.functions.invoke("public-media-worker", { method: "POST", body: {} }); } catch { /* processed later */ }
}

export const heroStateLabel: Record<string, string> = {
  pending: "Bilden bearbetas",
  ready: "Bild",
  failed: "Bilden kunde inte bearbetas",
  rejected: "Bilden godkändes inte",
};
