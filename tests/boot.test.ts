/**
 * What boot reads out of localStorage (ADR-0001 seam 4) — CODE_REVIEW.md S8.
 *
 * Two stored blobs stand between a cold start and a usable app, and neither
 * could survive being garbage. The session blob is boot's *first* step
 * (`getFlags` → Elm's flags), and it was `JSON.parse`d with no guard, so one
 * corrupted value meant a blank page and no way back except clearing site data
 * by hand. The per-document store was read the same way by `localStore.load`,
 * which Elm receives whole alongside a document's cards, so a corrupted one
 * cost the theme and the focused card as well as throwing.
 *
 * Observed through the boundary they actually cross: the real localStorage.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";

import { readSessionData, writeSessionData } from "../src/shared/session";
import { localStore } from "../src/web/container-web";

/** The session blob's key, per docs/ARCHITECTURE.md §6.2. */
const SESSION_KEY = "gingko-session-storage";

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  localStorage.clear();
});

/* ===== the session blob ===== */

test("a stored session is read back", () => {
  localStorage.setItem(SESSION_KEY, JSON.stringify({ email: "user@example.com" }));

  expect(readSessionData()).toEqual({ email: "user@example.com" });
});

test("nothing stored is a guest, not an error", () => {
  expect(readSessionData()).toBeNull();
});

test("a corrupted session boots as a guest", () => {
  localStorage.setItem(SESSION_KEY, "{not json at all");

  expect(readSessionData()).toBeNull();
});

test("a corrupted session is cleared, so the next boot is clean", () => {
  localStorage.setItem(SESSION_KEY, "{not json at all");

  readSessionData();

  expect(localStorage.getItem(SESSION_KEY)).toBeNull();
});

test("valid JSON that is not a session blob boots as a guest", () => {
  // `getFlags` sets fields on whatever this returns and hands it to Elm as its
  // flags. A number or a string takes the assignments silently and then fails
  // Elm's decoder, which is the same blank page by a longer route.
  for (const stored of ["42", '"hello"', "null", "[1,2,3]"]) {
    localStorage.setItem(SESSION_KEY, stored);
    expect(readSessionData()).toBeNull();
  }
});

test("a corrupted session is replaced by the next write", () => {
  localStorage.setItem(SESSION_KEY, "{not json at all");

  writeSessionData({ email: "user@example.com" }, "test");

  expect(readSessionData()).toEqual({ email: "user@example.com" });
});

test("a storage that refuses the write does not fail the message that asked", () => {
  // Private modes and blocked site data. What it costs is this session's
  // preferences on the next reload; everything that matters is in Dexie.
  const setItem = Storage.prototype.setItem;
  Storage.prototype.setItem = () => {
    throw new Error("QuotaExceededError");
  };

  try {
    expect(() => writeSessionData({ email: "user@example.com" }, "test")).not.toThrow();
  } finally {
    Storage.prototype.setItem = setItem;
  }
});

/* ===== the per-document store ===== */

test("a per-document store read before anything is written is empty, not null", () => {
  expect(localStore.isReady()).toBe(false);

  localStore.db("tree-abc");

  // Elm gets this blob as `loadedCards.localStore` and decodes optional fields
  // out of it, so an empty object is a document with no settings yet; `null`
  // was a throw on the way there.
  expect(localStore.load()).toEqual({});
});

test("a per-document setting survives a corrupted store", () => {
  localStore.db("tree-abc");
  localStorage.setItem("gingko-local-store/tree-abc/settings", "}{");

  expect(localStore.load()).toEqual({});

  localStore.set("theme", "dark");

  expect(localStore.load()).toEqual({ theme: "dark" });
});

test("per-document settings round-trip", () => {
  localStore.db("tree-xyz");
  localStore.set("last-actives", ["a", "b"]);
  localStore.set("theme", "gray");

  expect(localStore.load()).toEqual({ "last-actives": ["a", "b"], theme: "gray" });
});
