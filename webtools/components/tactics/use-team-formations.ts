"use client";

// The project's TeamZone team's formations with what each place asks for, the
// team's attributes to ask for, and the suggestion of who plays where. Only
// the team's leaders get them; for others [allowed] turns false.
import { useCallback, useEffect, useState } from "react";
import type { TeamAttributes } from "../../lib/tactics/attributes.ts";
import type { FormationSlot, Suggestion, TeamFormation } from "../../lib/tactics/lineup.ts";
import { useAccount } from "../account";

export type FormationDraft = { id: string | null; name: string; lines: string; matchFormat: string; slots: FormationSlot[]; revision: number | null };

export function useTeamFormations(teamId: string | null) {
  const { client, session } = useAccount();
  // Asked again once signed in: asked before, it would be turned away.
  const userId = session?.user.id ?? null;
  const [formations, setFormations] = useState<TeamFormation[]>([]);
  // Ready-made formations with requirements on every place; copied to change.
  const [templates, setTemplates] = useState<TeamFormation[]>([]);
  const [attributes, setAttributes] = useState<TeamAttributes | null>(null);
  const [allowed, setAllowed] = useState(false);

  const load = useCallback(async () => {
    if (!client || !teamId || !userId) { setAllowed(false); return; }
    const api = client.schema("api");
    const [listed, team] = await Promise.all([
      api.rpc("list_team_formations", { target_club_id: null, target_team_id: teamId }),
      api.rpc("get_team_player_attributes", { target_club_id: null, target_team_id: teamId }),
    ]);
    if (listed.error || team.error) { setAllowed(false); return; }
    setAllowed(true);
    const lists = listed.data as { formations: TeamFormation[]; templates?: TeamFormation[] };
    setFormations(lists.formations);
    setTemplates(lists.templates ?? []);
    const data = team.data as TeamAttributes;
    setAttributes({ sport: data.sport, catalog: data.catalog, custom: data.custom });
  }, [client, teamId, userId]);

  useEffect(() => { void load(); }, [load]);

  /** Saves a formation; the saved one, or the error's message (formation_name_taken, stale_revision …). */
  const save = async (draft: FormationDraft): Promise<TeamFormation | string> => {
    if (!client || !teamId) return "not_found";
    const { data, error } = await client.schema("api").rpc("save_team_formation", {
      target_club_id: null, target_team_id: teamId, formation_id: draft.id, new_name: draft.name,
      new_lines: draft.lines, new_match_format: draft.matchFormat,
      new_slots: draft.slots.filter(slot => slot.position || slot.foot || slot.requirements.length)
        .map(slot => ({ code: slot.code, position: slot.position, foot: slot.foot ?? null, requirements: slot.requirements })),
      expected_revision: draft.revision,
    });
    if (error) return error.message;
    const saved = data as TeamFormation;
    setFormations(current => [...current.filter(item => item.id !== saved.id), saved].sort((a, b) => a.name.localeCompare(b.name, "sv")));
    return saved;
  };

  const remove = async (formationId: string) => {
    if (!client || !teamId) return false;
    const { data, error } = await client.schema("api").rpc("delete_team_formation", { target_club_id: null, target_team_id: teamId, formation_id: formationId });
    if (error) return false;
    setFormations((data as { formations: TeamFormation[] }).formations);
    setTemplates(current => (data as { templates?: TeamFormation[] }).templates ?? current);
    return true;
  };

  /** Who plays where: a saved formation, or only lines and format; [candidates] the players to choose from (null: the team's). */
  const suggest = async (choice: { formationId: string } | { lines: string; matchFormat: string }, candidates: string[] | null): Promise<Suggestion | null> => {
    if (!client || !teamId) return null;
    const { data, error } = await client.schema("api").rpc("suggest_lineup", {
      target_club_id: null, target_team_id: teamId,
      formation_id: "formationId" in choice ? choice.formationId : null,
      new_lines: "lines" in choice ? choice.lines : null,
      new_match_format: "matchFormat" in choice ? choice.matchFormat : null,
      candidate_ids: candidates, locked: {},
    });
    return error ? null : data as Suggestion;
  };

  return { formations, templates, attributes, allowed, save, remove, suggest, reload: load };
}
