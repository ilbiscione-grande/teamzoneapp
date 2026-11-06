// The product page's film, behind the hero's text: muted and looping. On a
// phone the text's dark background all but hides it, so the poster is enough.
export function ProductVideo({ src, poster }: { src: string; poster: string }) {
  return <video className="tb-product-video" poster={poster} autoPlay muted loop playsInline preload="metadata" aria-hidden="true" tabIndex={-1}><source src={src} media="(min-width: 701px)" /></video>;
}
