/**
 * The logout sequence (ADR-0001 seam 2), extracted from doc.js's dispatch
 * table into src/shared/session.js so it can be exercised without a browser
 * session, a server, or Dexie.
 *
 * Elm sends the `LogoutUser` port message; this is everything that happens
 * next. Observed through the boundaries it actually crosses: the HTTP call
 * (faked), the real localStorage, and the two callbacks doc.js supplies for
 * the things only it owns (tearing down the socket, telling Elm).
 */
import { afterEach, beforeEach, expect, test } from "bun:test";

import { logoutUser } from "../src/shared/session";

/** The session blob's key, per docs/ARCHITECTURE.md §6.2. */
const SESSION_KEY = "gingko-session-storage";

interface FetchCall {
  url: string;
  method: string | undefined;
}

let calls: FetchCall[] = [];
/** What the faked server does next. Only `ok`/`status` are ever read. */
let respond: () => Promise<{ ok: boolean; status: number }> = async () => ({
  ok: true,
  status: 200,
});

const realFetch = globalThis.fetch;

beforeEach(() => {
  calls = [];
  respond = async () => ({ ok: true, status: 200 });
  localStorage.clear();
  localStorage.setItem(SESSION_KEY, JSON.stringify({ email: "user@example.com" }));
  globalThis.fetch = ((input: unknown, init?: { method?: string }) => {
    calls.push({ url: String(input), method: init?.method });
    return respond();
  }) as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
  localStorage.clear();
});

test("ends the server session with POST /logout", async () => {
  await logoutUser({});

  expect(calls).toEqual([{ url: "/logout", method: "POST" }]);
});

test("clears the stored session blob", async () => {
  await logoutUser({});

  expect(localStorage.getItem(SESSION_KEY)).toBeNull();
});

test("tells Elm the user is logged out, once, after the blob is gone", async () => {
  const blobWhenTold: Array<string | null> = [];

  await logoutUser({ onLoggedOut: () => blobWhenTold.push(localStorage.getItem(SESSION_KEY)) });

  expect(blobWhenTold).toEqual([null]);
});

test("stops syncing as the departing user before telling Elm", async () => {
  const order: string[] = [];

  await logoutUser({
    teardown: () => order.push("teardown"),
    onLoggedOut: () => order.push("told Elm"),
  });

  expect(order).toEqual(["teardown", "told Elm"]);
});

// A self-host must never be stuck logged in because its server is down,
// unreachable, or older than POST /logout. Every step below fails and the
// user still ends up logged out locally.

test("logs out locally when the server rejects the call", async () => {
  respond = async () => ({ ok: false, status: 404 });
  const told: string[] = [];

  await logoutUser({ onLoggedOut: () => told.push("told Elm") });

  expect([localStorage.getItem(SESSION_KEY), ...told]).toEqual([null, "told Elm"]);
});

test("logs out locally when the server cannot be reached", async () => {
  respond = () => Promise.reject(new TypeError("Failed to fetch"));
  const told: string[] = [];

  await logoutUser({ onLoggedOut: () => told.push("told Elm") });

  expect([localStorage.getItem(SESSION_KEY), ...told]).toEqual([null, "told Elm"]);
});

test("logs out even if tearing down the socket throws", async () => {
  const told: string[] = [];

  await logoutUser({
    teardown: () => {
      throw new Error("socket already gone");
    },
    onLoggedOut: () => told.push("told Elm"),
  });

  expect(told).toEqual(["told Elm"]);
});

// The local document cache is deliberately kept (ticket 04): unsynced card
// rows are the only copy of offline work, so logout must not be a delete. The
// per-document settings under gingko-local-store/<treeId>/ are the same call.

test("keeps local document data, clearing only the session blob", async () => {
  localStorage.setItem("gingko-local-store/tree-1/settings", '{"theme":"dark"}');

  await logoutUser({});

  expect(localStorage.getItem("gingko-local-store/tree-1/settings")).toBe('{"theme":"dark"}');
});

test("keeps the record of which account owns the legacy database", async () => {
  // Ticket 27's claim (gingko-local-db-owner, §6.2): the one account that has
  // adopted the pre-per-account database `"db"`. Logout is exactly where it
  // must not go. An unclaimed `"db"` is adoptable, so a logout that took the
  // claim with the session blob would hand the departing account's documents
  // to whoever logged in next — the leak ticket 27 exists to close, restored
  // by a plausible tidy-up ("clear the gingko-* keys we wrote").
  localStorage.setItem("gingko-local-db-owner", "e99ead1f7cfdea04");

  await logoutUser({});

  expect(localStorage.getItem("gingko-local-db-owner")).toBe("e99ead1f7cfdea04");
});
