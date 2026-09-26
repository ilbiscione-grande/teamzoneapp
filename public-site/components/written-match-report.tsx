export function WrittenMatchReport({ text }: { text?: string | null }) {
  if (!text?.trim()) return null;
  return <details className="match-report"><summary>Läs matchrapport</summary><p style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{text}</p></details>;
}
