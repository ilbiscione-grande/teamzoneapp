"use client";

// A share link's QR code: drawn as SVG, shown big on a screen for a room to
// scan, or saved as a picture for a printout or a slide.
import { useMemo } from "react";
import { qrModules, qrPath } from "../../lib/tactics/qr.ts";

const QUIET = 4;

export function QrCode({ text, label, size = 180 }: { text: string; label: string; size?: number }) {
  const { path, extent } = useMemo(() => {
    const modules = qrModules(text);
    return { path: qrPath(modules, QUIET), extent: modules.length + QUIET * 2 };
  }, [text]);
  return (
    <svg className="tb-qr" width={size} height={size} viewBox={`0 0 ${extent} ${extent}`} role="img" aria-label={label} shapeRendering="crispEdges">
      <rect width={extent} height={extent} fill="#ffffff" />
      <path d={path} fill="#0b111c" />
    </svg>
  );
}

/** The QR code as a PNG to save, with the link's name under it. */
export function downloadQrPng(text: string, title: string, fileName: string) {
  const modules = qrModules(text);
  const cell = Math.max(8, Math.floor(1000 / (modules.length + QUIET * 2)));
  const side = (modules.length + QUIET * 2) * cell;
  const canvas = document.createElement("canvas");
  canvas.width = side;
  canvas.height = side + 90;
  const context = canvas.getContext("2d");
  if (!context) return;
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#0b111c";
  modules.forEach((row, y) => row.forEach((dark, x) => {
    if (dark) context.fillRect((x + QUIET) * cell, (y + QUIET) * cell, cell, cell);
  }));
  context.font = "bold 40px Inter, system-ui, sans-serif";
  context.textAlign = "center";
  context.fillText(title.slice(0, 40), side / 2, side + 50);
  canvas.toBlob(blob => {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }, "image/png");
}

/** The QR code filling the screen, for a room to scan from a TV or projector. */
export function BigQr({ text, title, onClose }: { text: string; title: string; onClose: () => void }) {
  return (
    <div className="tb-bigqr" role="dialog" aria-modal="true" aria-label="QR-kod" onClick={onClose}>
      <strong>{title}</strong>
      <QrCode text={text} label={`QR-kod för ${title}`} size={Math.min(720, typeof window === "undefined" ? 480 : Math.min(window.innerWidth, window.innerHeight) - 160)} />
      <span>Skanna med mobilens kamera för att se tavlan. Tryck var som helst för att stänga.</span>
    </div>
  );
}
