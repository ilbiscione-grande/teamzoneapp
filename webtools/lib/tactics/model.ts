// Tacticsboard's document: a project of boards, each a list of frames, each
// frame the objects on the pitch at that moment. Everything is measured in
// metres on a 105 × 68 pitch, the home goal to the left. The whole document
// is saved at once (core.tactics_projects.document) and carries its schema
// version; ids are stable so a board can be linked from TeamZone.

export const SCHEMA_VERSION = 1;
export const PITCH_LENGTH = 105;
export const PITCH_WIDTH = 68;

export type Point = { x: number; y: number };
export type Side = "home" | "away";

type Base = {
  id: string;
  x: number;
  y: number;
  rotation: number;
  locked: boolean;
  hidden: boolean;
  /** The object's own name in the object list. */
  label?: string;
  /** Animation: the move into this frame bends through this pitch point. */
  pathControl?: Point | null;
  /** Animation: how the object shows as this frame is reached (one; boards from before several could be chosen). */
  effect?: Effect | null;
  /** Animation: the effects played together as this frame is reached; read through effectsOf. */
  effects?: Effect[];
  /** Animation: how close the zoom effect goes on this object; "medium" when missing. */
  zoomLevel?: ZoomLevel;
};

export type ZoomLevel = "close" | "medium" | "wide";

/**
 * Effects play while the board moves into the frame that has them. An
 * object new in a frame fades in and one gone from the next fades out by
 * themselves; "pop" and "draw" are other ways in, "pulse" and "highlight"
 * point at an object already there, "trail" leaves a dashed track of the
 * move behind it, "arrow" shows the way ahead of it, "ring" rings it in its
 * colour and "zoom" brings the view in on it. Several play together.
 */
export type Effect = "fade" | "pop" | "draw" | "pulse" | "highlight" | "trail" | "arrow" | "zoom" | "ring";

export type PlayerObject = Base & {
  type: "player";
  side: Side;
  number: number | null;
  name: string | null;
  /** A position such as MV or YB; missing on players drawn before positions. */
  position?: string | null;
  /**
   * The TeamZone player, when placed from the team's squad. The name, number
   * and position are copied from the squad then, and edits here win over it.
   */
  personId: string | null;
  /** A colour of its own, such as a goalkeeper's; else the team's. */
  color: string | null;
};

export type BallObject = Base & {
  type: "ball";
  /** The player the ball sticks to, and where on the player's edge. */
  attachedTo: string | null;
  offset: Point | null;
};

export type EquipmentKind = "cone" | "pole" | "mannequin" | "goal";

export type EquipmentObject = Base & {
  type: EquipmentKind;
  color: string;
  scale: number;
};

export type ArrowHead = "none" | "end" | "both";

export type LineObject = Base & {
  type: "line";
  /** Start and end, relative to x and y. */
  points: [number, number, number, number];
  /** A curve's control point, relative to x and y; null when straight. */
  control: Point | null;
  arrow: ArrowHead;
  dashed: boolean;
  color: string;
  width: number;
};

export type FreehandObject = Base & {
  type: "freehand";
  points: number[];
  arrow: ArrowHead;
  dashed: boolean;
  color: string;
  width: number;
};

export type ShapeObject = Base & {
  type: "rect" | "ellipse";
  width: number;
  height: number;
  color: string;
  /** 0–1: how much the area is filled. */
  fill: number;
  dashed: boolean;
};

export type TextObject = Base & {
  type: "text";
  text: string;
  /** The letters' height, whatever the box. */
  size: number;
  /** The box, once resized: the text wraps inside it. Missing, it fits the text. */
  width?: number | null;
  height?: number | null;
  color: string;
  background: boolean;
};

export type TacticsObject =
  | PlayerObject
  | BallObject
  | EquipmentObject
  | LineObject
  | FreehandObject
  | ShapeObject
  | TextObject;

export type ObjectType = TacticsObject["type"];

export type Frame = {
  id: string;
  objects: TacticsObject[];
  /** How long the move into this frame takes when played. */
  durationMs: number;
  /** How the move into this frame speeds up and slows down; smooth when missing. */
  easing?: Easing;
  note: string;
};

/** smooth: starts and stops softly; linear: the same speed all the way; in/out: soft only at the start or the end. */
export type Easing = "smooth" | "linear" | "in" | "out";

export type PitchView = "full" | "attack" | "defend" | "empty";
export type PitchOverlay = "none" | "corridors" | "thirds" | "zones";

export type TeamStyle = { name: string; color: string; numberColor: string };

/** The part of a training session an exercise is in. */
export type ExercisePart = "warmup" | "main" | "finish";

/** The Swedish FA's phases of the game, with the ball and without it. */
export type GamePhase = "scoring" | "preventing_scoring" | "build_up" | "preventing_build_up" | "counter" | "regaining" | "attacking_play" | "defending";

export type AgeClass = "7-9" | "10-12" | "13-15" | "16+";
export type GameForm = "3v3" | "5v5" | "7v7" | "9v9" | "11v11";

/** A board as an exercise: what the library keeps beside it. */
export type ExerciseDetails = {
  part: ExercisePart;
  minutes: number;
  players: number | null;
  area: string;
  coachingPoints: string;
  phase: GamePhase | null;
  ageClasses: AgeClass[];
  gameForms: GameForm[];
};

export type Board = {
  id: string;
  name: string;
  view: PitchView;
  overlay: PitchOverlay;
  teams: Record<Side, TeamStyle>;
  showNames: boolean;
  /** What the board shows, such as an exercise's set-up and coaching points: shown beside it when presenting. */
  description?: string;
  /** Positions above the players; missing on boards made before it. */
  showPositions?: boolean;
  /** In a training project: the board as an exercise (decision package 13); its organisation is the description. */
  exercise?: ExerciseDetails;
  frames: Frame[];
};

/** A player of the TeamZone team, as the project last read the squad. */
export type SquadPlayer = { personId: string; name: string; number: number | null; position: string | null };

export type ProjectDocument = {
  schemaVersion: number;
  boards: Board[];
  squad: SquadPlayer[];
};

export type ProjectKind = "match" | "training" | "education";

export type ProjectSummary = {
  id: string;
  name: string;
  kind: ProjectKind;
  teamzone_team_id: string | null;
  team_name: string | null;
  board_count: number;
  revision: number;
  created_at: string;
  updated_at: string;
};

export type Project = ProjectSummary & { document: ProjectDocument };
