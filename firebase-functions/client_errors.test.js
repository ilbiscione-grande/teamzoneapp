const test = require("node:test");
const assert = require("node:assert/strict");
const {allowedOrigin, sanitizedClientError, withinLimit, LIMIT_PER_MINUTE} = require("./client_errors");

const valid = {
  operation: "calendar_surface._createEvent",
  error_type: "PostgrestException",
  fatal: false,
  environment: "audit",
  release: "0.1.0_1",
};

test("keeps only the allowlisted identifiers", () => {
  const record = sanitizedClientError(JSON.stringify({
    ...valid, message: "must-not-pass", email: "x@example.com", trace: "at main",
  }));
  assert.deepEqual(record, {event: "teamzone.client.error", platform: "web", ...valid});
});

test("rejects free text, wrong types, oversized and broken bodies", () => {
  assert.equal(sanitizedClientError(JSON.stringify({...valid, operation: "bad value with spaces"})), null);
  assert.equal(sanitizedClientError(JSON.stringify({...valid, error_type: "x@example.com"})), null);
  assert.equal(sanitizedClientError(JSON.stringify({...valid, fatal: "yes"})), null);
  assert.equal(sanitizedClientError(JSON.stringify({...valid, release: "r".repeat(81)})), null);
  assert.equal(sanitizedClientError("{" + " ".repeat(2000) + "}"), null);
  assert.equal(sanitizedClientError("not json"), null);
  assert.equal(sanitizedClientError(JSON.stringify([valid])), null);
});

test("only the app's origins, plus configured extra origins", () => {
  assert.equal(allowedOrigin("https://app.teamzoneapp.se", ""), true);
  assert.equal(allowedOrigin("https://test.teamzoneapp.se", ""), true);
  assert.equal(allowedOrigin("https://evil.example", ""), false);
  assert.equal(allowedOrigin(undefined, ""), false);
  assert.equal(allowedOrigin("http://localhost:5000", "http://localhost, http://localhost:5000"), true);
  assert.equal(allowedOrigin("http://localhost:5000", ""), false);
});

test("limits records per address and minute", () => {
  const now = Date.UTC(2026, 9, 13, 12, 0, 0);
  for (let i = 0; i < LIMIT_PER_MINUTE; i++) assert.equal(withinLimit("203.0.113.1", now), true);
  assert.equal(withinLimit("203.0.113.1", now), false);
  assert.equal(withinLimit("203.0.113.2", now), true, "other addresses are unaffected");
  assert.equal(withinLimit("203.0.113.1", now + 60000), true, "the next minute is open again");
});

test("a fatal report may carry code-location frames only", () => {
  const stack = [
    "#0 _EventParticipantsState._correctCallup (package:teamzone_app/src/features/calendar/event_participants.dart:641:7)",
    "#1 _State.build.<anonymous closure> (package:teamzone_app/m.dart:9:1)",
    "#2 new EventDetails.fromJson (package:teamzone_app/m.dart:8:3)",
    "#3 Object.c (main.dart.js:9876:54)",
  ];
  assert.deepEqual(sanitizedClientError(JSON.stringify({...valid, fatal: true, stack})).stack, stack);
});

test("rejects stacks with data, wrong order, too many frames or on handled errors", () => {
  const frame = (i, member = "f", location = "package:teamzone_app/a.dart") => `#${i} ${member} (${location}:${i + 1}:1)`;
  const bad = (stack, fatal = true) => sanitizedClientError(JSON.stringify({...valid, fatal, stack}));
  assert.equal(bad([frame(0, "Anna Andersson")]), null, "two words are not a function name");
  assert.equal(bad([frame(0, "f", "anna@example.se")]), null);
  assert.equal(bad([frame(0, "f", "C:/Users/anna/x.dart")]), null, "paths must already be cut");
  assert.equal(bad(["Exception: Ogiltig e-post anna@example.se"]), null);
  assert.equal(bad([frame(1)]), null, "frames are numbered from 0");
  assert.equal(bad(Array.from({length: 31}, (_, i) => frame(i))), null);
  assert.equal(bad([frame(0)], false), null, "handled errors carry no stack");
  assert.equal(bad([]), null);
  assert.equal(bad("#0 f (package:teamzone_app/a.dart:1:1)"), null, "a stack is a list of frames");
});
