/**
 * Which local database this account's documents live in.
 *
 * The Dexie database was one global `"db"` (docs/ARCHITECTURE.md §6.2), which
 * was harmless while a browser could only ever hold one account: nothing could
 * log out. Ticket 04 made logging out work, and that turned the shared name
 * into a leak — the next account to log in opened the departing account's
 * `trees`/`cards`/`tree_snapshots` and read them as its own document list.
 *
 * So the name is derived from the logged-in email. Nothing is cleared on a
 * switch: each account's database stays where it is, which is what makes
 * unsynced offline work survive A → B → A (ticket 04 keeps local data for the
 * same reason).
 *
 * Nothing here opens, creates or deletes a database — this module only answers
 * *which name*, so the decision can be exercised without IndexedDB. doc.js owns
 * the Dexie instance and its schema.
 */

/**
 * The name every install before ticket 27 used, and the one that still holds an
 * upgrading user's documents.
 */
const LEGACY_DB_NAME = "db";

/**
 * Where the adoption of {@link LEGACY_DB_NAME} is recorded: the hash of the one
 * account it belongs to. Beside the session blob (`gingko-session-storage`),
 * which is already what decides which account this client is.
 */
const DB_CLAIM_KEY = "gingko-local-db-owner";

/**
 * The same account, however its address was written down.
 *
 * `/me` answers with the server's spelling of the address and a login form
 * answers with whatever was typed into it; if those derived two names, the
 * documents stored under the first spelling would be stranded. Two accounts
 * that differ only in the case of their addresses would share a database, which
 * is the accepted cost: no mail provider treats those as two mailboxes, and the
 * failure it prevents (an account losing its local work because the spelling
 * changed) is the more likely one.
 */
function normalizeEmail(email) {
  return String(email).trim().toLowerCase();
}

/**
 * A 64-bit hash of a string, as 16 hex characters.
 *
 * The mixer is bryc's cyrb64 (public domain): two 32-bit accumulators with
 * different multipliers, avalanched into each other at the end. Cheap, stable
 * across browsers and versions (plain integer arithmetic, no float, no
 * dependency), and well enough distributed that a collision between two
 * accounts on one machine is not a thing that happens.
 *
 * NOT a cryptographic hash, and it does not have to be. What the hash is for is
 * keeping the address out of a name that anything can read back — devtools,
 * `indexedDB.databases()`, and the bug-report export in
 * `src/web/database-download.js`, which puts the database's name in the
 * *filename* it hands the user to attach. Anyone holding a guess at the address
 * can confirm it by hashing; that is not what this defends against, and a
 * shared browser profile is not a privacy boundary in the first place (the
 * other account's database is still on disk under its own name).
 *
 * SHA-256 via `crypto.subtle` was the alternative and is unusable here: it is
 * only exposed in a secure context, and a self-host served over plain HTTP from
 * a LAN address is not one — the hash would be `undefined` exactly on the
 * deployments this fork exists for. It is also asynchronous, and this answer is
 * needed before the first Dexie call at boot.
 *
 * @param {string} text
 * @returns {string} 16 lowercase hex characters.
 */
function hash64(text) {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;

  for (let i = 0; i < text.length; i++) {
    const ch = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }

  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);

  const hex = (n) => (n >>> 0).toString(16).padStart(8, "0");
  return hex(h2) + hex(h1);
}

/**
 * The hash that identifies an account's local data.
 *
 * The address is encoded before hashing so that every code point reaches the
 * mixer as ASCII: `charCodeAt` reads UTF-16 units, and `encodeURIComponent` is
 * a total, stable, injective mapping to ASCII, so an internationalized address
 * hashes as reliably as `a@b.com` and no two addresses collide by encoding.
 *
 * @param {string} email
 * @returns {string} 16 lowercase hex characters.
 */
function hashEmail(email) {
  return hash64(encodeURIComponent(normalizeEmail(email)));
}

/**
 * The database name for an account that does not own {@link LEGACY_DB_NAME}.
 *
 * @param {string} email
 * @returns {string}
 */
function dbNameForEmail(email) {
  return "db-" + hashEmail(email);
}

/**
 * The claim on {@link LEGACY_DB_NAME}, backed by localStorage: the hash of the
 * account that owns it, or null if nobody does.
 *
 * Guarded like `readSessionData` in session.js, and for the same reason —
 * storage can be denied outright (private modes, blocked site data). A claim
 * that cannot be read is *no claim*, which is the safe answer: see
 * {@link resolveUserDbName}.
 *
 * @returns {string|null}
 */
