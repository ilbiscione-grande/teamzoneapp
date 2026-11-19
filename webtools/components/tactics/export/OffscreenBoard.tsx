"use client";

// One board frame drawn off screen at a fixed size, with the
// editor's own pitch and objects, and how they moved there, and handed back
// as a picture: landscape, or with a crop at the crop's shape as the PDF
// lays it out (pictureRatio). What the screen shows (zoom, a turned phone) does not matter
// here; whether it is in 3D does: tilted, the ground and the upright
// figures are put together into one picture (tilt-picture.ts).
import type Konva from "konva";
import { useEffect, useMemo, useRef } from "react";
import { Group, Layer, Stage } from "react-konva";
import { ballHolders } from "../../../lib/tactics/ball.ts";
import { fitView, marginFor, shownRect } from "../../../lib/tactics/geometry.ts";
import { pictureSize } from "../../../lib/tactics/board-picture.ts";
import { drawnGround, groundReach, projector } from "../../../lib/tactics/projection.ts";
import type { Board, TacticsObject } from "../../../lib/tactics/model.ts";
import type { Trail } from "../../../lib/tactics/marks.ts";
import { layered } from "../../../lib/tactics/document.ts";
import { ObjectNode } from "../objects/ObjectNode.tsx";
import { MoveArrows } from "./MoveArrows.tsx";
import { useEditor } from "../store.ts";
import { lookOf } from "../../../lib/tactics/pitch-style.ts";
import { Figures3D, STANDING } from "../stage/Figures3D.tsx";
import { Pitch, tiltedReach } from "../stage/Pitch.tsx";
import { ZoneDim, ZoneDimLayer } from "../stage/ZoneDim.tsx";
import { drawTilted, layerCanvases } from "../stage/tilt-picture.ts";
import { StageContext, type StageShared } from "../stage/stage-context.ts";

/** The picture's longer side, in pixels. */
const LONG_SIDE = 1500;

const SHARPNESS = 1.4;
const WHOLE = { x: 0, y: 0, scale: 1 };

/**
 * moves: dashed arrows of how things moved into the frame (MoveArrows), drawn under the objects. tilted: in 3D.
 * longSide, sharpness, type and quality: the picture's size and format, by default for the PDF.
 */
export default function OffscreenBoard({ board, objects, moves = [], tilted = false, onPicture, longSide = LONG_SIDE, sharpness = SHARPNESS, type = "image/jpeg", quality = 0.9 }: {
  board: Board; objects: TacticsObject[]; moves?: Trail[]; tilted?: boolean; onPicture: (dataUrl: string) => void;
  longSide?: number; sharpness?: number; type?: string; quality?: number;
}) {
  const stage = useRef<Konva.Stage>(null);
  const figures = useRef<Konva.Stage | null>(null);
  const nodes = useRef(new Map<string, Konva.Node>());
  const content = useRef<Konva.Group>(null);
  const branding = useEditor(state => state.document?.branding);
  const size = pictureSize(board, longSide);
  // The board's crop where it has one: the part of the pitch the PDF is to show.
  const fit = fitView(shownRect(board, marginFor(board.surroundings), true), size.width, size.height, false, !!board.crop);
  const holders = ballHolders(objects);
  // In layers, as the board draws them.
  const shown = layered(objects.filter(item => !item.hidden));
  const reach = tilted ? groundReach(size.width, size.height, drawnGround(fit, WHOLE, tiltedReach(board.surroundings))) : null;
  const offset = { x: reach?.left ?? 0, y: reach?.top ?? 0 };
  const shared = useMemo<StageShared>(() => ({ nodes: nodes.current, content, metresPerPixel: () => 1 / fit.scale, editable: false }), [fit.scale]);

  useEffect(() => {
    // Two screen frames: the shapes are laid out and drawn.
    let second = 0;
    const first = requestAnimationFrame(() => {
      second = requestAnimationFrame(() => {
        const picture = tilted ? tiltedPicture() : stage.current?.toDataURL({ mimeType: type, quality, pixelRatio: sharpness });
        if (picture) onPicture(picture);
      });
    });
    return () => { cancelAnimationFrame(first); cancelAnimationFrame(second); };
  }, [board, objects, moves, tilted, onPicture]); // eslint-disable-line react-hooks/exhaustive-deps

  function tiltedPicture() {
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(size.width * sharpness);
    canvas.height = Math.round(size.height * sharpness);
    const context = canvas.getContext("2d");
    if (!context || !stage.current) return null;
    drawTilted(context, { ground: layerCanvases(stage.current), offset, figures: layerCanvases(figures.current), width: size.width, height: size.height });
    return canvas.toDataURL(type, quality);
  }

  return (
    <div className="tb-offscreen" aria-hidden="true">
      <StageContext.Provider value={shared}>
        <Stage ref={stage} width={size.width + (reach ? reach.left + reach.right : 0)} height={size.height + (reach ? reach.top + reach.bottom : 0)} listening={false}>
          <Layer {...offset}>
            <Group x={fit.x} y={fit.y} scaleX={fit.scale} scaleY={fit.scale} rotation={fit.rotation}>
              <Pitch view={board.view} overlay={board.overlay} style={board.pitch} surroundings={board.surroundings} branding={branding} upright={-fit.rotation} tilted={tilted} />
            </Group>
          </Layer>
          <Layer {...offset}>
            <Group ref={content} x={fit.x} y={fit.y} scaleX={fit.scale} scaleY={fit.scale} rotation={fit.rotation}>
              {tilted && <ZoneDim objects={shown} />}
              <MoveArrows moves={moves} ink={lookOf(board.pitch).ink} light={lookOf(board.pitch).light} />
              {shown.filter(item => !tilted || !STANDING.has(item.type)).map(item => (
                <ObjectNode key={item.id} item={item} board={board} selected={false} upright={-fit.rotation} holding={holders.has(item.id)} objects={shown} />
              ))}
            </Group>
          </Layer>
          {!tilted && <ZoneDimLayer objects={shown} zoomed={{ x: 0, y: 0, scaleX: 1, scaleY: 1 }} offset={offset}
            fitted={{ x: fit.x, y: fit.y, scaleX: fit.scale, scaleY: fit.scale, rotation: fit.rotation }} />}
        </Stage>
        {tilted && (
          <Figures3D objects={shown} board={board} project={projector(fit, WHOLE, size.width, size.height)} spotlight={null}
            width={size.width} height={size.height} stageRef={node => { figures.current = node; }} />
        )}
      </StageContext.Provider>
    </div>
  );
}
