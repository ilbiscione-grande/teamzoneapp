// The small line in the corner of a video, on a dark plate so it can be read
// whatever the video shows under it. Its words are the product's own and
// stay the same whatever language the board is in.
export const WATERMARK = "Made with Tacticsboard by Teamzone";

/** The letters' size and the text's distance from the bottom right corner, in the video's pixels. */
export function watermarkPlace(width: number, height: number) {
  const size = Math.max(12, Math.round(Math.min(width, height) * 0.022));
  const margin = Math.round(size * 0.9);
  return { size, x: width - margin, y: height - margin };
}

/** The plate behind the text: the text's box with room round it, kept inside the picture. */
export function watermarkPlate(textWidth: number, size: number, x: number, y: number) {
  const pad = Math.round(size * 0.6);
  return { x: x - textWidth - pad, y: y - size, width: textWidth + pad * 2, height: Math.round(size * 1.4), radius: Math.round(size * 0.4) };
}

export function drawWatermark(context: CanvasRenderingContext2D, width: number, height: number) {
  const { size, x, y } = watermarkPlace(width, height);
  context.save();
  context.font = `600 ${size}px ${getComputedStyle(document.body).fontFamily}`;
  context.textAlign = "right";
  context.textBaseline = "alphabetic";
  const plate = watermarkPlate(context.measureText(WATERMARK).width, size, x, y);
  context.fillStyle = "rgba(11, 17, 28, .62)";
  context.beginPath();
  context.roundRect(plate.x, plate.y, plate.width, plate.height, plate.radius);
  context.fill();
  context.fillStyle = "rgba(255, 255, 255, .92)";
  context.fillText(WATERMARK, x, y);
  context.restore();
}
