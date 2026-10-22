"use client";

// A colour picker of a few match colours and any other.
export const swatches = ["#ffffff", "#111827", "#facc15", "#f97316", "#dc2626", "#ec4899", "#8b5cf6", "#1d4ed8", "#06b6d4", "#16a34a"];

export function Swatches({ value, onChange, label }: { value: string | null; onChange: (color: string) => void; label: string }) {
  return (
    <div className="tb-field">
      <span>{label}</span>
      <div className="tb-swatches" role="radiogroup" aria-label={label}>
        {swatches.map(color => (
          <button key={color} type="button" role="radio" aria-checked={value === color} aria-label={color}
            style={{ background: color }} onClick={() => onChange(color)} />
        ))}
        <input type="color" value={value ?? "#ffffff"} onChange={event => onChange(event.target.value)} aria-label={`${label}, egen färg`} />
      </div>
    </div>
  );
}
