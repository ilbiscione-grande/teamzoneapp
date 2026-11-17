"use client";

// The host follows one group: its copy large, as the group moves objects
// and draws, its chat, who is in it, showing it to everyone, and saving it
// as a new board in the project. The host only watches here; the host's own
// board is the project, which a group's copy must not touch.
import { useEffect, useState } from "react";
import { groupPreview, type HostGroup } from "../../../lib/tactics/live-groups.ts";
import { ProjectThumb } from "../home/ProjectThumb.tsx";
import { GroupChat } from "./GroupChat.tsx";
import { GroupMembers, type GroupActions } from "./GroupTile.tsx";
import { useT } from "../../language";

export function GroupWatch({ group, groups, actions, onClose }: { group: HostGroup; groups: HostGroup[]; actions: GroupActions; onClose: () => void }) {
  const t = useT();
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="tb-modal" role="dialog" aria-modal="true" aria-label={t("Grupp {number}", { number: group.number })}
      onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="tb-modal-card tb-live-group-watch">
        <div className="tb-modal-head">
          <h2>{t("Grupp {number}", { number: group.number })}{group.shown && <span className="tb-live-group-shown">{t("Visas för alla")}</span>}</h2>
          <button type="button" className="tb-modal-close" aria-label={t("Stäng")} onClick={onClose}>×</button>
        </div>
        <ProjectThumb preview={groupPreview(group)} detail labels strokes={group.strokes} />
        <p className="tb-hint">{t("Gruppens kopia, som den ser ut just nu. Du följer bara gruppen här; ditt projekt ändras inte.")}</p>
        <GroupMembers group={group} groups={groups} actions={actions} />
        <GroupChat messages={group.messages} number={group.number} />
        <div className="tb-actions">
          <button type="button" className="wt-button small" onClick={() => { actions.save(group.id); setSaved(true); }}>{t("Spara som ny tavla")}</button>
          <button type="button" className="wt-button small" disabled={actions.busy} onClick={() => actions.show(group.shown ? null : group.id)}>
            {group.shown ? t("Sluta visa") : t("Visa för alla")}
          </button>
        </div>
        {saved && <p className="tb-hint" role="status">{t("Sparad som en ny tavla sist i projektet. Grupperna märker inget.")}</p>}
      </div>
    </div>
  );
}
