import { dateKey, resourcePath, type Resource, type SeriesOverride, type SeriesTime } from './booking.ts';
import { pitchOptions } from './pitch-options.ts';

export function seriesScopeLabel(ids: string[], resources: Resource[]): string {
  for (const root of resources) {
    const option = pitchOptions(root,resources).find(option=>option.resourceIds.length===ids.length && option.resourceIds.every(id=>ids.includes(id)));
    if (option) return `${root.name} · ${option.label}`;
  }
  return ids.map(id=>{const r=resources.find(r=>r.id===id);return r ? resourcePath(r,resources) : id;}).join(', ');
}

/** Same date and duration; never silently replace a half pitch with a quarter. */
export function seriesCandidates(time: SeriesTime, selected: string[], resources: Resource[]): SeriesOverride[] {
  const ids = time.resource_ids ?? selected;
  const original = time.original_starts_at ?? time.starts_at;
  const start = new Date(time.starts_at), end = new Date(time.ends_at);
  const result: SeriesOverride[] = [];
  for (const minutes of [-30, 30, -60, 60, -90, 90, -120, 120]) {
    const a = new Date(start.getTime() + minutes * 60000), z = new Date(end.getTime() + minutes * 60000);
    if (dateKey(a) === dateKey(start) && dateKey(z) === dateKey(start) && a > new Date())
      result.push({ original_starts_at: original, starts_at: a.toISOString(), ends_at: z.toISOString(), resource_ids: ids });
  }
  for (const root of resources) {
    const options = pitchOptions(root, resources);
    const current = options.find(option => option.resourceIds.length === ids.length && option.resourceIds.every(id => ids.includes(id)));
    if (!current) continue;
    const extent = (id: string) => id === 'full' ? 4 : id.startsWith('three-') ? 3 : id.length === 1 ? 2 : 1;
    for (const option of options.filter(option => option.id !== current.id && extent(option.id) === extent(current.id)))
      result.push({ original_starts_at: original, starts_at: time.starts_at, ends_at: time.ends_at, resource_ids: option.resourceIds });
    break;
  }
  return result;
}

/** Missing, duplicate or malformed availability rows never imply availability. */
export function checkedSeriesCandidate(ids: string[], data: unknown): boolean {
  if (!data || typeof data !== 'object' || !('items' in data) || !Array.isArray(data.items)) return false;
  const items = data.items as {resource_id?: unknown; busy?: unknown}[];
  return items.length === ids.length && ids.every(id => {
    const rows = items.filter(row => row?.resource_id === id);
    return rows.length === 1 && rows[0].busy === false;
  });
}
