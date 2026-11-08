export type CalendarView = 'day' | 'week' | 'list';
export type CalendarPreference = {view:CalendarView;resourceId:string};

export function calendarPreferenceKey(organizationId:string):string {
  return `wt-booking-view-${organizationId}`;
}

/** Local preferences never restore resources that the organization no longer exposes. */
export function parseCalendarPreference(raw:string|null,resourceIds:string[]):CalendarPreference {
  const fallback:CalendarPreference={view:'day',resourceId:'all-pitches'};
  if(!raw)return fallback;
  try {
    const value:unknown=JSON.parse(raw);
    if(!value || typeof value!=='object' || Array.isArray(value))return fallback;
    const saved=value as Record<string,unknown>;
    return {
      view:saved.view==='day'||saved.view==='week'||saved.view==='list' ? saved.view : 'day',
      resourceId:typeof saved.resourceId==='string' && resourceIds.includes(saved.resourceId) ? saved.resourceId : 'all-pitches',
    };
  }catch{return fallback;}
}
