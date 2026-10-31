"use client";

// The start page's projects: your own, found with the filters as in
// TeamZone's library, and the team's other leaders made, filtered by words
// and kind here. A pin is shown at once and taken back if it fails.
import { useCallback, useEffect, useState } from "react";
import type { HomeFilters } from "../../../lib/tactics/home.ts";
import { useAccount } from "../../account";
import type { HomeProject, Published } from "./ProjectCard.tsx";

export { noHomeFilters, teamMatches, type HomeFilters } from "../../../lib/tactics/home.ts";

export function useHomeProjects(filters: HomeFilters) {
  const { client } = useAccount();
  const [mine, setMine] = useState<HomeProject[] | null>(null);
  const [team, setTeam] = useState<HomeProject[]>([]);
  const [error, setError] = useState("");

  const load = useCallback(async (current: HomeFilters) => {
    if (!client) return;
    const { data, error: loadError } = await client.schema("api").rpc("search_my_tactics_projects", {
      search_text: current.text.trim().slice(0, 100), project_kind: current.kind || null, exercise_part: current.part || null,
      game_phase: current.phase || null, age_class: current.age || null, game_form: current.form || null,
    });
    if (loadError) { setError("Dina projekt kunde inte hämtas."); setMine([]); return; }
    setError("");
    setMine(data as HomeProject[]);
  }, [client]);
  useEffect(() => {
    const timer = window.setTimeout(() => void load(filters), filters.text ? 300 : 0);
    return () => window.clearTimeout(timer);
  }, [filters, load]);
  const loadTeam = useCallback(() => {
    // Before the leader-access migration the call fails; none are shown then.
    client?.schema("api").rpc("list_team_tactics_projects").then(({ data }) => setTeam((data as HomeProject[] | null) ?? []));
  }, [client]);
  useEffect(loadTeam, [loadTeam]);

  const reload = () => { void load(filters); loadTeam(); };

  const pin = async (project: HomeProject) => {
    if (!client) return;
    const pinned = !project.pinned;
    const mark = (list: HomeProject[]) => list.map(item => item.id === project.id ? { ...item, pinned } : item);
    setMine(list => list && mark(list));
    setTeam(mark);
    const { error: pinError } = await client.schema("api").rpc("set_tactics_project_pinned", { target_project_id: project.id, pin: pinned });
    if (pinError) {
      setError("Projektet kunde inte fästas.");
      const undo = (list: HomeProject[]) => list.map(item => item.id === project.id ? { ...item, pinned: !pinned } : item);
      setMine(list => list && undo(list));
      setTeam(undo);
    }
  };

  /** Removes the project once confirmed; true when it is gone. */
  const remove = async (project: HomeProject, confirmText: string) => {
    if (!client || !window.confirm(confirmText)) return false;
    const { error: removeError } = await client.schema("api").rpc("delete_tactics_project", { target_project_id: project.id });
    if (removeError) { setError("Projektet kunde inte tas bort."); return false; }
    void load(filters);
    return true;
  };

  const unpublish = async (item: Published) => {
    if (!client || !window.confirm(`Sluta publicera ${item.title}? De som redan använt den behåller sina kopior.`)) return;
    const { error: removeError } = await client.schema("api").rpc("unshare_tactics_item", { target_shared_id: item.shared_id });
    if (removeError) { setError("Det kunde inte tas bort ur TeamZones bibliotek."); return; }
    void load(filters);
  };

  return { mine, team, error, reload, pin, remove, unpublish };
}
