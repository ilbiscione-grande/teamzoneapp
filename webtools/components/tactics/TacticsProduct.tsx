// Tacticsboard's product page (plan item 10): what it does, the price and
// "Prova gratis". Rendered on the server so search engines read it; shown at
// /appar/tacticsboard and, for the signed-out, at /tacticsboard.
import Link from "next/link";
import { launchOfferOpen, prices } from "../../lib/tactics/access.ts";
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
  ["Behöver jag vara med i TeamZone?", "Nej. Du skapar ett konto med din e-post och kan börja direkt. Är du ledare i TeamZone kan du även använda truppen och koppla tavlan till ett träningspass."],
  ["Behöver jag ange kort för att prova?", "Nej. Provperioden är 7 dagar och kräver inget kort. Köper du under provperioden betalar du först när den är slut."],
  ["Vad händer när provperioden är slut?", "Tacticsboard låses tills du prenumererar. Inget tas bort, och länkar du har delat fortsätter att fungera för andra."],
  ["Hur säger jag upp?", "Från kontosidan, när du vill. Prenumerationen gäller perioden ut."],
] as const;

export function TacticsProduct() {
  const offer = launchOfferOpen();
  return (
    <div className="tb-product">
      <section className="wt-hero tb-product-hero">
        <ProductVideo src="/tacticsboard/demo.mp4" poster="/tacticsboard/editor.png" end={7.5} />
        <div className="wt-wrap">
          <p className="tb-product-brand">Teamzone Webtools</p>
          <h1>Tacticsboard</h1>
          <p className="wt-lead">Rita, animera och presentera taktik för träning, genomgångar och match.</p>
          <div className="wt-actions">
            <Link className="wt-button" href={signUp}>Prova gratis i 7 dagar</Link>
            <Link className="wt-button secondary" href={signIn}>Logga in</Link>
          </div>
          <p className="tb-product-small">Inget kort behövs. Därefter {prices.month.label}.</p>
        </div>
      </section>

      <section className="wt-wrap wt-section">
        <div className="wt-points">
          {points.map(([title, text]) => (
            <article key={title}><h3>{title}</h3><p>{text}</p></article>
          ))}
        </div>
        <div className="tb-shots">
          {shots.map(([file, width, height, caption]) => (
            <figure key={file}>
              <img src={`/tacticsboard/${file}`} width={width} height={height} alt={caption} loading="lazy" />
              <figcaption>{caption}</figcaption>
            </figure>
          ))}
        </div>
      </section>

      <section className="wt-wrap wt-section" aria-labelledby="tb-price-title">
        <h2 id="tb-price-title">Pris</h2>
        <div className="tb-prices">
          <article className="wt-panel">
            <h3>Månad</h3>
            <p className="tb-price">{prices.month.amount} kr<span>/mån</span></p>
            <p>Säg upp när du vill.</p>
          </article>
          <article className="wt-panel">
            <h3>År</h3>
            {offer ? (
              <>
                <p className="tb-price">{prices.year.amount / 2} kr<span> första året</span></p>
                <p>Halva priset vid köp senast 31 december 2026. Därefter {prices.year.label}.</p>
              </>
            ) : (
              <>
                <p className="tb-price">{prices.year.amount} kr<span>/år</span></p>
                <p>Två månader gratis jämfört med månadspriset.</p>
              </>
            )}
          </article>
        </div>
        <p className="wt-small">Priserna är inklusive moms. Du betalar med kort, Apple Pay eller Google Pay hos Stripe.</p>
        <Link className="wt-button" href={signUp}>Prova gratis i 7 dagar</Link>
      </section>

      <section className="wt-wrap wt-section" aria-labelledby="tb-faq-title">
        <h2 id="tb-faq-title">Vanliga frågor</h2>
        <dl className="tb-faq">
          {questions.map(([question, answer]) => (
            <div key={question}><dt>{question}</dt><dd>{answer}</dd></div>
          ))}
        </dl>
      </section>
    </div>
  );
}
