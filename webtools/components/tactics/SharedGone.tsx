// A shared link that shows nothing: taken back by its owner, or one opened
// from TeamZone, which is good for some hours only.
import { serverT } from "../../lib/i18n/server.ts";

export async function SharedGone() {
  const t = await serverT();
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <h1 className="wt-page-title">{t("Länken gäller inte längre")}</h1>
      <p>{t("Har du öppnat tavlan från TeamZone-appen gäller länken bara några timmar. Öppna den igen från appen.")}</p>
      <p>{t("Har du fått länken av någon kan den ha tagits bort. Be om en ny.")}</p>
    </div>
  );
}
