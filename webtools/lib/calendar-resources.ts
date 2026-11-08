import type { Booking, Resource } from './booking.ts';

export function physicalResource(resource: Resource, resources: Resource[]): Resource {
  if (resource.category !== 'pitch') return resource;
  const seen = new Set([resource.id]);
  let root = resource;
  while (root.parent_resource_id) {
    const parent = resources.find(item => item.id === root.parent_resource_id);
    if (!parent || parent.category !== 'pitch' || seen.has(parent.id)) break;
    seen.add(parent.id); root = parent;
  }
  return root;
}

export function calendarResources(resources: Resource[], all: Resource[]): Resource[] {
  return [...new Map(resources.map(resource => { const root=physicalResource(resource,all); return [root.id,root]; })).values()];
}

export type CalendarCard = { id: string; booking: Booking; bookings: Booking[]; resource: Resource; label: string; coverage: string[] | null };

/** Merge only identical occurrences in the same atomic group and physical pitch. */
export function calendarCards(bookings: Booking[], resources: Resource[]): CalendarCard[] {
  const cards = new Map<string, CalendarCard>();
  for (const booking of bookings) {
    const resource = resources.find(item => item.id === booking.resource_id);
    if (!resource) continue;
    const root = physicalResource(resource,resources);
    const key = root.category === 'pitch' && booking.group_id
      ? JSON.stringify([booking.group_id,root.id,booking.starts_at,booking.ends_at,booking.status,booking.title,booking.team_id,booking.event_id,booking.is_mine,booking.can_cancel,booking.can_decide])
      : booking.id;
    const existing = cards.get(key);
    if (existing) existing.bookings.push(booking);
    else cards.set(key,{id:booking.id,booking,bookings:[booking],resource:root,label:'',coverage:null});
  }
  for (const card of cards.values()) {
    const root=card.resource, layout=root.pitch_layout;
    const keys=['A1','A2','B1','B2'];
    const valid=layout && new Set(['A','B',...keys].map(key=>layout[key])).size===6
      && ['A','B',...keys].every(key=>resources.some(item=>item.id===layout[key] && item.category==='pitch' && item.parent_resource_id===(key.length===1?root.id:layout[key[0]])))
      && resources.filter(item=>item.parent_resource_id===root.id).length===2
      && ['A','B'].every(key=>resources.filter(item=>item.parent_resource_id===layout[key]).length===2)
      && keys.every(key=>!resources.some(item=>item.parent_resource_id===layout[key]));
    const covered = new Set<string>();
    let known=!!valid;
    for (const booking of card.bookings) {
      const part = valid ? Object.keys(layout!).find(key=>layout![key]===booking.resource_id) : undefined;
      if (booking.resource_id===root.id) keys.forEach(key=>covered.add(key));
      else if (part) keys.filter(key=>key.startsWith(part)).forEach(key=>covered.add(key));
      else known=false;
    }
    const names=[...new Set(card.bookings.map(booking=>booking.resource_name))].join(' + ');
    if (known) {
      card.coverage=keys.filter(key=>covered.has(key));
      const count=covered.size;
      card.label=count===4?'Helplan':count===3?`¾ plan · utom ${resources.find(item=>item.id===layout![keys.find(key=>!covered.has(key))!])!.name}`
        :count===2?`½ plan · ${names}`:count===1?`¼ plan · ${names}`:names;
    } else card.label=root.category==='pitch' && card.bookings.length===1 && card.booking.resource_id===root.id?'Helplan':names;
  }
  return [...cards.values()];
}
