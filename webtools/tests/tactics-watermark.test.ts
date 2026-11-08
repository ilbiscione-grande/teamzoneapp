import assert from "node:assert/strict";
import { test } from "node:test";
import { WATERMARK, watermarkPlace, watermarkPlate } from "../components/tactics/timeline/watermark.ts";

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

test("the watermark's dark plate covers the text and stays inside the picture", () => {
  for (const [width, height] of [[1920, 1080], [1080, 1920], [320, 240]]) {
    const { size, x, y } = watermarkPlace(width, height);
    const textWidth = size * 18;
    const plate = watermarkPlate(textWidth, size, x, y);
    assert.ok(plate.x < x - textWidth && plate.x + plate.width > x, "wider than the text");
    assert.ok(plate.y < y - size * 0.75 && plate.y + plate.height > y + size * 0.2, "from the letters' tops to below their tails");
    assert.ok(plate.x + plate.width <= width && plate.y + plate.height <= height, `inside ${width}×${height}`);
  }
});
