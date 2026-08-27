/**
 * Which local database an account's documents live in (ADR-0001 seam 4) —
 * ticket 27.
 *
 * The Dexie database used to be one global `"db"`, so once ticket 04 made
 * logging out possible, the next account to log in on the same browser opened
 * the departing account's document cache and read it as its own. The name is
 * derived from the logged-in email instead, and the one database that already
 * exists on every upgraded install is *adopted* by the first account that logs
 * in — recorded as a claim, so no second account can adopt it too.
 *
 * Observed through the boundaries the decision actually crosses: the claim
 * store (faked in memory below, then the real localStorage), and the name it
 * answers with. Never through IndexedDB — nothing here opens a database, which
 * is the point of putting the decision in its own module.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";

import {
  dbNameForEmail,
  readDbClaim,
  resolveUserDbName,
  writeDbClaim,
} from "../src/shared/local-db";

/**
 * Where the adoption of the legacy database is recorded, in memory.
 *
 * `read` answers the hash of the account that owns `"db"`, or null if no one
 * does; `write` records one and reports whether it landed. The real store is
 * localStorage (exercised at the bottom of this file), which can refuse a write
 * outright and can refuse to be read at all — both are what `denyWrites` and
 * `refuseReads` model.
 */
function fakeClaimStore(
  initial: string | null = null,
  options: { denyWrites?: boolean; refuseReads?: boolean } = {},
) {
  let claim = initial;
  return {
    read: () => {
      if (options.refuseReads) throw new Error("SecurityError: storage is not available");
      return claim;
    },
    write: (hash: string) => {
      if (options.denyWrites) return false;
      claim = hash;
      return true;
    },
    /** What the store is left holding — the equivalent of asserting on rows. */
    stored: () => claim,
  };
}

/**
 * The name every install before ticket 27 used. Spelled out rather than
 * imported: it is a contract with databases already on disk, and a test that
 * read the constant could not tell a rename from a working upgrade.
 */
const LEGACY = "db";

/* ===== the name derived from an email ===== */

test("the database name does not contain the address it is derived from", () => {
  // IndexedDB names are readable by anything with the origin's devtools and by
  // `indexedDB.databases()`, so the address is hashed rather than spelled.
  const name = dbNameForEmail("someone@example.com");

  expect(name).not.toContain("someone");
  expect(name).not.toContain("example.com");
  expect(name).not.toContain("@");
});

test("a database name is a hashed name, not an arbitrary string", () => {
  expect(dbNameForEmail("someone@example.com")).toMatch(/^db-[0-9a-f]{16}$/);
});

test("the same account always names the same database", () => {
  // The whole feature rests on this: a name that changed between boots would
  // lose the account's unsynced offline work every time.
  expect(dbNameForEmail("someone@example.com")).toBe(dbNameForEmail("someone@example.com"));
});

test("two accounts name two databases", () => {
  expect(dbNameForEmail("a@example.com")).not.toBe(dbNameForEmail("b@example.com"));
});

test("the same address written differently is the same account", () => {
  // `/me` answers with the server's spelling and a login form answers with
  // whatever was typed; treating those as two accounts would strand the
  // documents of whichever spelling came first.
  const canonical = dbNameForEmail("someone@example.com");

  expect(dbNameForEmail("Someone@Example.com")).toBe(canonical);
  expect(dbNameForEmail("  someone@example.com\n")).toBe(canonical);
});

test("an address outside ASCII still names a database", () => {
  expect(dbNameForEmail("ünïcode@example.com")).toMatch(/^db-[0-9a-f]{16}$/);
  expect(dbNameForEmail("ünïcode@example.com")).not.toBe(dbNameForEmail("unicode@example.com"));
});

/* ===== adopting the database that is already on disk ===== */

test("the first account to log in adopts the database that is already there", () => {
  // The upgrade case, and the only one that matters for the installs that
  // exist: one user, one database, full of their documents. Adopting it in
  // place moves no rows, so there is no half-done migration to survive.
  const store = fakeClaimStore();

  expect(resolveUserDbName("first@example.com", store)).toBe(LEGACY);
  expect(store.stored()).not.toBeNull();
});

test("the account that adopted it keeps it on the next boot", () => {
  const store = fakeClaimStore();

  resolveUserDbName("first@example.com", store);

  expect(resolveUserDbName("first@example.com", store)).toBe(LEGACY);
});

test("the second account to log in never gets the first account's database", () => {
  const store = fakeClaimStore();
  resolveUserDbName("first@example.com", store);
  const claimed = store.stored();

  expect(resolveUserDbName("second@example.com", store)).toBe(dbNameForEmail("second@example.com"));
  expect(store.stored()).toBe(claimed);
});

