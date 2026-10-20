// The Webtools catalog. Each app works on its own; all of them sign in with
// the TeamZone account, and a club or team connection is optional.

export type AppStatus = "planned" | "beta" | "live";

export type WebtoolApp = {
  slug: string;
  name: string;
  /** Two letters for the app's mark. */
  mark: string;
  tagline: string;
  description: string;
  features: string[];
  status: AppStatus;
};

export const webtoolApps: WebtoolApp[] = [
  {
    slug: "tacticsboard",
    name: "Tacticsboard",
    mark: "TB",
    tagline: "Rita, animera och presentera taktik.",
    description: "En taktiktavla för träning, genomgångar och matchförberedelser. Rita upp spelsystem och övningar, animera förlopp och visa dem för laget.",
    features: ["Planer för flera sporter", "Animationer steg för steg", "Laguppställningar från din trupp", "Dela och exportera"],
    status: "planned",
  },
  {
    slug: "video-analyzer",
    name: "Video Analyzer",
    mark: "VA",
    tagline: "Klipp, märk och visa matchvideo.",
    description: "Gå igenom matcher och träningar på video. Markera situationer, rita i bilden och samla klipp till genomgångar med laget eller enskilda spelare.",
    features: ["Taggning av situationer", "Ritverktyg i bilden", "Klippsamlingar", "Dela med spelare"],
    status: "planned",
  },
  {
    slug: "bokningshanterare",
    name: "Bokningshanterare",
    mark: "BH",
    tagline: "Boka planer, hallar och material.",
    description: "Håll ordning på planer, hallar, omklädningsrum och material. Se vad som är ledigt, boka och få översikt över klubbens anläggningar.",
    features: ["Kalender per anläggning", "Bokningsförfrågningar", "Krockkontroll", "Material och utrustning"],
    status: "planned",
  },
  {
    slug: "turneringsplanerare",
    name: "Turneringsplanerare",
    mark: "TP",
    tagline: "Planera cuper och turneringar.",
    description: "Lägg upp grupper, spelschema och slutspel. Fördela planer och tider, för in resultat och visa tabeller för lag och publik.",
    features: ["Grupper och slutspel", "Spelschema med planer", "Resultat och tabeller", "Publik sida för cupen"],
    status: "planned",
  },
];

export const statusLabel: Record<AppStatus, string> = {
  planned: "Kommer snart",
  beta: "Beta",
  live: "Tillgänglig",
};

export function findApp(slug: string): WebtoolApp | undefined {
  return webtoolApps.find(app => app.slug === slug);
}

/** Only Webtools' own pages are valid places to return to after signing in. */
export function safeReturnTo(value: string | null | undefined): string {
  if (!value) return "/";
  if (value === "/" || value === "/konto") return value;
  const app = /^\/appar\/([a-z0-9-]+)$/.exec(value);
  return app && findApp(app[1]) ? value : "/";
}
