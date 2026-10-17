import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  defaultFilters, filterListings, listingPayload, placeFromNominatim, poolError, stockholmInstant, watchLabel, whenLabel,
  type Listing, type ListingDraft,
} from "../lib/match-pool.ts";

const now = new Date("2026-10-17T08:00:00Z");
const place = { place_label: "Alby, Botkyrka", latitude: 59.24, longitude: 17.85 };
const draft: ListingDraft = {
  kind: "home_slot", date: "2026-11-14", startTime: "10:00", endTime: "11:30", dateFrom: "", dateTo: "", maxDistance: "50",
  place, venueName: "Alby IP", surface: "artificial", format: "7v7", ageClass: "P12", gender: "boys", level: "", note: "",
};

test("Stockholm local time becomes the right instant in winter and summer", () => {
  assert.equal(stockholmInstant("2026-11-14", "10:00")?.toISOString(), "2026-11-14T09:00:00.000Z");
  assert.equal(stockholmInstant("2026-06-14", "10:00")?.toISOString(), "2026-06-14T08:00:00.000Z");
  assert.equal(stockholmInstant("14/11", "10:00"), null);
});

test("a home slot needs a time in the future, a sane length and a venue", () => {
  const { payload } = listingPayload(draft, now);
  assert.equal(payload?.starts_at, "2026-11-14T09:00:00.000Z");
  assert.equal(payload?.ends_at, "2026-11-14T10:30:00.000Z");
  assert.equal(payload?.venue_name, "Alby IP");
  assert.equal(payload?.level, null);
  assert.match(listingPayload({ ...draft, date: "2026-10-01" }, now).problem ?? "", /passerat/);
  assert.match(listingPayload({ ...draft, endTime: "10:15" }, now).problem ?? "", /30 minuter/);
  assert.match(listingPayload({ ...draft, venueName: " " }, now).problem ?? "", /plan/);
  assert.match(listingPayload({ ...draft, place: null }, now).problem ?? "", /ort/);
});

test("an away search needs a date range of at most 60 days and a distance", () => {
  const away: ListingDraft = { ...draft, kind: "away_wanted", dateFrom: "2026-10-20", dateTo: "2026-11-10", maxDistance: "75" };
  const { payload } = listingPayload(away, now);
  assert.deepEqual([payload?.date_from, payload?.date_to, payload?.max_distance_km], ["2026-10-20", "2026-11-10", 75]);
  assert.equal(payload?.venue_name, undefined);
  assert.match(listingPayload({ ...away, dateTo: "2027-01-30" }, now).problem ?? "", /60 dagar/);
  assert.match(listingPayload({ ...away, dateTo: "2026-10-19" }, now).problem ?? "", /före/);
  assert.match(listingPayload({ ...away, maxDistance: "2" }, now).problem ?? "", /km/);
});

test("filters: kind, format, gender, verified only and free text", () => {
  const base = { id: "a", kind: "home_slot", state: "open", team_id: "t", team_name: "P2012", club_name: "Alby IF", verified: true,
    starts_at: null, ends_at: null, date_from: null, date_to: null, max_distance_km: null, place_label: "Botkyrka", distance_km: 5,
    venue_name: null, venue_surface: null, match_format: "7v7", age_class: "P12", gender: "boys", level: null, note: null, created_at: "" } as Listing;
  const other = { ...base, id: "b", kind: "away_wanted", verified: false, match_format: "9v9", gender: "girls", age_class: "F13", club_name: "Bro BK", place_label: "Bro" } as Listing;
  const all = [base, other];
  assert.deepEqual(filterListings(all, defaultFilters).map(l => l.id), ["a", "b"]);
  assert.deepEqual(filterListings(all, { ...defaultFilters, verifiedOnly: true }).map(l => l.id), ["a"]);
  assert.deepEqual(filterListings(all, { ...defaultFilters, kind: "away_wanted" }).map(l => l.id), ["b"]);
  assert.deepEqual(filterListings(all, { ...defaultFilters, format: "7v7", gender: "boys" }).map(l => l.id), ["a"]);
  assert.deepEqual(filterListings(all, { ...defaultFilters, text: "bro" }).map(l => l.id), ["b"]);
});

