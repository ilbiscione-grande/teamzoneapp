"use client";

// One board frame drawn off screen at a fixed landscape size, with the
// editor's own pitch and objects, and how they moved there, and handed back
// as a picture. What the screen shows (zoom, a turned phone) does not matter here.
import type Konva from "konva";
import { useEffect, useMemo, useRef } from "react";
import { Group, Layer, Stage } from "react-konva";
import { ballHolders } from "../../../lib/tactics/ball.ts";
import { fitView, viewRect } from "../../../lib/tactics/geometry.ts";
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import type { Trail } from "../../../lib/tactics/marks.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { MoveArrows } from "./MoveArrows.tsx";
import { Pitch } from "../stage/Pitch.tsx";
import { StageContext, type StageShared } from "../stage/stage-context.ts";

export const PICTURE = { width: 1500, height: 1000 };

/** moves: dashed arrows of how things moved into the frame (MoveArrows), drawn under the objects. */
export default function OffscreenBoard({ board, objects, moves = [], onPicture }: {
  board: Board; objects: TacticsObject[]; moves?: Trail[]; onPicture: (dataUrl: string) => void;
}) {
  const stage = useRef<Konva.Stage>(null);
  const nodes = useRef(new Map<string, Konva.Node>());
  const content = useRef<Konva.Group>(null);
  const fit = fitView(viewRect(board.view), PICTURE.width, PICTURE.height);
  const holders = ballHolders(objects);
  const shared = useMemo<StageShared>(() => ({ nodes: nodes.current, content, metresPerPixel: () => 1 / fit.scale, editable: false }), [fit.scale]);

  useEffect(() => {
    // Two screen frames: the shapes are laid out and drawn.
    let second = 0;
    const first = requestAnimationFrame(() => {
      second = requestAnimationFrame(() => {
        const picture = stage.current?.toDataURL({ mimeType: "image/jpeg", quality: 0.9, pixelRatio: 1.4 });
        if (picture) onPicture(picture);
      });
    });
    return () => { cancelAnimationFrame(first); cancelAnimationFrame(second); };
  }, [board, objects, moves, onPicture]);

  return (
    <div className="tb-offscreen" aria-hidden="true">
      <StageContext.Provider value={shared}>
        <Stage ref={stage} width={PICTURE.width} height={PICTURE.height} listening={false}>
          <Layer>
            <Group x={fit.x} y={fit.y} scaleX={fit.scale} scaleY={fit.scale} rotation={fit.rotation}>
              <Pitch view={board.view} overlay={board.overlay} />
            </Group>
          </Layer>
          <Layer>
            <Group ref={content} x={fit.x} y={fit.y} scaleX={fit.scale} scaleY={fit.scale} rotation={fit.rotation}>
              <MoveArrows moves={moves} />
              {objects.filter(item => !item.hidden).map(item => (
                <ObjectNode key={item.id} item={item} board={board} selected={false} upright={-fit.rotation} holding={holders.has(item.id)} />
              ))}
            </Group>
          </Layer>
        </Stage>
      </StageContext.Provider>
    </div>
  );
}
