import type { Resource } from "./booking.ts";

export type ResourceAvailabilityResult = {
  resource_id: string;
  busy: boolean;
  outside_disposition: boolean;
};

/** A missing or incomplete server result never counts as free. */
export function bookingAlternatives(resources: Resource[], rows: ResourceAvailabilityResult[], selectedId: string): Resource[] {
  const selected = resources.find(resource => resource.id === selectedId);
  if (!selected) return [];
  return resources.filter(resource => resource.active && resource.id !== selectedId &&
    rows.some(row => row.resource_id === resource.id && row.busy === false && row.outside_disposition === false) &&
    !rows.some(row => row.resource_id === resource.id && (row.busy !== false || row.outside_disposition !== false)))
    .sort((a, b) => Number(b.category === selected.category) - Number(a.category === selected.category) || a.name.localeCompare(b.name, "sv"));
}
