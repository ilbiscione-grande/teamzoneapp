import type { Resource, ResourceCategory } from "./booking.ts";
import { resourceAdminGroups } from "./resource-admin.ts";

export type AvailabilityRow = { resource_id:string; busy:boolean; outside_disposition:boolean; busy_resource_name:string|null; busy_from:string|null; busy_to:string|null };
export type AvailabilityState = "inactive" | "unknown" | "outside" | "busy" | "free";
export function availabilityState(resource: Resource, rows: AvailabilityRow[] | null): AvailabilityState {
  if (!resource.active) return "inactive";
  const matching = rows?.filter(row => row.resource_id === resource.id) ?? [];
  if (!matching.length) return "unknown";
  if (matching.some(row => row.outside_disposition === true)) return "outside";
  if (matching.some(row => row.busy === true)) return "busy";
  return matching.every(row => row.busy === false && row.outside_disposition === false) ? "free" : "unknown";
}
export function availabilityGroups(resources: Resource[], rows: AvailabilityRow[] | null, query: string, category: ResourceCategory | "all", onlyFree: boolean) {
  return resourceAdminGroups(resources,query,category,"all").map(group => ({...group,matchingIds:group.matchingIds.filter(id => !onlyFree || availabilityState(group.items.find(item => item.resource.id === id)!.resource,rows) === "free")})).filter(group => group.matchingIds.length > 0);
}