test("labels: a slot with its time, a range with its days", () => {
  assert.match(whenLabel({ kind: "home_slot", starts_at: "2026-11-14T09:00:00Z", ends_at: "2026-11-14T10:30:00Z", date_from: null, date_to: null }), /14 nov\.? kl 10:00–11:30/);
  assert.match(whenLabel({ kind: "away_wanted", starts_at: null, ends_at: null, date_from: "2026-11-01", date_to: "2026-11-15" }), /1 nov.* – .*15 nov/);
});

test("Nominatim places are short, Swedish and rounded to about a km", () => {
  const picked = placeFromNominatim({ lat: "59.238912", lon: "17.845123", name: "Alby IP",
    address: { suburb: "Alby", municipality: "Botkyrka kommun", county: "Stockholms län" } });
  assert.deepEqual(picked, { place_label: "Alby IP, Alby, Botkyrka", latitude: 59.24, longitude: 17.85 });
  assert.equal(placeFromNominatim({ lat: "x", lon: "17" }), null);
});

test("database codes become Swedish messages", () => {
  assert.match(poolError({ message: "not_leader" }), /ledare/);
  assert.match(poolError({ message: "already_interested" }), /redan/);
  assert.match(poolError(new Error("boom")), /Något gick fel/);
});

test("the page shows verification on every card and only searches places when signed in", () => {
  const page = readFileSync(new URL("../components/match-pool.tsx", import.meta.url), "utf8");
  assert.match(page, /Officiellt verifierad klubb/);
  assert.match(page, /Ej verifierad klubb/);
  assert.match(page, /Bara verifierade klubbar/);
  const route = readFileSync(new URL("../app/api/public/v1/places/route.ts", import.meta.url), "utf8");
  assert.match(route, /auth\.getUser\(token\)/);
  assert.match(route, /countrycodes: "se"/);
  assert.match(route, /lastCall \+ 1100/);
});

test("sign-in from the app: the code is used once by the server and leaves the address at once", () => {
  const route = readFileSync(new URL("../app/api/public/v1/account/handoff/route.ts", import.meta.url), "utf8");
  assert.match(route, /assertSameOrigin/);
  assert.match(route, /rpc\("consume_web_handoff"/);
  assert.match(route, /verified\.user\?\.id !== owner/);
  assert.match(route, /json\(\{ refresh_token: verified\.session\.refresh_token \}\)/);
  assert.doesNotMatch(route, /access_token/);
  const account = readFileSync(new URL("../components/personal-account.tsx", import.meta.url), "utf8");
  const strip = account.indexOf("window.history.replaceState(null");
  const exchange = account.indexOf("/api/public/v1/account/handoff");
  assert.ok(strip > 0 && strip < exchange, "the code is removed from the address before it is used");
});

test("watches are described in words, and cancellation needs the other team", () => {
  assert.equal(watchLabel({ kind: "away_wanted", max_distance_km: 50, match_format: "7v7", gender: "boys", age_class: "P12", verified_only: true }),
    "Söker bortamatch · inom 50 km · P12 · 7 mot 7 · Pojkar · bara verifierade klubbar");
  assert.equal(watchLabel({ kind: "all", max_distance_km: 25, match_format: null, gender: null, age_class: null, verified_only: false }), "Alla annonser · inom 25 km");
  const page = readFileSync(new URL("../components/match-pool.tsx", import.meta.url), "utf8");
  assert.match(page, /Begär avbokning/);
  assert.match(page, /Godkänn avbokning/);
  assert.match(page, /cancel_requested_side !== side/);
  assert.match(page, /Lägg ut annonsen igen/);
  assert.match(page, /get\("annons"\)/);
});
