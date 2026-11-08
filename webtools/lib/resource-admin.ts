import { categoryLabels, resourcePath, type Resource, type ResourceCategory } from "./booking.ts";
import { resourceFamilies } from "./resource-families.ts";

export type ResourceStatusFilter = "all" | "active" | "inactive";

/** Match individual resources but retain their full family, including inactive ancestors and siblings. */
export function resourceAdminGroups(resources: Resource[], query: string, category: ResourceCategory | "all", status: ResourceStatusFilter) {
  const words = query.trim().toLocaleLowerCase("sv").split(/\s+/).filter(Boolean);
  return resourceFamilies(resources).map(group => ({...group, matchingIds: group.items.filter(({resource}) => {
    if (category !== "all" && resource.category !== category) return false;
    if (status === "active" && !resource.active || status === "inactive" && resource.active) return false;
    const ownership = resource.ownership_kind === "external" ? "Extern externt disponerad" : resource.ownership_kind === "owned" ? "Egen resurs" : "Ägande ej angivet";
    const text = [resourcePath(resource,resources),categoryLabels[resource.category],resource.location,resource.owner_name,ownership,resource.description].filter(Boolean).join(" ").toLocaleLowerCase("sv");
    return words.every(word => text.includes(word));
  }).map(({resource}) => resource.id)})).filter(group => group.matchingIds.length > 0);
}