function readDbClaim() {
  try {
    const raw = localStorage.getItem(DB_CLAIM_KEY);
    return typeof raw === "string" && raw.length > 0 ? raw : null;
  } catch (err) {
    console.error("local data: could not read which account owns the local database", err);
    return null;
  }
}

/**
 * Record the claim on {@link LEGACY_DB_NAME}, and report whether it is durable.
 *
 * Read back rather than trusted: a storage that accepts `setItem` and drops the
 * value would leave the legacy database claimed by nobody, and the next account
 * to log in would adopt it as well — the very leak this module exists to close.
 * The caller acts only on `true`.
 *
 * @param {string} hash
 * @returns {boolean} whether the claim can be read back.
 */
function writeDbClaim(hash) {
  try {
    localStorage.setItem(DB_CLAIM_KEY, hash);
    return localStorage.getItem(DB_CLAIM_KEY) === hash;
  } catch (err) {
    console.error("local data: could not record which account owns the local database", err);
    return false;
  }
}

/** The claim store this runs against in the browser. */
const localStorageClaimStore = { read: readDbClaim, write: writeDbClaim };

/**
 * The name of the Dexie database holding this account's documents.
 *
 * The migration, in full. There is exactly one database that predates
 * per-account naming, and one account it belongs to: whoever is logged in on
 * the install that is being upgraded. That account **adopts** it — the name
 * `"db"` stays, and the adoption is recorded as a claim so that no second
 * account can adopt it too. Every other account gets {@link dbNameForEmail}.
 *
 * WHY ADOPT RATHER THAN COPY
 *
 * The alternative was to copy `"db"`'s rows into `db-<hash>` and delete `"db"`.
 * Dexie cannot rename a database, so that is a full read and re-write of every
 * card version the user has — and it has a state in the middle. A copy
 * interrupted halfway leaves rows in both places and no way to tell which run
 * they came from; worse, a copy that *finished* but whose delete did not leaves
 * a `"db"` that a later boot would copy forward again, putting rows the user
 * has since edited back over the newer ones (`bulkPut` is keyed by primary key,
 * so the older row wins by arriving last). Guarding that needs a marker anyway,
 * which is the whole of this design without the copy.
 *
 * Adoption moves nothing. The only write is one claim, so:
 *
 *  - **it cannot be half done** — a `setItem` either lands whole or not at all,
 *    and no row is read, written or deleted on the strength of it;
 *  - **it cannot run twice** — the claim is written only when there is none,
 *    and a re-run by the same account reads its own claim and takes the same
 *    branch (a re-run by another account reads a claim that is not its own);
 *  - **a failure loses nothing** — a claim that does not land means the legacy
 *    database is simply not adopted. That account reads its own empty database
 *    and re-pulls from the server; the rows in `"db"` stay untouched and are
 *    picked up as soon as a claim can be recorded.
 *
 * The unhappy case worth naming: if localStorage is cleared while IndexedDB
 * survives, the claim goes with it and the next account to log in can adopt
 * `"db"`. Clearing site data takes both together, so this needs storage cleared
 * selectively — and the session blob lives in the same place, so such a client
 * has forgotten who was logged in either way. No data is lost; the pre-ticket
 * behavior is what returns.
 *
 * @param {string} email  the logged-in account. Required: guessing here would
 *   hand out a database that everyone shares, which is the bug.
 * @param {{read: function(): (string|null), write: function(string): boolean}}
 *   [claimStore]  where the adoption is recorded. localStorage by default.
 * @returns {string} the Dexie database name to open.
 */
function resolveUserDbName(email, claimStore) {
  const store = claimStore || localStorageClaimStore;

  if (email == null || normalizeEmail(email) === "") {
    throw new Error("local data: cannot name a database without an account");
  }

  const hash = hashEmail(email);
  const ownName = dbNameForEmail(email);

  let claim = null;
  try {
    claim = store.read();
  } catch (err) {
    // A store that cannot be read is a store with no claim in it, and an
    // unclaimed legacy database is not this account's to take on faith.
    console.error("local data: could not read the local database claim", err);
    return ownName;
  }

  if (claim === hash) {
    return LEGACY_DB_NAME;
  }

  if (claim != null) {
    return ownName;
  }

  return store.write(hash) ? LEGACY_DB_NAME : ownName;
}

module.exports = {
  LEGACY_DB_NAME: LEGACY_DB_NAME,
  DB_CLAIM_KEY: DB_CLAIM_KEY,
  hashEmail: hashEmail,
  dbNameForEmail: dbNameForEmail,
  readDbClaim: readDbClaim,
  writeDbClaim: writeDbClaim,
  resolveUserDbName: resolveUserDbName,
};
