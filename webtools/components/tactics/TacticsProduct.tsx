// Tacticsboard's product page (plan item 10): what it does, the price and
// "Prova gratis". Rendered on the server so search engines read it; shown at
// /appar/tacticsboard and, for the signed-out, at /tacticsboard.
import Link from "next/link";
import { launchOfferOpen, prices } from "../../lib/tactics/access.ts";
import { serverT } from "../../lib/i18n/server.ts";
import { supportEmail, tacticsboardTermsUrl } from "../../lib/support.ts";
import { ProductVideo } from "./ProductVideo.tsx";
import "./product.css";

const signUp = "/logga-in?skapa=1&returnTo=%2Ftacticsboard";
const signIn = "/logga-in?returnTo=%2Ftacticsboard";

const points = [
  ["Rita", "Spelare, bollar, koner, mål, pilar och ytor på en riktig plan. Formationer på ett klick."],
  ["Animera", "Bygg förloppet steg för steg och spela upp det. Spelarna rör sig dit du drar dem."],
  ["Presentera", "Visa tavlan i helskärm, eller håll en livegenomgång där laget följer med i mobilen, svarar på frågor och chattar."],
  ["Dela", "Skicka en länk till spelare och föräldrar. De behöver inget konto för att titta."],
  ["Spara och ordna", "Projekt, mappar, mallar och versioner. Hämta och dela övningar i biblioteket."],
  ["Exportera", "Som PDF eller video, till träningsplanen eller gruppchatten."],
] as const;

// Screenshots in public/tacticsboard: file, size, and what they show.
const shots = [
  ["verktyg.png", 1291, 882, "Verktygen: spelare, boll, utrustning, pilar, ytor och mått."],
  ["editor.png", 1521, 1045, "Tavlorna i ett projekt, med beskrivning och tidslinje."],
  ["ytor.png", 1360, 846, "Markera ytor och de spelare laget ska titta på."],
] as const;

const questions = [
  ["Behöver jag vara med i TeamZone?", "Nej. Du skapar ett konto med din e-post och kan börja direkt."],
  ["Behöver jag ange kort för att prova?", "Nej. Provperioden är 7 dagar och kräver inget kort. Köper du under provperioden betalar du först när den är slut."],
  ["Vad händer när provperioden är slut?", "Tacticsboard låses tills du prenumererar. Inget tas bort, och länkar du har delat fortsätter att fungera för andra."],
  ["Hur säger jag upp?", "Från kontosidan, när du vill. Prenumerationen gäller perioden ut."],
  ["Kan jag ångra köpet?", "Ja, i 14 dagar från köpet med knappen Ångra köpet på kontosidan. Prenumerationen avslutas direkt, och du får tillbaka det du har betalat, med avdrag för en proportionell del för den betalda tiden."],
  ["Hur når jag supporten?", "Mejla {email}. Vi svarar inom två vardagar."],
] as const;

export async function TacticsProduct() {
  const t = await serverT();
  const offer = launchOfferOpen();
  return (
    <div className="tb-product">
      <section className="wt-hero tb-product-hero">
        <ProductVideo src="/tacticsboard/demo.mp4" poster="/tacticsboard/editor.png" end={7.5} />
        <div className="wt-wrap">
          <p className="tb-product-brand">Teamzone Webtools</p>
          <h1>Tacticsboard</h1>
          <p className="wt-lead">{t("Rita, animera och presentera taktik för träning, genomgångar och match.")}</p>
          <div className="wt-actions">
            <Link className="wt-button" href={signUp}>{t("Prova gratis i 7 dagar")}</Link>
            <Link className="wt-button secondary" href={signIn}>{t("Logga in")}</Link>
          </div>
          <p className="tb-product-small">{t("Inget kort behövs. Därefter {price}.", { price: t(prices.month.label) })}</p>
        </div>
      </section>

      <section className="wt-wrap wt-section">
        <div className="wt-points">
          {points.map(([title, text]) => (
            <article key={title}><h3>{t(title)}</h3><p>{t(text)}</p></article>
          ))}
        </div>
        <div className="tb-shots">
          {shots.map(([file, width, height, caption]) => (
            <figure key={file}>
              <img src={`/tacticsboard/${file}`} width={width} height={height} alt={t(caption)} loading="lazy" />
              <figcaption>{t(caption)}</figcaption>
            </figure>
          ))}
        </div>
      </section>

      <section className="wt-wrap wt-section" aria-labelledby="tb-price-title">
        <h2 id="tb-price-title">{t("Pris")}</h2>
        <div className="tb-prices">
          <article className="wt-panel">
            <h3>{t("Månad")}</h3>
            <p className="tb-price">{t("{amount} kr", { amount: prices.month.amount })}<span>{t("/mån")}</span></p>
            <p>{t("Säg upp när du vill.")}</p>
          </article>
          <article className="wt-panel">
            <h3>{t("År")}</h3>
            {offer ? (
              <>
                <p className="tb-price">{t("{amount} kr", { amount: t(prices.launch.amount) })}<span>{t(" första året")}</span></p>
                <p>{t("25 % rabatt vid köp senast 31 december 2026. Därefter {price}.", { price: t(prices.year.label) })}</p>
              </>
            ) : (
              <>
                <p className="tb-price">{t("{amount} kr", { amount: prices.year.amount })}<span>{t("/år")}</span></p>
                <p>{t("Två månader gratis jämfört med månadspriset.")}</p>
              </>
            )}
          </article>
        </div>
        <p className="wt-small">{t("Priserna är inklusive moms. Du betalar med kort, Apple Pay eller Google Pay hos Stripe. I 14 dagar från köpet kan du ångra det med knappen Ångra köpet på kontosidan. Läs")} <a href={tacticsboardTermsUrl}>{t("villkoren för Tacticsboard")}</a>.</p>
        <Link className="wt-button" href={signUp}>{t("Prova gratis i 7 dagar")}</Link>
      </section>

      <section className="wt-wrap wt-section" aria-labelledby="tb-faq-title">
        <h2 id="tb-faq-title">{t("Vanliga frågor")}</h2>
        <dl className="tb-faq">
          {questions.map(([question, answer]) => (
            <div key={question}><dt>{t(question)}</dt><dd>{t(answer, { email: supportEmail })}</dd></div>
          ))}
        </dl>
      </section>
    </div>
  );
}
