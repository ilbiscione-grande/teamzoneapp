"use client";

// One group in the host's overview: a small picture of the group's copy as
// it stands, who is in it (each can be moved to another group), following
// the group, and showing it to everyone.
import { groupPreview, type HostGroup } from "../../../lib/tactics/live-groups.ts";
import { ProjectThumb } from "../home/ProjectThumb.tsx";
import { useT } from "../../language";

export type GroupActions = {
  busy: boolean;
  show: (groupId: string | null) => void;
  watch: (groupId: string) => void;
  assign: (profileId: string, groupId: string) => void;
  /** The group's copy as a new board in the project. */
  save: (groupId: string) => void;
};

export function GroupTile({ group, groups, actions }: { group: HostGroup; groups: HostGroup[]; actions: GroupActions }) {
  const t = useT();
  return (
    <li className="tb-live-group-tile" data-shown={group.shown}>
      <button type="button" className="tb-live-group-picture" onClick={() => actions.watch(group.id)} aria-label={t("Följ grupp {number}", { number: group.number })}>
        <ProjectThumb preview={groupPreview(group)} strokes={group.strokes} />
      </button>
      <div className="tb-row">
        <strong>{t("Grupp {number}", { number: group.number })}</strong>
        {group.shown && <span className="tb-live-group-shown">{t("Visas för alla")}</span>}
      </div>
      <GroupMembers group={group} groups={groups} actions={actions} />
      <div className="tb-row">
        <button type="button" className="wt-button small" onClick={() => actions.watch(group.id)}>{t("Följ")}</button>
        <button type="button" className="wt-button small" disabled={actions.busy} onClick={() => actions.show(group.shown ? null : group.id)}>
          {group.shown ? t("Sluta visa") : t("Visa för alla")}
        </button>
      </div>
    </li>
  );
}

/** Who is in the group, each with the group they are in, to move them to another. */
export function GroupMembers({ group, groups, actions }: { group: HostGroup; groups: HostGroup[]; actions: GroupActions }) {
  const t = useT();
  if (group.members.length === 0) return <p className="tb-hint">{t("ingen än")}</p>;
  return (
    <ul className="tb-live-group-members">
      {group.members.map(member => (
        <li key={member.profile_id}>
          <span>{member.name}</span>
          <select aria-label={t("Grupp för {name}", { name: member.name })} value={group.id} disabled={actions.busy}
            onChange={event => actions.assign(member.profile_id, event.target.value)}>
            {groups.map(option => <option key={option.id} value={option.id}>{t("Grupp {number}", { number: option.number })}</option>)}
          </select>
        </li>
      ))}
    </ul>
  );
}
