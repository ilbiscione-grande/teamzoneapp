// A QR code for a share link: its dark modules as an SVG path, and as a
// picture to save. The code is made by qrcode-generator; drawing is ours.
import qrcode from "qrcode-generator";

/** The modules of a QR code for the text: true is dark. Medium error correction survives a smudged print. */
export function qrModules(text: string): boolean[][] {
  const code = qrcode(0, "M");
  code.addData(text);
  code.make();
  const size = code.getModuleCount();
  return Array.from({ length: size }, (_, row) => Array.from({ length: size }, (_, col) => code.isDark(row, col)));
}

/** One SVG path of unit squares for the dark modules, offset by a quiet zone. */
export function qrPath(modules: boolean[][], quiet = 4): string {
  const parts: string[] = [];
  modules.forEach((row, y) => {
    // Runs of dark modules in a row become one rectangle.
    let x = 0;
    while (x < row.length) {
      if (!row[x]) { x++; continue; }
      let end = x;
      while (end < row.length && row[end]) end++;
      parts.push(`M${x + quiet} ${y + quiet}h${end - x}v1h${x - end}z`);
      x = end;
    }
  });
  return parts.join("");
}
