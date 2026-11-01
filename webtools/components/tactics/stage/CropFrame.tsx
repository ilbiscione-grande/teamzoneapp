"use client";

// The board's crop: the part of the pitch that presenting, shared links, the
// PDF and the video show. Chosen from Dela: the editor dims all but the crop
// and a rectangle dragged over the pitch becomes the new one. Otherwise the
// editor marks it with a faint dashed frame.
import { useState } from "react";
import { Group, Rect, Text } from "react-konva";
import { create } from "zustand";
import { cropBetween, type Rect as Area } from "../../../lib/tactics/geometry.ts";
import type { Point } from "../../../lib/tactics/model.ts";
import { updateBoard } from "../../../lib/tactics/document.ts";
import { useEditor } from "../store.ts";

/** after: run when the crop is done, such as opening Dela again. */
export const useCropping = create<{ on: boolean; after: (() => void) | null; start: (after?: () => void) => void; stop: () => void }>((set, get) => ({
  on: false,
  after: null,
  start: after => set({ on: true, after: after ?? null }),
  stop: () => { const after = get().after; set({ on: false, after: null }); after?.(); },
}));

export function setCrop(boardId: string, crop: Area | null) {
  useEditor.getState().change(document => updateBoard(document, boardId, board => ({ ...board, crop })));
}

/** A rectangle dragged over the pitch while choosing: where it began and where the pointer is. */
export function useCropDraw(pointer: () => Point | null, boardId: string | undefined) {
  const [draft, setDraft] = useState<{ from: Point; to: Point } | null>(null);
  return {
    draft: draft ? cropBetween(draft.from, draft.to) : null,
    start: () => { const at = pointer(); if (at) setDraft({ from: at, to: at }); },
    move: () => { const at = pointer(); if (at && draft) setDraft({ ...draft, to: at }); },
    end: () => {
      const crop = draft && cropBetween(draft.from, draft.to);
      setDraft(null);
      if (crop && boardId) setCrop(boardId, crop);
    },
  };
}

const FAR = 400;

/** active: choosing, dimming all but the crop and catching every press. Drawn in metres; pixel: metres per screen pixel. */
export function CropFrame({ crop, active, pixel, upright }: { crop: Area | null; active: boolean; pixel: number; upright: number }) {
  if (!active) {
    if (!crop) return null;
    return (
      <Group listening={false}>
        <Rect {...crop} stroke="#facc15" strokeWidth={pixel * 1.5} dash={[pixel * 8, pixel * 6]} opacity={0.7} />
        <Text x={crop.x + pixel * 6} y={crop.y + pixel * 6} text="Utsnitt" fontSize={pixel * 12} fontStyle="bold" fill="#facc15" opacity={0.8} rotation={upright} />
      </Group>
    );
  }
  const area = crop ?? { x: 0, y: 0, width: 0, height: 0 };
  const shade = { fill: "rgba(11,17,28,0.55)", listening: false } as const;
  return (
    <Group>
      {crop && <>
        <Rect x={-FAR} y={-FAR} width={FAR * 2 + 200} height={FAR + area.y} {...shade} />
        <Rect x={-FAR} y={area.y + area.height} width={FAR * 2 + 200} height={FAR} {...shade} />
        <Rect x={-FAR} y={area.y} width={FAR + area.x} height={area.height} {...shade} />
        <Rect x={area.x + area.width} y={area.y} width={FAR} height={area.height} {...shade} />
        <Rect {...area} stroke="#facc15" strokeWidth={pixel * 2.5} listening={false} />
      </>}
      {/* Over the objects, so a press starts a rectangle and never moves a player. */}
      <Rect x={-FAR} y={-FAR} width={FAR * 2 + 200} height={FAR * 2 + 100} fill="rgba(0,0,0,0.001)" />
    </Group>
  );
}
