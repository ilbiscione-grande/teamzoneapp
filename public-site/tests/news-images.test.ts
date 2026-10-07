import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { acceptableSourceSize, detectImageFormat, fitWithin, isWebp } from "../../supabase/functions/_shared/public_media.ts";
import { scaledSize } from "../lib/admin-image.ts";

const root = new URL("../", import.meta.url);
const bytes = (...values: number[]) => new Uint8Array(values);
const ascii = (text: string) => new TextEncoder().encode(text);

test("the worker trusts only the file signature", () => {
  assert.equal(detectImageFormat(bytes(0xff, 0xd8, 0xff, 0xe0)), "jpeg");
  assert.equal(detectImageFormat(bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)), "png");
  const webp = new Uint8Array([...ascii("RIFF"), 0, 0, 0, 0, ...ascii("WEBP")]);
  assert.equal(detectImageFormat(webp), "webp");
  assert.equal(isWebp(webp), true);
  for (const other of [ascii("<svg xmlns='http://www.w3.org/2000/svg'/>"), ascii("%PDF-1.7"), ascii("GIF89a"), bytes(0x49, 0x49, 0x2a, 0x00), bytes()]) {
    assert.equal(detectImageFormat(other), null);
  }
});

test("variants fit within 2048 px and sources are bounded before decoding", () => {
  assert.deepEqual(fitWithin(4000, 3000), { width: 2048, height: 1536 });
  assert.deepEqual(fitWithin(1200, 800), { width: 1200, height: 800 }, "never enlarged");
  assert.deepEqual(fitWithin(1000, 9000), { width: 228, height: 2048 });
  assert.equal(acceptableSourceSize(6000, 4000), true);
  assert.equal(acceptableSourceSize(9000, 100), false);
  assert.equal(acceptableSourceSize(8000, 8000), false, "decompression bomb by area");
  assert.equal(acceptableSourceSize(0, 10), false);
});

test("the browser scales before upload without enlarging", () => {
  assert.deepEqual(scaledSize(4032, 3024), { width: 2560, height: 1920 });
  assert.deepEqual(scaledSize(800, 600), { width: 800, height: 600 });
});

test("news images reach the public pages only through processed, same-origin paths", () => {
  const editor = readFileSync(new URL("components/admin/admin-news.tsx", root), "utf8");
  const image = readFileSync(new URL("lib/admin-image.ts", root), "utf8");
  const article = readFileSync(new URL("app/[clubSlug]/nyheter/[articleSlug]/page.tsx", root), "utf8");
  // CSP: no blob: or signed storage URLs as <img>; the local preview is a canvas.
  assert.doesNotMatch(editor + image, /createObjectURL|createSignedUrl/);
  assert.match(editor, /<canvas/);
  assert.match(image, /imageOrientation: "from-image"/);
  assert.match(image, /"public-media-worker"/);
  assert.match(editor, /"set_editorial_article_hero"/);
  assert.match(article, /media_path\.startsWith\("\/media\/public\/"\)/);
  assert.match(article, /alt=\{article\.media_alt \?\? ""\}/);
});
