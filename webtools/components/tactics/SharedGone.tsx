// A shared link that shows nothing: taken back by its owner, or one opened
// from TeamZone, which is good for some hours only.
export function SharedGone() {
  return (
    <div className="wt-wrap wt-section wt-narrow">
      <h1 className="wt-page-title">Länken gäller inte längre</h1>
      <p>Har du öppnat tavlan från TeamZone-appen gäller länken bara några timmar. Öppna den igen från appen.</p>
      <p>Har du fått länken av någon kan den ha tagits bort. Be om en ny.</p>
    </div>
  );
}
