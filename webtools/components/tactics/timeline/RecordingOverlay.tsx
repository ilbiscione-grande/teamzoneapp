"use client";

// While a video is recorded: a see-through cover over the pitch, so nothing on
// it can be touched, and how far the recording has come. The video copies the
// board's own canvases, so neither shows in it.
import { useT } from "../../language";
import { useRecording } from "./video-export.ts";

export function RecordingOverlay() {
  const t = useT();
  const share = useRecording(state => state.share);
  if (share === null) return null;
  const percent = Math.round(share * 100);
  return (
    <div className="tb-recording" onPointerDown={event => event.stopPropagation()} onWheel={event => event.stopPropagation()}>
      <div className="tb-recording-card" role="status">
        <span>{t("Spelar in {percent} %", { percent })}</span>
        <div className="tb-recording-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent}>
          <i style={{ width: `${percent}%` }} />
        </div>
      </div>
    </div>
  );
}
