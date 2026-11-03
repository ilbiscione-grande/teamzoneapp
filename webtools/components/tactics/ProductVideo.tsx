"use client";

// The product page's film: muted, looping, and only its first `end`
// seconds (the recording's last second shows the desktop).
import { useRef } from "react";

export function ProductVideo({ src, poster, end }: { src: string; poster: string; end: number }) {
  const video = useRef<HTMLVideoElement>(null);
  return (
    <video
      ref={video}
      className="tb-product-video"
      src={`${src}#t=0,${end}`}
      poster={poster}
      autoPlay
      muted
      loop
      playsInline
      preload="metadata"
      aria-label="Tacticsboard i användning: spelare och boll rör sig över planen"
      onTimeUpdate={() => {
        const element = video.current;
        if (element && element.currentTime >= end) { element.currentTime = 0; void element.play(); }
      }}
    />
  );
}
