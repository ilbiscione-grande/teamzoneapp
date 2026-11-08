/** Assign overlapping reservations separate lanes, keeping touching intervals together. */
export function calendarLanes<T extends { id: string; top: number; height: number }>(items: T[]): { item: T; lane: number; lanes: number }[] {
  const sorted = [...items].sort((a,b) => a.top-b.top || a.id.localeCompare(b.id));
  const ends: number[] = [];
  const assigned = sorted.map(item => {
    let lane = ends.findIndex(end => end <= item.top + 1e-10);
    if (lane < 0) lane = ends.length;
    ends[lane] = item.top + item.height;
    return { item, lane };
  });
  return assigned.map(item => ({...item,lanes:Math.max(ends.length,1)}));
}
