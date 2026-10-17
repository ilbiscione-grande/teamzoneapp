"use client";

import { useEffect, useRef, useState } from "react";
import type { LayerGroup, Map as LeafletMap } from "leaflet";
import { groupByPlace, type Listing, type Place } from "../lib/match-pool";

// POOL-04: the listings on a map (Leaflet with OpenStreetMap's tiles).
// Positions are the rounded places listings were saved with, never the
// pitch. Listings at the same place share one marker with a count; a
// marker is green when every club at it is verified, amber otherwise.
// Choosing a marker shows those listings as cards below the map.

export function ListingsMap({ listings, origin, radiusKm, selected, onSelect }: {
  listings: Listing[]; origin: Place | null; radiusKm: number | null; selected: string | null; onSelect: (key: string | null) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<LeafletMap | null>(null);
  const layer = useRef<LayerGroup | null>(null);
  const leaflet = useRef<typeof import("leaflet") | null>(null);
  const fitted = useRef("");
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let disposed = false;
    import("leaflet").then(L => {
      if (disposed || !box.current) return;
      leaflet.current = L;
      const created = L.map(box.current, { scrollWheelZoom: false, zoomControl: true }).setView([62.5, 16], 5);
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 18,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>',
      }).addTo(created);
      layer.current = L.layerGroup().addTo(created);
      map.current = created;
      setReady(true);
    }).catch(() => { if (!disposed) setFailed(true); });
    return () => { disposed = true; map.current?.remove(); map.current = null; layer.current = null; };
  }, []);

  useEffect(() => {
    const L = leaflet.current, target = map.current, group = layer.current;
    if (!ready || !L || !target || !group) return;
    group.clearLayers();
    const points: [number, number][] = [];
    if (origin) {
      points.push([origin.latitude, origin.longitude]);
      if (radiusKm) {
        L.circle([origin.latitude, origin.longitude], { radius: radiusKm * 1000, color: "#1f8a4c", weight: 1, fillOpacity: 0.04, interactive: false }).addTo(group);
      }
      L.marker([origin.latitude, origin.longitude], {
        icon: L.divIcon({ className: "mp-pin origin", html: "", iconSize: [18, 18] }),
        title: `Er utgångsort: ${origin.place_label}`, keyboard: false, interactive: false,
      }).addTo(group);
    }
    for (const place of groupByPlace(listings)) {
      points.push([place.latitude, place.longitude]);
      const verified = place.listings.every(listing => listing.verified);
      const count = place.listings.length;
      const marker = L.marker([place.latitude, place.longitude], {
        icon: L.divIcon({
          className: `mp-pin ${verified ? "verified" : "unverified"}${selected === place.key ? " selected" : ""}`,
          // Only a number: nothing from a listing goes into the marker's markup.
          html: count > 1 ? String(count) : "",
          iconSize: [30, 30],
        }),
        title: `${count === 1 ? "1 annons" : `${count} annonser`} i ${place.listings[0].place_label}`,
        keyboard: true,
      });
      marker.on("click", () => onSelect(place.key));
      marker.addTo(group);
    }
    // Fit the view when the set of places changes, not when one is chosen.
    const signature = points.map(point => point.join(",")).sort().join(";");
    if (signature !== fitted.current) {
      fitted.current = signature;
      if (points.length === 1) target.setView(points[0], 10);
      else if (points.length > 1) target.fitBounds(L.latLngBounds(points), { padding: [30, 30], maxZoom: 11 });
    }
  }, [ready, listings, origin, radiusKm, selected, onSelect]);

  if (failed) return <div className="cs-empty">Kartan kunde inte laddas. Använd listan i stället.</div>;
  return <div className="mp-map" ref={box} role="region" aria-label="Karta med annonser" />;
}
