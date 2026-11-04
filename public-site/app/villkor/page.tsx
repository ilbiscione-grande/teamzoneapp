import type { Metadata } from "next";
import { LegalDocument } from "../../components/legal-document";

export const metadata: Metadata = {
  title: "Användarvillkor",
  description: "Användarvillkor för TeamZone.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. Om TeamZone och avtalet",
    paragraphs: [
      "TeamZone är en digital tjänst för idrottsklubbar, lag, ledare, spelare, vårdnadshavare och klubbfunktionärer. Dessa villkor reglerar användningen av tjänsten.",
      "Tjänsteleverantör: Tre 60 Grader, enskild näringsidkare, organisationsnummer 19790531-2471, Plangränd 15, 574 34 Vetlanda.",
    ],
  },
  {
    title: "2. Konto och behörighet",
    items: [
      "Du ska lämna korrekta kontouppgifter och skydda dina inloggningsuppgifter.",
      "Åtkomst styrs av klubb-, lag- och rollkopplingar. Du får endast använda behörigheter som faktiskt har tilldelats dig.",
      "Vårdnadshavare får agera för ett barn endast genom en verifierad relation i tjänsten.",
      "Klubben ansvarar för att dess roller, medlemskap och publiceringsbehörigheter hålls aktuella.",
    ],
  },
  {
    title: "3. Tillåten användning",
    paragraphs: ["TeamZone får endast användas för laglig och idrottsrelaterad verksamhet."],
    items: [
      "Du får inte försöka kringgå behörighetskontroller eller få åtkomst till andra användares uppgifter.",
      "Du får inte publicera olagligt, kränkande, vilseledande eller integritetskänsligt innehåll utan stöd.",
      "Du får inte störa tjänstens drift, automatisera missbruk eller använda skyddade klubbnamn utan godkännande.",
    ],
  },
  {
    title: "4. Klubbarnas och användarnas innehåll",
    paragraphs: [
      "Den som lägger in text, bilder eller annan information ansvarar för att nödvändiga rättigheter och tillstånd finns. Äganderätten till innehållet övergår inte till TeamZone.",
      "Du ger TeamZone den begränsade rätt som behövs för att lagra, bearbeta och visa innehållet inom tjänsten enligt dina val och behörigheter.",
    ],
  },
  {
    title: "5. Minderåriga",
    paragraphs: [
      "Klubbar och ansvariga vuxna ska behandla barns uppgifter varsamt och följa tillämpliga regler, lagliga grunder och samtyckeskrav. Publik exponering av minderårigas uppgifter är avstängd som utgångspunkt.",
      "[PLACEHOLDER: fastställd minimiålder och detaljerad guardianpolicy införs efter juridisk granskning.]",
    ],
  },
  {
    title: "6. Drift, ändringar och tillgänglighet",
    paragraphs: [
      "Vi arbetar för en säker och tillgänglig tjänst men kan inte garantera oavbruten drift. Underhåll, säkerhetsåtgärder eller externa tjänster kan tillfälligt påverka funktioner.",
      "Väsentliga villkorsändringar versionssätts och kräver ett nytt uttryckligt godkännande i appen.",
    ],
  },
  {
    title: "7. Avstängning och avslut",
    paragraphs: [
      "Åtkomst kan begränsas vid säkerhetsrisk, misstänkt missbruk eller väsentligt avtalsbrott. Användare kan begära kontoavslut och personuppgiftshantering enligt integritetspolicyn. Verksamhetshistorik kan behöva bevaras i anonymiserad form.",
    ],
  },
  {
    title: "8. Avgifter och betalning",
    paragraphs: [
      "Tacticsboard säljs som prenumeration till enskilda personer. Pris, provperiod, betalning, uppsägning och ångerrätt står i Villkor för Tacticsboard, som du godkänner när du köper.",
      "[PLACEHOLDER: avgifter för klubbar avtalas separat och införs här innan de aktiveras.]",
    ],
  },
  {
    title: "9. Ansvar och tillämplig lag",
    paragraphs: [
      "TeamZone ersätter inte professionell medicinsk, juridisk eller ekonomisk rådgivning. Användare och klubbar ansvarar för sina verksamhetsbeslut.",
      "Svensk lag gäller för villkoren. Som konsument kan du vända dig till Allmänna reklamationsnämnden (ARN), arn.se, om vi inte kommer överens. Tvister kan också prövas av allmän domstol.",
      "[PLACEHOLDER: ansvarsbegränsningen fastställs vid juridisk granskning.]",
    ],
  },
  {
    title: "10. Kontakt",
    paragraphs: [
      "Frågor om villkoren mejlar du till support@teamzoneapp.se. Vi svarar inom två vardagar.",
    ],
  },
] as const;

export default function TermsPage() {
  return (
    <LegalDocument
      eyebrow="Juridik"
      title="Användarvillkor"
      version="2026-11-04-draft"
      updated="4 november 2026"
      introduction="Läs villkoren innan du skapar eller använder ett TeamZone-konto. Detta dokument är ett tekniskt komplett placeholderutkast och är ännu inte juridiskt godkänt."
      sections={sections}
    />
  );
}
