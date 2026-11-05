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
      "Varje klubb är personuppgiftsansvarig för de medlems-, lag- och verksamhetsuppgifter som klubben själv bestämmer över. Vi behandlar de uppgifterna för klubbens räkning.",
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
      "Sälja och administrera prenumerationer: fullgörande av avtal.",
      "Bokföring och kvitton: rättslig förpliktelse enligt bokföringslagen.",
      "Svara på frågor till supporten: berättigat intresse av att kunna hjälpa dig, eller fullgörande av avtal när frågan gäller din tjänst.",
      "Skicka marknadsföring: endast efter frivilligt val, som kan återkallas när som helst.",
    ],
  },
  {
    title: "4. Behörighet och delning",
    paragraphs: [
      "Uppgifter visas enligt aktiva klubb-, lag- och rollkopplingar. TeamZone säljer inte personuppgifter. Uppgifter kan behandlas av avtalade leverantörer för exempelvis hosting, databas, autentisering, filhantering, e-post och driftövervakning.",
    ],
    items: [
      "Supabase (Singapore): databas, inloggning och filer. Uppgifterna lagras inom EU, för Tacticsboard i Stockholm. Skydd vid åtkomst utanför EU: EU:s standardavtalsklausuler.",
      "Google Firebase (Google): drift av webbplatserna i Nederländerna och aviseringar i appen. Aviseringar kan behandlas utanför EU, bland annat i USA. Skydd: EU-USA:s dataskyddsramverk (Data Privacy Framework).",
      "Resend (USA): utskick av e-post, till exempel bekräftelser och aviseringar. Mottagarens adress och mejlets innehåll lagras i USA. Skydd: EU:s standardavtalsklausuler och dataskyddsramverket.",
      "ImprovMX (USA): tar emot mejl till supporten. Mejl tas emot och lagras tillfälligt i Frankrike och kan vidarebefordras via USA. Skydd: EU:s standardavtalsklausuler.",
      "Google Gmail (Google): supportens inkorg. Mejl kan behandlas utanför EU, bland annat i USA. Skydd: dataskyddsramverket.",
      "Stripe (Irland): betalning för Tacticsboard. Stripe behandlar betalningen för vår räkning och är självständigt personuppgiftsansvarig för egna ändamål, till exempel säkerhet och bedrägeribekämpning. Uppgifter kan föras över till USA och Indien. Skydd: dataskyddsramverket och EU:s standardavtalsklausuler.",
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
      "Du måste vara minst 13 år för att skapa ett eget konto. Yngre barn hanteras bara genom en verifierad vårdnadshavare eller klubb. Skriv inte ut namn på barn i tavlor eller annat du delar öppet.",
    ],
  },
  {
    title: "6. Lagring och radering",
    paragraphs: [
      "Uppgifter lagras inte längre än vad ändamålet, avtalet, säkerheten eller lagkrav kräver. Konto- och medlemskopplingar kan avslutas, medan nödvändig verksamhets- och revisionshistorik kan bevaras med neutral eller anonymiserad identitet.",
    ],
    items: [
      "Konto, projekt och prenumerationsuppgifter: så länge kontot finns. Avslutar du kontot raderas de. Är kontot kopplat till en klubb granskas raderingen först.",
      "Kvitton, fakturor, bokföring och besked om ånger: sju år, eftersom bokföringslagen kräver det för underlaget till betalningar och återbetalningar.",
      "Mejl till supporten: två år efter att ärendet är avslutat.",
      "Fel- och kraschloggar: 30 dagar. Prestandadata: 14 dagar.",
      "E-postloggar hos Resend: 30 dagar.",
      "Säkerhetskopior av databasen: upp till 7 dygn.",
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
      "Vi använder bara det som krävs för att tjänsten ska fungera: din inloggning och dina inställningar, till exempel i Tacticsboard, sparas i webbläsaren. Vi använder inga cookies för analys eller marknadsföring.",
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
      introduction="Här beskriver vi hur TeamZone behandlar personuppgifter."
      sections={sections}
    />
  );
}
