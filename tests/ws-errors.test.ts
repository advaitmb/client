/**
 * What a failed websocket message handler owes the user (CODE_REVIEW.md E16),
 * extracted from doc.js's `ws.onmessage` into src/shared/ws-errors.js.
 *
 * The whole `switch` used to sit in one `try { … } catch (e) { console.log(e) }`,
 * which flattened every outcome to the same console line. The case that matters
 * is `cards`: a failed `bulkPut` there is incoming sync data that never reached
 * this device, and the user is left editing a document that is quietly behind
 * the server. At the other extreme, `rt` arrives every time a collaborator
 * moves, and a failure loses where a cursor is.
 *
 * So the policy is per message type, and this is where it is pinned down. It is
 * an allowlist of the benign types rather than a list of the serious ones: a
 * case added to the switch later is loud until someone has thought about it.
 */
import { expect, test } from "bun:test";

import { wsMessageFailure } from "../src/shared/ws-errors";

/** Every message type whose failure means data did not reach this device. */
const LOSES_DATA = [
  "cards",
  "cardsConflict",
  "trees",
  "treesOk",
  "history",
  "historyMeta",
  "doPull",
  "removedFrom",
];

/** Every message type whose failure the user can do nothing with. */
const BENIGN = ["user", "rt", "rt:users", "pushOk", "pushError"];

test("a failed bulkPut of pulled cards is reported to the user", () => {
  // The E16 case: the server sent cards this client did not have, and writing
  // them to Dexie threw. Nothing else will bring them back on its own.
  const failure = wsMessageFailure("cards", new Error("QuotaExceededError"));

  expect(failure.userMessage).toBeString();
  expect(failure.userMessage).not.toBe("");
});

test.each(LOSES_DATA)("a failed '%s' handler is reported to the user", (messageType) => {
  expect(wsMessageFailure(messageType, new Error("boom")).userMessage).toBeString();
});

test.each(BENIGN)("a failed '%s' handler stays in the console", (messageType) => {
  expect(wsMessageFailure(messageType, new Error("boom")).userMessage).toBeNull();
});

test("an unrecognized message type is reported rather than assumed benign", () => {
  // Default-deny: whoever adds a case to the switch has to come here and say
  // which side it is on, instead of the new case being silent by default.
  expect(wsMessageFailure("somethingNew", new Error("boom")).userMessage).toBeString();
});

test("a frame that could not be parsed at all is reported", () => {
  // No type to judge by, so no way to know what was in it. Parsing used to
  // happen outside the try entirely, making this an unhandled rejection.
  expect(wsMessageFailure(null, new SyntaxError("Unexpected token")).userMessage).toBeString();
});

test("the console line names the message type, for every type", () => {
  expect(wsMessageFailure("cards", new Error("boom")).consoleMessage).toContain("cards");
  expect(wsMessageFailure("rt", new Error("boom")).consoleMessage).toContain("rt");
});

test("the user-facing message says nothing about message types", () => {
  // `data.t` is protocol jargon; it belongs in the console line above, which is
  // logged for both kinds of failure.
  const failure = wsMessageFailure("cardsConflict", new Error("boom"));

  expect(failure.userMessage).not.toContain("cardsConflict");
});

test("the same failure always produces the same message", () => {
  // The Elm side adds these with `Toast.addUnique`, so identical text is what
  // keeps a message type that fails on every frame to one toast instead of a
  // stack of them.
  const first = wsMessageFailure("cards", new Error("one"));
  const second = wsMessageFailure("cards", new Error("two"));

  expect(first.userMessage).toBe(second.userMessage);
});

test("a thrown non-Error does not defeat the report", () => {
  // A rejected Dexie promise can carry anything at all.
  expect(wsMessageFailure("cards", undefined).userMessage).toBeString();
  expect(wsMessageFailure("cards", "just a string").consoleMessage).toContain("cards");
});
