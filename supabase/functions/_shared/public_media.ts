// Pure helpers for public-media-worker, kept free of Deno and ImageMagick so
// they can be unit tested anywhere.

export type SourceFormat = "jpeg" | "png" | "webp";

/** Longest side of a published variant. */
export const MAX_VARIANT_SIDE = 2048;
/** Upper bound for a decoded source, guarding against decompression bombs. */
export const MAX_SOURCE_SIDE = 8192;
export const MAX_SOURCE_PIXELS = 40_000_000;
export const MAX_VARIANT_BYTES = 5_242_880;

/**
 * The format from the file's own signature, never from its name or declared
 * type. Anything else (SVG, PDF, scripts, TIFF, …) is rejected before an
 * image decoder sees it.
 */
export function detectImageFormat(bytes: Uint8Array): SourceFormat | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes.length >= 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value)) return "png";
  if (isWebp(bytes)) return "webp";
  return null;
}

export function isWebp(bytes: Uint8Array): boolean {
  const ascii = (start: number, end: number) => String.fromCharCode(...bytes.slice(start, end));
  return bytes.length >= 12 && ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
}

/** Size that fits within maxSide on both axes, never enlarging. */
export function fitWithin(width: number, height: number, maxSide = MAX_VARIANT_SIDE): { width: number; height: number } {
  if (width <= maxSide && height <= maxSide) return { width, height };
  const scale = maxSide / Math.max(width, height);
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/** Whether a source's dimensions may be decoded at all. */
export function acceptableSourceSize(width: number, height: number): boolean {
  return Number.isInteger(width) && Number.isInteger(height) && width >= 1 && height >= 1
    && width <= MAX_SOURCE_SIDE && height <= MAX_SOURCE_SIDE && width * height <= MAX_SOURCE_PIXELS;
}
