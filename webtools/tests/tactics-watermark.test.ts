import assert from "node:assert/strict";
import { test } from "node:test";
import { WATERMARK, watermarkPlace } from "../components/tactics/timeline/watermark.ts";

test("the watermark says who made it", () => {
  assert.equal(WATERMARK, "Made with Tacticsboard by Teamzone");
});

test("the watermark sits in the bottom right corner and follows the video's size", () => {
  const full = watermarkPlace(1920, 1080);
  assert.equal(full.size, 24);
  assert.ok(full.x < 1920 && full.x > 1860);
  assert.ok(full.y < 1080 && full.y > 1020);
  assert.equal(watermarkPlace(1080, 1920).size, 24, "the short side counts in a standing video");
  assert.equal(watermarkPlace(320, 240).size, 12, "still readable when small");
});
