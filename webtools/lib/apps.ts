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
  /** Where the app itself opens, once it is there. */
  href?: string;
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
    href: "/bokningar",
    name: "Bokningshanterare",
    mark: "BH",
    tagline: "Boka planer, hallar och material.",
    description: "Boka allt från planer, hallar och omklädningsrum till minibussar och kameror. Fungerar för alla sporter och föreningar, med eller utan TeamZone. Med TeamZone bokar ledare för sina lag och kopplar bokningen till en aktivitet, till exempel minibussen till bortamatchen.",
    features: ["Planer, lokaler, fordon och utrustning", "Krockar stoppas", "Godkännande per resurs", "Bokning för laget och aktiviteten i TeamZone"],
    status: "beta",
  },
  {
    slug: "turneringsplanerare",
    href: "/turneringar",
    name: "Turneringsplanerare",
    mark: "TP",
    tagline: "Planera cuper och turneringar.",
    description: "Skapa turneringen och dess klasser, öppna anmälan och dela länken. Lag anmäler sig och du godkänner dem och bockar av avgifterna. Fungerar med eller utan TeamZone. Grupper, spelschema, resultat och slutspel kommer härnäst.",
    features: ["Klasser med gruppspel och slutspel eller poolspel", "Anmälan via länk med godkännande", "Avgifter och betalningar", "Arrangörer och funktionärer"],
    status: "beta",
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
  if (value === "/" || value === "/konto" || value === "/bokningar" || value === "/aviseringar" || value === "/turneringar") return value;
  // A tournament, which is also its registration link, and staff invitations.
  if (/^\/turneringar\/[0-9a-f-]{36}$/.test(value)) return value;
  if (/^\/turneringar\?inbjudan=[0-9a-f]{64}$/.test(value)) return value;
  if (/^\/bokningar\/[0-9a-f-]{36}$/.test(value)) return value;
  // From the app's "Boka resurs": the team and activity to book for.
  if (/^\/bokningar\/[0-9a-f-]{36}\?boka=1(&lag=[0-9a-f-]{36})?&aktivitet=[0-9a-f-]{36}$/.test(value)) return value;
  // An invitation link survives signing in.
  if (/^\/bokningar\?inbjudan=[0-9a-f]{64}$/.test(value)) return value;
  const app = /^\/appar\/([a-z0-9-]+)$/.exec(value);
  return app && findApp(app[1]) ? value : "/";
}
