"use client";

// The project's logo on the pitch (Branding): faint in the centre circle, or
// small by the far corner flag, drawn with the pitch beneath the objects.
import { useEffect, useState } from "react";
import { Image } from "react-konva";
import { PITCH_LENGTH as L, PITCH_WIDTH as W, type Branding } from "../../../lib/tactics/model.ts";

function useLoaded(src: string | null): HTMLImageElement | null {
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  useEffect(() => {
    if (!src) { setImage(null); return; }
    const element = new window.Image();
    element.onload = () => setImage(element);
    element.src = src;
    return () => { element.onload = null; };
  }, [src]);
  return image;
}

export function PitchLogo({ branding, upright }: { branding: Branding | undefined; upright: number }) {
  const image = useLoaded(branding?.logo ?? null);
  if (!image || !branding || branding.place === "none") return null;
  const centre = branding.place === "centre";
  // As wide as the centre circle, or 6 m by the corner; the picture keeps its shape.
  const size = centre ? 13 : 6;
  const ratio = image.width / Math.max(1, image.height);
  const [width, height] = ratio >= 1 ? [size, size / ratio] : [size * ratio, size];
  const at = centre ? { x: L / 2, y: W / 2 } : { x: L - 5, y: 5 };
  return (
    <Image image={image} x={at.x} y={at.y} width={width} height={height} offsetX={width / 2} offsetY={height / 2}
      rotation={upright} opacity={centre ? 0.22 : 0.85} listening={false} perfectDrawEnabled={false} />
  );
}
