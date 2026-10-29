// Which way a player faces, in degrees on the pitch: 0 towards the
// right-hand goal, 90 down the screen. A player's turn (rotation) counts
// from their own side's way of attacking: the away side faces the home
// goal unturned.
import type { Side } from "./model.ts";

/** An angle to 0–360. */
export const normalAngle = (angle: number) => ((angle % 360) + 360) % 360;

/** To the nearest `step` degrees. */
export const snapAngle = (angle: number, step = 15) => normalAngle(Math.round(angle / step) * step);

/** The turn that makes a player of this side face this way. */
export const facingToRotation = (facing: number, side: Side) => normalAngle(facing - (side === "away" ? 180 : 0));

/** Eight ways to face, as the panel offers them: the arrow and the angle on the pitch. */
export const facings: { label: string; arrow: string; angle: number }[] = [
  { label: "Upp", arrow: "↑", angle: 270 },
  { label: "Upp åt höger", arrow: "↗", angle: 315 },
  { label: "Åt höger", arrow: "→", angle: 0 },
  { label: "Ner åt höger", arrow: "↘", angle: 45 },
  { label: "Ner", arrow: "↓", angle: 90 },
  { label: "Ner åt vänster", arrow: "↙", angle: 135 },
  { label: "Åt vänster", arrow: "←", angle: 180 },
  { label: "Upp åt vänster", arrow: "↖", angle: 225 },
];
