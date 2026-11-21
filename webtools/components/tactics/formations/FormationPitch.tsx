"use client";

// A formation on the own half, attacking upwards: each place as a disc with
// its short name, and a dot for each thing it asks for. A place is chosen by
// clicking it.
import { formationPositions } from "../../../lib/tactics/formations.ts";
import { slotLabel, type FormationSlot } from "../../../lib/tactics/lineup.ts";
import { PITCH_LENGTH, PITCH_WIDTH } from "../../../lib/tactics/model.ts";

const DEPTH = PITCH_LENGTH / 2;

export function FormationPitch({ lines, slots, selected, english, onSelect }: {
  lines: number[];
  slots: FormationSlot[];
  selected: string | null;
  english: boolean;
  onSelect: (code: string) => void;
}) {
  const spots = formationPositions(lines, "home");
  const line = { fill: "none", stroke: "rgba(255,255,255,.75)", strokeWidth: 0.35 };
  return (
    <svg className="tb-formation-pitch" viewBox={`-2 -2 ${PITCH_WIDTH + 4} ${DEPTH + 4}`} role="group">
      <rect x={-2} y={-2} width={PITCH_WIDTH + 4} height={DEPTH + 4} rx={2} fill="#2f7d46" />
      <rect x={0} y={0} width={PITCH_WIDTH} height={DEPTH} {...line} />
      <path d={`M ${PITCH_WIDTH / 2 - 9.15} 0 A 9.15 9.15 0 0 0 ${PITCH_WIDTH / 2 + 9.15} 0`} {...line} />
      <rect x={(PITCH_WIDTH - 40.32) / 2} y={DEPTH - 16.5} width={40.32} height={16.5} {...line} />
      <rect x={(PITCH_WIDTH - 18.32) / 2} y={DEPTH - 5.5} width={18.32} height={5.5} {...line} />
      {slots.map((slot, index) => {
        const spot = spots[index];
        if (!spot) return null;
        const cx = spot.y, cy = DEPTH - spot.x;
        const chosen = slot.code === selected;
        const label = slotLabel(lines, slot.code, english);
        return (
          <g key={slot.code} className="tb-formation-spot" data-chosen={chosen} role="button" tabIndex={0}
            aria-label={label} aria-pressed={chosen}
            onClick={() => onSelect(slot.code)}
            onKeyDown={event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onSelect(slot.code); } }}>
            <circle cx={cx} cy={cy} r={chosen ? 3.9 : 3.4} fill={chosen ? "#facc15" : "#0f172a"} stroke="white" strokeWidth={0.5} />
            <text x={cx} y={cy + 0.9} textAnchor="middle" fontSize={label.length > 2 ? 2.1 : 2.5} fontWeight={700} fill={chosen ? "#0f172a" : "white"}>{label}</text>
            {slot.requirements.map((requirement, dot) => (
              <circle key={requirement.attribute} cx={cx - (slot.requirements.length - 1) * 0.9 + dot * 1.8} cy={cy + 5.2}
                r={requirement.weight === 2 ? 0.75 : 0.5} fill={requirement.weight === 2 ? "#facc15" : "white"} />
            ))}
          </g>
        );
      })}
    </svg>
  );
}
