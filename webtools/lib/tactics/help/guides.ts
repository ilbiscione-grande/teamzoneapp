// All the guides, in the order the help page lists them.
import { drawGuides } from "./guides-draw.ts";
import type { Guide } from "./model.ts";
import { showGuides } from "./guides-show.ts";

export const guides: Guide[] = [...drawGuides, ...showGuides];

export const guideBySlug = (slug: string) => guides.find(guide => guide.slug === slug) ?? null;
