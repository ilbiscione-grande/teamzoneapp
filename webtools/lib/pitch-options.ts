import type { Resource } from './booking';

export type PitchOption = { id: string; label: string; resourceIds: string[] };
/** Only explicit owner layouts with the original physical relationships qualify. */
export function pitchOptions(root: Resource | undefined, resources: Resource[]): PitchOption[] {
  const layout = root?.pitch_layout;
  if (!root?.active || root.category !== 'pitch' || !layout) return [];
  const keys = ['A','B','A1','A2','B1','B2'];
  if (new Set(keys.map(key => layout[key])).size !== 6) return [];
  for (const key of keys) {
    const part = resources.find(item => item.id === layout[key]);
    if (!part || !part.active || part.category !== 'pitch' || part.parent_resource_id !== (key.length === 1 ? root.id : layout[key[0]])) return [];
    if (key.length === 2 && resources.some(item => item.parent_resource_id === part.id)) return [];
  }
  if (resources.filter(item => item.parent_resource_id === root.id).length !== 2
    || keys.slice(0,2).some(key => resources.filter(item => item.parent_resource_id === layout[key]).length !== 2)) return [];
  const name = (key: string) => resources.find(item => item.id === layout[key])!.name;
  // Preserve owner names; add the extent only when the name does not already say it.
  const partLabel = (key: string, extent: string) => {
    const partName = name(key).trim();
    return new RegExp(`^${extent}(?:\\s|$)`, 'iu').test(partName) ? partName : `${extent} · ${partName}`;
  };
  return [
    {id:'full',label:'Helplan',resourceIds:[root.id]},
    ...['A','B'].map(key => ({id:key,label:partLabel(key,'Halvplan'),resourceIds:[layout[key]]})),
    ...['A1','A2','B1','B2'].map(key => ({id:key,label:partLabel(key,'Fjärdedelsplan'),resourceIds:[layout[key]]})),
    ...['A1','A2','B1','B2'].map(key => ({id:`three-${key}`,label:`¾-plan · allt utom ${name(key)}`,resourceIds:keys.slice(2).filter(other => other !== key).map(other => layout[other])})),
  ];
}

export function dispositionLabel(resource: Resource): string {
  return resource.available_from ? `${resource.available_from}–${resource.available_until || 'tills vidare'}` : 'Utan egen tidsbegränsning';
}
