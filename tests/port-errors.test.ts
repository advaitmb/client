/**
 * What a failed *port* message is worth telling the user (ADR-0001 seam 12) —
 * CODE_REVIEW.md S7.
 *
 * `doc.js` dispatches every message from Elm through one table wrapped in one
 * `try { cases[msg]() } catch`, which reported everything — a handler that
 * threw included — as "Unexpected message from Elm", and, since most handlers
 * are `async`, never saw their rejections at all. Every Dexie write in the
 * table is one of those: a save, a delete, a rename, an import failing had
 * exactly the same visible outcome as a successful one.
 *
 * So the policy is per tag, in the same shape and for the same reasons as
 * `ws-errors.js`'s: an allowlist of the benign tags, everything else reported
 * to the user. Being wrong about a benign tag costs a dialog; being wrong about
 * a persisting one costs the user's work — and a tag added to the table later
 * is loud until someone has decided which side it is on.
 */
import { expect, test } from "bun:test";

import { isExtensionInterference, portMessageFailure } from "../src/shared/port-errors";

/* ===== which failures reach the user ===== */

test("a failed database write reaches the user", () => {
  for (const tag of [
    "SaveCardBased",
    "SaveCardBasedMigration",
    "InitDocument",
    "LoadDocument",
    "RequestDelete",
    "RenameDocument",
    "StoreUser",
  ]) {
    const failure = portMessageFailure(tag, new Error("QuotaExceededError"));
    expect(failure.userMessage).not.toBeNull();
  }
});

test("a failure that only means the DOM did not move stays in the console", () => {
  for (const tag of [
    "ScrollCards",
    "SetField",
    "SelectAll",
    "SetCursorPosition",
    "TextSurround",
    "SendCollabState",
    "HistorySlider",
    "ConsoleLogRequested",
  ]) {
    const failure = portMessageFailure(tag, new Error("no such element"));
    expect(failure.userMessage).toBeNull();
  }
});

test("a tag nobody has classified is reported, not silently benign", () => {
  // The direction of the list, and the whole of why it is a list of the benign
  // ones: a case added to the dispatch table later cannot be swallowed by
  // default.
  expect(portMessageFailure("SomeNewPortMessage", new Error("boom")).userMessage)
    .not.toBeNull();
});

/* ===== what the console gets ===== */

test("the console line names the tag that failed", () => {
  expect(portMessageFailure("SaveCardBased", new Error("boom")).consoleMessage)
    .toContain("SaveCardBased");
});

test("the report never reads the thrown value", () => {
  // A rejected Dexie promise can carry anything, and the report must not be
  // the second thing that throws.
  for (const thrown of [undefined, null, "a string", 42, { no: "message" }]) {
    expect(() => portMessageFailure("SaveCardBased", thrown)).not.toThrow();
  }
  expect(portMessageFailure("ScrollCards", undefined).userMessage).toBeNull();
});

test("one text per failure, whatever the tag", () => {
  // Identical text is what keeps a tag that fails on every message to one
  // dialog rather than a stack of them, the same reason ws-errors.js gives.
  const a = portMessageFailure("SaveCardBased", new Error("one"));
  const b = portMessageFailure("RenameDocument", new Error("two"));

  expect(a.userMessage).toBe(b.userMessage);
  expect(a.userMessage).not.toContain("SaveCardBased");
});

/* ===== the browser-extension net ===== */

test("the two known extension-clobbering errors are recognized", () => {
  expect(isExtensionInterference("Cannot read properties of undefined (reading 'childNodes')"))
    .toBe(true);
  expect(isExtensionInterference("Failed to execute 'removeChild' on 'Node': oops"))
    .toBe(true);
});

test("an ordinary error is not blamed on an extension", () => {
  expect(isExtensionInterference("TypeError: x is not a function")).toBe(false);
});

test("an error event with no message is not an extension either", () => {
  // `window`'s error handler also fires for failed resource loads, whose event
  // carries no `message` at all -- reading `.match` off it threw inside the
  // error handler itself.
  for (const message of [undefined, null, 42, {}]) {
    expect(isExtensionInterference(message as unknown as string)).toBe(false);
  }
});