test("an account that comes back gets the database it left behind", () => {
  // The A → B → A switch: A's unsynced rows are still in the database A
  // adopted, and B's are in B's own.
  const store = fakeClaimStore();

  const first = resolveUserDbName("a@example.com", store);
  const second = resolveUserDbName("b@example.com", store);

  expect(resolveUserDbName("a@example.com", store)).toBe(first);
  expect(resolveUserDbName("b@example.com", store)).toBe(second);
  expect(first).not.toBe(second);
});

test("a boot interrupted after the claim was recorded adopts the same database", () => {
  // The claim is one storage write and nothing else happens on the strength of
  // it, so "interrupted" can only mean: recorded, then the page went away. The
  // next boot reads it back and takes the same branch.
  const beforeCrash = fakeClaimStore();
  resolveUserDbName("first@example.com", beforeCrash);

  const afterCrash = fakeClaimStore(beforeCrash.stored());

  expect(resolveUserDbName("first@example.com", afterCrash)).toBe(LEGACY);
  expect(resolveUserDbName("second@example.com", afterCrash)).toBe(
    dbNameForEmail("second@example.com"),
  );
});

test("a claim that cannot be recorded is not acted on", () => {
  // Adopting without a durable claim would let the *next* account adopt the
  // same database too, which is the leak this ticket exists for. The legacy
  // database is left untouched instead: the account reads its own, empty one
  // and re-pulls from the server, and nothing is deleted.
  const store = fakeClaimStore(null, { denyWrites: true });

  expect(resolveUserDbName("first@example.com", store)).toBe(dbNameForEmail("first@example.com"));
  expect(resolveUserDbName("second@example.com", store)).toBe(dbNameForEmail("second@example.com"));
});

test("a claim store that cannot be read is not adopted from", () => {
  const store = fakeClaimStore("whatever", { refuseReads: true });

  expect(resolveUserDbName("first@example.com", store)).toBe(dbNameForEmail("first@example.com"));
});

test("no account is an error, not a database everyone shares", () => {
  const store = fakeClaimStore();

  for (const nobody of ["", "   ", null, undefined]) {
    expect(() => resolveUserDbName(nobody as string, store)).toThrow();
  }
  expect(store.stored()).toBeNull();
});

/* ===== the claim, through the real localStorage ===== */

/**
 * The claim's key, per docs/ARCHITECTURE.md §6.2 — spelled out for the same
 * reason as LEGACY above, and as boot.test.ts spells the session blob's key.
 */
const CLAIM_KEY = "gingko-local-db-owner";

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  localStorage.clear();
});

test("nothing recorded reads as no claim", () => {
  expect(readDbClaim()).toBeNull();
});

test("a recorded claim survives a reload", () => {
  writeDbClaim("0123456789abcdef");

  expect(readDbClaim()).toBe("0123456789abcdef");
  expect(localStorage.getItem(CLAIM_KEY)).toBe("0123456789abcdef");
});

test("the claim does not spell the address either", () => {
  resolveUserDbName("someone@example.com");

  expect(localStorage.getItem(CLAIM_KEY)).not.toContain("someone");
  expect(localStorage.getItem(CLAIM_KEY)).not.toContain("example.com");
});

test("a storage that refuses the write reports it instead of throwing", () => {
  const setItem = Storage.prototype.setItem;
  Storage.prototype.setItem = () => {
    throw new Error("QuotaExceededError");
  };

  try {
    expect(writeDbClaim("0123456789abcdef")).toBe(false);
  } finally {
    Storage.prototype.setItem = setItem;
  }
});

test("a storage that accepts the write and drops it reports a failure", () => {
  // Not hypothetical: Safari's private mode has answered `setItem` without
  // storing. A claim nobody can read back is no claim at all, and acting on it
  // would let the next account adopt the same database.
  const setItem = Storage.prototype.setItem;
  Storage.prototype.setItem = () => {};

  try {
    expect(writeDbClaim("0123456789abcdef")).toBe(false);
  } finally {
    Storage.prototype.setItem = setItem;
  }
});

test("the accounts on one browser get one legacy database between them", () => {
  // The default path, end to end, through the storage the browser really has.
  expect(resolveUserDbName("first@example.com")).toBe(LEGACY);
  expect(resolveUserDbName("second@example.com")).toBe(dbNameForEmail("second@example.com"));
  expect(resolveUserDbName("third@example.com")).toBe(dbNameForEmail("third@example.com"));
  expect(resolveUserDbName("first@example.com")).toBe(LEGACY);
});
