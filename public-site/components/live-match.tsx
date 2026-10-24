"use client";

import { useEffect, useMemo, useState } from "react";
import { clockLabel, matchStory, variantFor, type LiveMatch } from "../lib/match-live";

// Decision package 12: the match under way on the team's page — the score,
// the clock and the match's course in the report's words, newest first —
// asked for again every 20 seconds while one is under way (PLM-08), and
// every other minute otherwise so a match that starts shows up. The page's
// own copy may be up to a minute old, so the card asks at once too.
const pollLive = 20_000;
const pollIdle = 120_000;

export function LiveMatches({ teamId, teamName, initial, serverNow }: {
  teamId: string;
  teamName: string;
  initial: LiveMatch[];
  serverNow: string;
}) {
  const [items, setItems] = useState(initial);
  // Server time minus this device's, so the clock runs as the leaders' does.
  const [offset, setOffset] = useState(() => Date.parse(serverNow) - Date.now());
  const [now, setNow] = useState(() => new Date());
  const live = items.filter(item => item.state === "live");

  const underWay = live.length > 0;
  useEffect(() => {
    let stopped = false;
    let timer: number | undefined;
    const ask = async () => {
      if (document.visibilityState === "visible") {
        try {
          const response = await fetch(`/api/public/v1/teams/${teamId}/live`, { cache: "no-store" });
          if (response.ok && !stopped) {
            const data = await response.json() as { items?: LiveMatch[]; server_now?: string };
            if (data.server_now) setOffset(Date.parse(data.server_now) - Date.now());
            setItems(data.items ?? []);
          }
        } catch { /* the next round tries again */ }
      }
      if (!stopped) timer = window.setTimeout(ask, underWay ? pollLive : pollIdle);
    };
    void ask();
    return () => { stopped = true; window.clearTimeout(timer); };
  }, [teamId, underWay]);

  useEffect(() => {
    if (!live.length) return;
    const tick = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(tick);
  }, [live.length]);

  if (!live.length) return null;
  return (
    <section id="live" className="cs-section cs-live-section" aria-live="polite">
      <div className="cs-wrap">
        {live.map(match => <LiveCard key={match.id} match={match} teamName={teamName} now={new Date(now.getTime() + offset)} />)}
      </div>
    </section>
  );
}

function LiveCard({ match, teamName, now }: { match: LiveMatch; teamName: string; now: Date }) {
  const opponent = match.opponent_name?.trim() || "Motståndare";
  const story = useMemo(
    () => matchStory(match.feed, { team: teamName, opponent, homeAway: match.home_away, variant: variantFor(match.id) }),
    [match.feed, match.id, match.home_away, opponent, teamName],
  );
  const clock = clockLabel(match, now);
  const weLeft = match.home_away !== "away";
  const left = weLeft ? [teamName, match.score_us] as const : [opponent, match.score_opponent] as const;
  const right = weLeft ? [opponent, match.score_opponent] as const : [teamName, match.score_us] as const;
  return (
    <article className="cs-live">
      <div className="cs-live-top">
        <span className="cs-live-badge"><i aria-hidden="true" />Live</span>
        <span>{match.title}</span>
      </div>
      <div className="cs-score cs-live-score">
        <span>{left[0]}</span>
        <strong>{left[1]}<i>–</i>{right[1]}</strong>
        <span>{right[0]}</span>
      </div>
      <p className="cs-live-clock"><strong>{clock.time}</strong> · {clock.phase}</p>
      {story.length ? (
        <ol className="cs-live-feed">{[...story].reverse().map((line, index) => <li key={story.length - index}>{line}</li>)}</ol>
      ) : <p className="cs-live-empty">Matchen är igång. Händelserna dyker upp här.</p>}
    </article>
  );
}

/** A played match's course, under its result (PLM-05). */
export function MatchCourse({ match, teamName }: { match?: LiveMatch; teamName: string }) {
  if (!match || match.state !== "completed") return null;
  const story = matchStory(match.feed, {
    team: teamName,
    opponent: match.opponent_name,
    homeAway: match.home_away,
    variant: variantFor(match.id),
  });
  if (!story.length) return null;
  return (
    <details className="match-report match-course">
      <summary>Matchens gång</summary>
      <ol>{story.map((line, index) => <li key={index}>{line}</li>)}</ol>
    </details>
  );
}
