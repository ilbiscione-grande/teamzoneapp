"use client";

import { useCallback, useEffect, useState } from "react";
import { call, NoticeBar, Panel, useAdminAction, type AdminEnv } from "./admin-ui";

type Visibility = { show_matches: boolean; show_results: boolean; show_training: boolean; revision: number };

export function AdminTeams({ env }: { env: AdminEnv }) {
  const teams = env.scope.teams;
  const [teamId, setTeamId] = useState(teams[0]?.teamId ?? "");
  if (!teams.length) return <Panel title="Matcher och träningar"><p className="ad-empty">Du hanterar inga lag i den här klubben.</p></Panel>;
  const team = teams.find(item => item.teamId === teamId) ?? teams[0];
  return <Panel title="Matcher och träningar" lead="Välj vad lagsidan visar. Ändringen gäller lagets alla matcher och träningar.">
    {teams.length > 1 && <label className="ad-form-row">Lag<select value={team.teamId} onChange={event => setTeamId(event.target.value)}>{teams.map(item => <option key={item.teamId} value={item.teamId}>{item.name}</option>)}</select></label>}
    <TeamVisibility key={team.teamId} env={env} teamId={team.teamId} />
  </Panel>;
}

function TeamVisibility({ env, teamId }: { env: AdminEnv; teamId: string }) {
  const { rpc } = env;
  const [value, setValue] = useState<Visibility | null>(null);
  const [saved, setSaved] = useState<Visibility | null>(null);
  const [loadError, setLoadError] = useState(false);
  const { busy, notice, run } = useAdminAction();

  const load = useCallback(async () => {
    setLoadError(false);
    try {
      const data = await call(rpc, "get_team_event_visibility", { team_id: teamId }) as Partial<Visibility>;
      const next = { show_matches: data.show_matches === true, show_results: data.show_results === true, show_training: data.show_training === true, revision: Number(data.revision ?? 0) };
      setValue(next); setSaved(next);
    } catch { setLoadError(true); }
  }, [rpc, teamId]);
  useEffect(() => { void load(); }, [load]);

  if (loadError) return <p className="ad-notice error">Inställningarna kunde inte hämtas. <button className="ad-link" onClick={() => void load()}>Försök igen</button></p>;
  if (!value) return <p className="ad-muted">Hämtar…</p>;
  const changed = JSON.stringify(value) !== JSON.stringify(saved);
  const toggle = (key: keyof Omit<Visibility, "revision">) => setValue({ ...value, [key]: !value[key] });

  return <form className="ad-form" onSubmit={async event => {
    event.preventDefault();
    const ok = await run(() => call(rpc, "set_team_event_visibility_v2", {
      team_id: teamId, show_results: value.show_results, show_training: value.show_training, show_matches: value.show_matches, expected_revision: value.revision,
    }).then(() => undefined), "Lagets publiceringsinställningar är sparade.");
    if (ok) await load();
  }}>
    <label className="ad-check"><input type="checkbox" checked={value.show_matches} onChange={() => toggle("show_matches")} />Visa matcher</label>
    <label className="ad-check"><input type="checkbox" checked={value.show_results} onChange={() => toggle("show_results")} />Visa matchresultat</label>
    <label className="ad-check"><input type="checkbox" checked={value.show_training} onChange={() => toggle("show_training")} />Visa träningstider</label>
    <NoticeBar notice={notice} />
    <div className="ad-actions"><button className="ad-button" disabled={busy || !changed}>Spara</button></div>
  </form>;
}
