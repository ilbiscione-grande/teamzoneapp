import type { Metadata } from "next";
import { LegalDocument } from "../../components/legal-document";

export const metadata: Metadata = {
  title: "Integritetspolicy",
  description: "Integritetspolicy för TeamZone.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. Personuppgiftsansvar",
    paragraphs: [
      "För konto, säkerhet, central plattformsdrift och Tacticsboard är Tre 60 Grader, enskild näringsidkare, organisationsnummer 19790531-2471, Plangränd 15, 574 34 Vetlanda, personuppgiftsansvarig.",
      "Varje klubb kan vara separat personuppgiftsansvarig för de medlems-, lag- och verksamhetsuppgifter som klubben bestämmer ändamål och medel för. Den exakta ansvarsfördelningen ska fastställas juridiskt före produktionsbruk.",
    ],
  },
  {
    title: "2. Uppgifter vi behandlar",
    items: [
      "Konto- och profiluppgifter, exempelvis namn, e-post, språk och autentiseringsstatus.",
      "Klubb-, lag-, roll-, medlems- och verifierade vårdnadshavarrelationer.",
      "Event, kallelser, svar, närvaro, meddelanden och material som behöriga användare lägger in.",
      "Support-, säkerhets- och revisionsuppgifter som behövs för spårbarhet och missbruksbekämpning.",
      "Frivilliga inställningar, exempelvis marknadsföringsval. Marknadsföring är av som standard.",
    ],
  },
  {
    title: "3. Ändamål och rättslig grund",
    items: [
      "Tillhandahålla konto och avtalade funktioner: fullgörande av avtal.",
      "Skydda konton, förebygga missbruk och bevara nödvändig audit: berättigat intresse och rättsliga skyldigheter där tillämpligt.",
      "Administrera klubb- och lagverksamhet: den grund som respektive ansvarig klubb fastställer.",
      "Skicka marknadsföring: endast efter frivilligt val, som kan återkallas när som helst.",
      "[PLACEHOLDER: slutlig laglig-grundmatris och intresseavvägningar fastställs vid juridisk granskning.]",
    ],
  },
  {
    title: "4. Behörighet och delning",
    paragraphs: [
      "Uppgifter visas enligt aktiva klubb-, lag- och rollkopplingar. TeamZone säljer inte personuppgifter. Uppgifter kan behandlas av avtalade leverantörer för exempelvis hosting, databas, autentisering, filhantering, e-post och driftövervakning.",
    ],
    items: [
      "Supabase: databas, inloggning och filer. Uppgifterna lagras inom EU.",
      "Google Firebase: drift av webbplatserna och aviseringar i appen.",
      "Resend: utskick av e-post, till exempel bekräftelser och aviseringar.",
      "ImprovMX och Google Gmail: mottagning av mejl till supporten.",
      "Stripe: betalning för Tacticsboard. Stripe är självständigt personuppgiftsansvarig för kort- och betaluppgifterna.",
      "[PLACEHOLDER: behandlingsplatser, tredjelandsöverföringar och skyddsåtgärder per leverantör kontrolleras och anges före lansering.]",
    ],
  },
  {
    title: "4 a. Tacticsboard",
    items: [
      "Vi sparar dina projekt, tavlor, mallar och mappar, det du publicerar i biblioteket, dina delade länkar och livegenomgångar, och anmälningar du gör.",
      "Om prenumerationen sparar vi provperiodens datum, prenumerationens status och period samt en hänvisning till din kund hos Stripe. Vi sparar inga kortuppgifter.",
      "Namn på spelare som du skriver på tavlorna är personuppgifter som du själv ansvarar för.",
      "Kvitton och fakturor sparas hos Stripe i sju år, eftersom bokföringslagen kräver det. Det gäller även om du avslutar kontot.",
    ],
  },
  {
    title: "5. Barns personuppgifter",
    paragraphs: [
      "Barns uppgifter skyddas genom dataminimering, rollstyrning och privata standardinställningar. Vårdnadshavare får endast agera genom en verifierad relation. Känsliga utvecklings-, hälso- eller medieflöden aktiveras inte utan särskilt beslutad policy.",
      "[PLACEHOLDER: minimiålder, samtyckesregler och information riktad till barn/vårdnadshavare.]",
    ],
  },
  {
    title: "6. Lagring och radering",
    paragraphs: [
      "Uppgifter lagras inte längre än vad ändamålet, avtalet, säkerheten eller lagkrav kräver. Konto- och medlemskopplingar kan avslutas, medan nödvändig verksamhets- och revisionshistorik kan bevaras med neutral eller anonymiserad identitet.",
      "[PLACEHOLDER: fullständig retentionstabell per datatyp och gallringsintervall.]",
    ],
  },
  {
    title: "7. Dina rättigheter",
    items: [
      "Begära tillgång till och rättelse av dina personuppgifter.",
      "Begära radering eller begränsning när förutsättningarna är uppfyllda.",
      "Invända mot behandling som bygger på berättigat intresse.",
      "Återkalla frivilligt samtycke utan att tidigare behandling blir olaglig.",
      "Begära dataportabilitet där den rätten gäller och lämna klagomål till Integritetsskyddsmyndigheten.",
    ],
  },
  {
    title: "8. Säkerhet",
    paragraphs: [
      "TeamZone använder bland annat autentisering, minsta behörighet, servervalidering, isolering mellan klubbar, revisionsloggar och skyddade administrativa funktioner. Ingen digital tjänst kan garantera absolut säkerhet.",
    ],
  },
  {
    title: "9. Cookies och lokal lagring",
    paragraphs: [
      "Nödvändig teknik kan användas för inloggning, säkerhet och användarens uttryckliga inställningar. [PLACEHOLDER: komplett cookie- och analysförteckning innan icke nödvändig mätning aktiveras.]",
    ],
  },
  {
    title: "10. Kontakt och ändringar",
    paragraphs: [
      "Integritetsfrågor och begäranden om dina rättigheter mejlar du till support@teamzoneapp.se. Vi svarar inom två vardagar.",
      "Väsentliga ändringar versionssätts och kan kräva att användaren läser och bekräftar den nya versionen i appen.",
    ],
  },
] as const;

export default function PrivacyPage() {
  return (
    <LegalDocument
      eyebrow="Din integritet"
      title="Integritetspolicy"
      version="2026-11-04-draft"
      updated="4 november 2026"
      introduction="Här beskriver vi hur TeamZone avser att behandla personuppgifter. Dokumentet är ett tekniskt komplett placeholderutkast och måste juridiskt granskas före produktionsbruk."
      sections={sections}
    />
  );
}
