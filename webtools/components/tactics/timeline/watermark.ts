// The small line in the corner of a video. Its words are the product's own
// and stay the same whatever language the board is in.
export const WATERMARK = "Made with Tacticsboard by Teamzone";

/** The letters' size and the text's distance from the bottom right corner, in the video's pixels. */
export function watermarkPlace(width: number, height: number) {
  const size = Math.max(12, Math.round(Math.min(width, height) * 0.022));
  const margin = Math.round(size * 0.9);
  return { size, x: width - margin, y: height - margin };
}

export function drawWatermark(context: CanvasRenderingContext2D, width: number, height: number) {
  const { size, x, y } = watermarkPlace(width, height);
  context.save();
  context.font = `600 ${size}px ${getComputedStyle(document.body).fontFamily}`;
  context.textAlign = "right";
  context.textBaseline = "alphabetic";
  context.shadowColor = "rgba(0, 0, 0, .7)";
  context.shadowBlur = size / 3;
  context.fillStyle = "rgba(255, 255, 255, .85)";
  context.fillText(WATERMARK, x, y);
  context.restore();
}
