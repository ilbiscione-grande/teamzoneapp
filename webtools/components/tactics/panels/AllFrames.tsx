"use client";

// The choice that a colour or an effect goes for every frame the object is
// in, not only the one in hand. It stays on until unticked, and is only
// offered on a board of several frames.
import { activeBoard, useEditor } from "../store.ts";
import { Swatches } from "./Swatches.tsx";
import { useT } from "../../language";

export function AllFrames() {
  const t = useT();
  const on = useEditor(state => state.allFrames);
  const several = useEditor(state => (activeBoard(state)?.frames.length ?? 0) > 1);
  if (!several) return null;
  return (
    <label className="tb-check" title={t("Ändringen gäller objektet i alla frames det finns i.")}>
      <input type="checkbox" checked={on} onChange={event => useEditor.getState().setAllFrames(event.target.checked)} />{t("Gäller alla frames")}
    </label>
  );
}

/** An object's colour, with the choice of all frames under it. */
export function ObjectSwatches(props: { value: string | null; onChange: (color: string) => void; label: string }) {
  return <><Swatches {...props} /><AllFrames /></>;
}
