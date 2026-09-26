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
      "För konto, säkerhet och central plattformsdrift är [JURIDISKT NAMN], organisationsnummer [ORG.NR], adress [POSTADRESS], avsedd personuppgiftsansvarig.",
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
      "[PLACEHOLDER: aktuell lista över personuppgiftsbiträden, behandlingsplatser och eventuella tredjelandsöverföringar.]",
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
      "Integritetsfrågor och rättighetsbegäranden skickas tills vidare genom TeamZones interna supportflöde. [PLACEHOLDER: offentlig dataskyddskontakt och eventuell dataskyddsansvarig.]",
      "Väsentliga ändringar versionssätts och kan kräva att användaren läser och bekräftar den nya versionen i appen.",
    ],
  },
] as const;

export default function PrivacyPage() {
  return (
    <LegalDocument
      eyebrow="Din integritet"
      title="Integritetspolicy"
      version="2026-09-11-draft"
      introduction="Här beskriver vi hur TeamZone avser att behandla personuppgifter. Dokumentet är ett tekniskt komplett placeholderutkast och måste juridiskt granskas före produktionsbruk."
      sections={sections}
    />
  );
}
