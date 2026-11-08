import { resourceTree, type Resource } from "./booking.ts";

/** Preserve inactive ancestors and mixed resource types when presenting subdivisions. */
export function resourceFamilies(resources: Resource[]): { root: Resource; items: { resource: Resource; depth: number }[] }[] {
  const families: { root: Resource; items: { resource: Resource; depth: number }[] }[] = [];
  for (const node of resourceTree(resources)) {
    if (node.depth === 0 || families.length === 0) families.push({ root: node.resource, items: [] });
    families[families.length - 1].items.push(node);
  }
  return families;
}
