// The attributes a TeamZone team ticks for its players (strengths and areas to
// develop), named as the app names them. A team's own attributes come by id
// with their label.
import type { Locale } from "../i18n/locale.ts";

const ATTRIBUTES: Record<string, { sv: string; en: string }> = {
  acceleration: { sv: "Acceleration", en: "Acceleration" },
  speed: { sv: "Snabbhet", en: "Speed" },
  strength: { sv: "Fysisk styrka", en: "Physical strength" },
  endurance: { sv: "Uthållighet", en: "Endurance" },
  agility: { sv: "Rörlighet", en: "Agility" },
  jumping: { sv: "Spänst", en: "Jumping" },
  heading: { sv: "Huvudspel", en: "Heading" },
  shooting: { sv: "Skott", en: "Shooting" },
  long_shots: { sv: "Distansskott", en: "Long shots" },
  crossing: { sv: "Inlägg", en: "Crossing" },
  passing: { sv: "Passningar", en: "Passing" },
  long_passing: { sv: "Långa passningar", en: "Long passing" },
  first_touch: { sv: "Mottagning", en: "First touch" },
  dribbling: { sv: "Dribbling", en: "Dribbling" },
  feints: { sv: "Finter", en: "Feints" },
  weak_foot: { sv: "Svagare foten", en: "Weaker foot" },
  finishing: { sv: "Avslut", en: "Finishing" },
  set_pieces: { sv: "Fasta situationer", en: "Set pieces" },
  goalkeeping: { sv: "Målvaktsspel", en: "Goalkeeping" },
  goalkeeping_hands: { sv: "Målvakt – räddningar", en: "Goalkeeper – saves" },
  goalkeeping_feet: { sv: "Målvakt – fotspel", en: "Goalkeeper – footwork" },
  defending_1v1: { sv: "1 mot 1 i försvar", en: "1v1 defending" },
  attacking_1v1: { sv: "1 mot 1 i anfall", en: "1v1 attacking" },
  positioning: { sv: "Positionsspel", en: "Positioning" },
  game_reading: { sv: "Spelförståelse", en: "Reading the game" },
  pressing: { sv: "Press", en: "Pressing" },
  duels: { sv: "Närkamper", en: "Duels" },
  runs_in_behind: { sv: "Djupledslöpningar", en: "Runs in behind" },
  fast_breaks: { sv: "Kontringar", en: "Fast breaks" },
  leadership: { sv: "Ledarskap", en: "Leadership" },
  communication: { sv: "Kommunikation", en: "Communication" },
  work_rate: { sv: "Arbetsvilja", en: "Work rate" },
  composure: { sv: "Lugn under press", en: "Composure" },
};

/** The team's list: the sport's attributes in order, then its own. */
export type TeamAttributes = { sport: string; catalog: { key: string; area: string }[]; custom: { id: string; label: string }[] };

export function attributeName(key: string, attributes: TeamAttributes | null, locale: Locale): string {
  const own = attributes?.custom.find(item => item.id === key);
  if (own) return own.label;
  const known = ATTRIBUTES[key];
  return known ? known[locale === "en" ? "en" : "sv"] : key;
}

/** Every attribute the team can ask for, named. */
export function attributeOptions(attributes: TeamAttributes, locale: Locale): { key: string; name: string }[] {
  return [
    ...attributes.catalog.map(item => ({ key: item.key, name: attributeName(item.key, attributes, locale) })),
    ...attributes.custom.map(item => ({ key: item.id, name: item.label })),
  ];
}
