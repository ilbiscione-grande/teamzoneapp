import type { Metadata } from "next";
import { LegalDocument } from "../../../components/legal-document";

export const metadata: Metadata = {
  title: "Villkor för Tacticsboard",
  description: "Villkor för prenumerationen på Tacticsboard.",
  robots: { index: false, follow: false },
};

const sections = [
  {
    title: "1. Säljaren och avtalet",
    paragraphs: [
      "Tacticsboard säljs av Tre 60 Grader, enskild näringsidkare, organisationsnummer 19790531-2471, momsregistreringsnummer SE790531247101, Plangränd 15, 574 34 Vetlanda. E-post: support@teamzoneapp.se.",
      "Villkoren gäller när du använder Tacticsboard, under provperioden och med en prenumeration. De gäller tillsammans med användarvillkoren för TeamZone. Säger villkoren olika saker gäller dessa för Tacticsboard.",
    ],
  },
  {
    title: "2. Tjänsten",
    paragraphs: [
      "Tacticsboard är en webbtjänst där du ritar, animerar och presenterar taktik och övningar. Du behöver ett konto men inget lag eller klubb i TeamZone. Tjänsten används i en uppdaterad webbläsare på dator, surfplatta eller telefon.",
    ],
  },
  {
    title: "3. Provperioden",
    items: [
      "Provperioden är 7 dagar och kostar ingenting. Den startar första gången du öppnar Tacticsboard och ges en gång per konto.",
      "Du behöver inte lämna några betaluppgifter för att prova.",
      "När provperioden är slut låses Tacticsboard tills du prenumererar. Inget av det du har gjort tas bort.",
    ],
  },
  {
    title: "4. Pris och betalning",
    items: [
      "Prenumerationen kostar 39 kronor per månad eller 390 kronor per år. Priserna är inklusive moms.",
      "Lanseringserbjudande: köper du årsprenumerationen senast den 31 december 2026 får du 25 % rabatt det första året och betalar 292,50 kronor. Därefter gäller ordinarie pris.",
      "Betalningen sköts av Stripe. Du betalar med kort, Apple Pay eller Google Pay. Vi tar inte del av dina kortuppgifter.",
      "Köper du med mer än två dygn kvar av provperioden dras den första betalningen när provperioden är slut. Annars dras den direkt.",
      "Kvitton skickas med e-post och finns under Hantera betalning på kontosidan.",
    ],
  },
  {
    title: "5. Förnyelse och uppsägning",
    items: [
      "Prenumerationen förnyas automatiskt varje månad eller år tills du säger upp den.",
      "Du säger upp när du vill under Hantera betalning på kontosidan. Prenumerationen gäller perioden ut och förnyas sedan inte. Betalt för en påbörjad period återbetalas inte, utom vid ånger enligt avsnitt 6.",
      "Avslutar du ditt konto avslutas prenumerationen direkt, utan återbetalning, utom vid ånger enligt avsnitt 6.",
      "Misslyckas en betalning har du 14 dagar på dig att uppdatera betalningen. Under den tiden fungerar allt. Därefter låses Tacticsboard tills betalningen är ordnad. Inget tas bort.",
    ],
  },
  {
    title: "6. Ångerrätt",
    paragraphs: [
      "Är du konsument har du 14 dagars ångerrätt från den dag du köpte prenumerationen, enligt lagen om distansavtal och avtal utanför affärslokaler.",
      "Du ångrar köpet med knappen Ångra köpet under Abonnemang på kontosidan. Den finns där under hela ångerfristen. Du bekräftar ditt namn och vilken prenumeration det gäller, och bekräftar sedan att du ångrar köpet. Vi skickar direkt ett mottagningsbevis med e-post som visar när vi tog emot beskedet.",
      "Du kan också mejla support@teamzoneapp.se inom 14 dagar eller använda Konsumentverkets standardformulär för ånger. Skriv att du ångrar köpet och vilken e-postadress kontot har.",
      "Vid köpet begär du att prenumerationen börjar direkt. Ångrar du dig betalar du därför en proportionell del av priset för tiden från att den betalda perioden började till att du ångrade dig. Tid under den kostnadsfria provperioden kostar ingenting. Resten betalar vi tillbaka till samma betalsätt inom 14 dagar från att vi fick ditt besked.",
      "Ångerrätten gäller köpet av prenumerationen och inte varje automatisk förnyelse. Du kan alltid säga upp prenumerationen enligt avsnitt 5.",
    ],
  },
  {
    title: "7. Ditt innehåll och biblioteket",
    items: [
      "Projekt, tavlor och mallar du skapar är dina. Vi lagrar och visar dem bara för att tjänsten ska fungera.",
      "Publicerar du något i biblioteket kan andra användare av Tacticsboard se och kopiera det. Du ger dem rätt att använda kopian i sin egen verksamhet. Du kan ta bort det du har publicerat, men kopior som redan har gjorts finns kvar.",
      "Du ansvarar för det du publicerar. Det får inte vara kränkande, olagligt eller kopierat från någon annan utan lov.",
      "Innehåll i biblioteket kan anmälas. Supporten kan dölja innehåll som bryter mot villkoren.",
      "Namn på spelare är personuppgifter. Skriv inte ut namn på andra, särskilt inte barn, i det du publicerar eller delar öppet.",
    ],
  },
  {
    title: "8. Delade länkar och livegenomgångar",
    paragraphs: [
      "Länkar och mappar du har delat fortsätter att fungera även om din prenumeration upphör, tills du tar bort delningen. Den som tar del av en länk eller en livegenomgång behöver ingen prenumeration.",
    ],
  },
  {
    title: "9. Drift och ändringar",
    items: [
      "Vi arbetar för att Tacticsboard ska fungera hela tiden men kan inte lova oavbruten drift. Underhåll och fel hos leverantörer kan påverka tjänsten tillfälligt.",
      "Vi kan ändra priset eller villkoren. Är ändringen till din nackdel meddelar vi det med e-post minst 30 dagar innan den gäller för dig. Ett nytt pris gäller från din första förnyelse efter det. Priset för en period du redan har betalat ändras inte.",
      "Vill du inte fortsätta säger du upp prenumerationen innan ändringen gäller. Den upphör då vid periodens slut.",
    ],
  },
  {
    title: "10. Ansvar",
    paragraphs: [
      "Vårt ansvar är begränsat till det du har betalat för Tacticsboard de senaste 12 månaderna, utom vid uppsåt eller grov vårdslöshet. Begränsningen gäller inte rättigheter du har som konsument enligt lag.",
      "Är tjänsten felaktig har du som konsument rättigheter enligt lagen om avtal om tillhandahållande av digitalt innehåll och digitala tjänster, till exempel att vi rättar felet, att du får prisavdrag eller att du häver avtalet.",
      "Spara gärna kopior av viktiga projekt med exporten.",
    ],
  },
  {
    title: "11. Support",
    paragraphs: [
      "Frågor och problem mejlar du till support@teamzoneapp.se. Vi svarar inom två vardagar.",
    ],
  },
  {
    title: "12. Tvister",
    paragraphs: [
      "Svensk lag gäller för avtalet. Kontakta oss först om du är missnöjd. Kommer vi inte överens kan du som konsument vända dig till Allmänna reklamationsnämnden (ARN), arn.se. Tvister kan också prövas av allmän domstol.",
    ],
  },
] as const;

export default function TacticsboardTermsPage() {
  return (
    <LegalDocument
      eyebrow="Juridik"
      title="Villkor för Tacticsboard"
      version="2026-11-06"
      updated="6 november 2026"
      counterpart="/en/terms/tacticsboard"
      introduction="Här står vad som gäller när du provar och prenumererar på Tacticsboard: pris, betalning, uppsägning och ångerrätt."
      sections={sections}
    />
  );
}
