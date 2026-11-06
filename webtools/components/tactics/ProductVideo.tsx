// The product page's film, behind the hero's text: muted and looping.
export function ProductVideo({ src, poster }: { src: string; poster: string }) {
  return <video className="tb-product-video" src={src} poster={poster} autoPlay muted loop playsInline preload="metadata" aria-hidden="true" tabIndex={-1} />;
}
