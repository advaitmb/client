# 27: Per-account local data (account switching sees stale cache)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 04 (resolved)

**Covers:** new finding from ticket 04's resolution (not in CODE_REVIEW.md).

**What to build:** Logging in as a different account never shows the previous
account's cached documents. The Dexie database is one global `"db"`, so after
ticket 04 made logout/account-switching possible, a switched-in user sees the
departing user's cached document list and card rows.

Design decision (taken): namespace local data per account — derive the Dexie
db name from the logged-in email (hash it; don't leak the address into
IndexedDB names verbatim) — rather than clearing on user change, so each
account's unsynced offline work survives switching. Handle the migration of
the existing global `"db"` for the common single-user case (adopt it for the
first account that logs in, or re-pull from the server — implementer's call,
documented in Comments).

## Acceptance criteria

- [x] Login as account B after account A never surfaces A's trees/cards.
- [x] A's unsynced local rows survive a switch A→B→A.
- [x] Existing single-user installs keep their local data after upgrade.
- [x] Tests at the practical seam (db-name derivation; migration decision
      pinned).
- [x] CI green.

## Answer

Landed on `selfhost` as `c03db48` (the implementation) and `fa1fe41` (two pins
the implementation silently depended on), plus the commit carrying the §6.2
storage inventory and this ticket — SHA in Comments, which is written after it.

**The shape.** `src/shared/local-db.js` answers exactly one question — *which
database name* — and nothing in it opens, creates or deletes a database. That
is what makes the decision testable without IndexedDB, and it is why the
module is at ADR-0001 seam 4 rather than seam 2: adopting is a *write*, so the
answer is not pure. `doc.js` keeps the Dexie instance and the version-4 schema
beside the queries that depend on it, opens the database once the email is
known (`openUserDb`, idempotent by name), and every query goes through
`userDb()`.

### The hash

`db-<16 hex>`, from cyrb64 — a 64-bit non-cryptographic mixer — over
`encodeURIComponent` of the trimmed, lower-cased address.

- **Why hashed at all.** The name is readable by anything with the origin:
  devtools, `indexedDB.databases()`, and `src/web/database-download.js`, which
  puts the database's name in the *filename* of the export a user attaches to
  a bug report. Hashing keeps the address out of all three. It is not a
  privacy boundary and does not pretend to be — anyone holding a guess at the
  address can confirm it by hashing, and a shared browser profile was never a
  boundary in the first place (the other account's database is still on disk).
- **Why not `crypto.subtle` / SHA-256.** It is only exposed in a secure
  context. A self-host served over plain HTTP from a LAN address is not one,
  so the hash would be `undefined` on exactly the deployments this fork
  exists for. It is also async, and the answer is needed before the first
  Dexie call at boot.
- **Why 64 bits is enough.** The population is "accounts sharing one browser
  profile" — single digits, not a keyspace. Measured anyway before relying on
  it: 200 000 distinct addresses, zero collisions, first-nibble buckets
  uniform to within 2%.
- **Lower-casing is deliberate, and has a cost.** `/me` answers with the
  server's spelling and a login form answers with whatever was typed; if
  those derived two names, the documents stored under the first spelling would
  be stranded. Two accounts differing only in case therefore share a database.
  Accepted: no mail provider treats those as two mailboxes, and the failure it
  prevents is the more likely one.
- **The derivation is now frozen** by known-good literals
  (`tests/local-db.test.ts`). See the pins below for why that is not optional.

### The migration: adoption

There is exactly one database that predates per-account naming and one account
it belongs to — whoever is logged in on the install being upgraded. That
account **adopts** `"db"`: the name stays, and the adoption is recorded as a
claim under `gingko-local-db-owner` so no second account can adopt it too.
Every other account opens `db-<hash>`.

On a *fresh* install the first account also claims `"db"` (there is one code
path, not two). That is protective rather than untidy: the claim is spent, so a
later account cannot adopt it even if the session blob is lost.

### Crash-safety

The migration's only write is one `localStorage.setItem`, and **no row is
read, written or deleted on the strength of it**. From that:

- **It cannot be half-done.** A `setItem` lands whole or not at all, and there
  is no second step to be interrupted before.
- **It cannot run twice.** The claim is written only when there is none. A
  re-run by the same account reads its own claim and takes the same branch; a
  re-run by any other account reads a claim that is not its own and opens its
  own database.
- **A failure loses nothing.** A claim that cannot be recorded means `"db"` is
  simply not adopted: that account reads its own empty database and re-pulls
  from the server, the rows in `"db"` stay untouched, and they are picked up as
  soon as a claim can be recorded. `writeDbClaim` reads the value back rather
  than trusting `setItem`, because a storage that accepts a write and drops it
  (Safari private mode has done this) would otherwise leave `"db"` claimed by
  nobody — and the *next* account would adopt it too, which is this ticket's
  bug.

The rejected alternative is what makes the above worth stating. **Copying**
`"db"`'s rows into `db-<hash>` and deleting `"db"` is a full re-write of every
card version the user has, and it has a state in the middle: interrupted
halfway it leaves rows in both places with no way to tell which run they came
from, and — worse — a copy that *finished* but whose delete did not leaves a
`"db"` that a later boot copies forward again, putting rows the user has since
edited back over the newer ones (`bulkPut` is keyed by primary key, so the
older row wins by arriving last). Guarding that needs a marker anyway, which
is this design with the dangerous half added. **Re-pulling from the server**
was the other option and is worse still: it discards precisely the unsynced
offline rows that tickets 04 and 27 both exist to keep.

### ImmortalDB and localStore: left keyed by treeId, deliberately

Two stores are keyed by document, not by account: `backup-snapshot:<treeId>`
(ImmortalDB) and `gingko-local-store/<treeId>/settings`. Neither is
namespaced, and the premise usually offered for that — *treeIds are
server-generated, so they cannot collide* — **is false, verified from code**:
`Page/DocNew.elm` mints a new id client-side via `RandomId.generate`, which is
`stringGenerator 7` — seven base62 characters (`src/elm/RandomId.elm`), a
space of 62^7 ≈ 3.5·10^12. There is no server round-trip and no uniqueness
guarantee.

So the decision rests on consequence instead, which is the stronger argument:

- `backup-snapshot:<treeId>` **has no read path**. `ImmortalDB.set` in
  `saveBackupToImmortalDB` is the only reference in the client; there is no
  `.get` anywhere. It cannot surface anything to another account through the
  app, whatever it is keyed by.
- `gingko-local-store/<treeId>/settings` holds `last-actives` and `theme` —
  view state, not content — and an absent or corrupt one already reads as "no
  settings yet" (S8).
- **Neither holds unsynced work.** All of it is in Dexie, which *is* per
  account now.

A clash therefore costs a wrong theme or a wrong focused card, self-correcting
on the next write, at a probability that needs two accounts on one profile to
independently draw the same seven characters. Namespacing would buy that, and
cost a migration of every per-document settings key ever written plus a
migration for a store nothing reads. It would also be arguably wrong: a
document id is legitimately shared between accounts when the *document* is
shared, so per-document is the honest key for per-document view state.

Recorded in `docs/ARCHITECTURE.md` §6.2 with the client-minted provenance
spelled out, so the next reader does not re-derive the false premise.

### Tests — 22 at the seam, red before green

`tests/local-db.test.ts` (21): the name never contains the address; it matches
`db-[0-9a-f]{16}`; the same account always names the same database and two
accounts never do; case and whitespace variants are one account; a non-ASCII
address still names a database. Then the migration, driven through an
in-memory claim store that can also refuse to be read or written: the first
account adopts and keeps it; the second never gets it; A→B→A returns each
account to its own; a boot interrupted after the claim was recorded takes the
same branch; a claim that cannot be recorded is not acted on; no account is an
error rather than a database everyone shares. Then the claim through the real
`localStorage`, including a storage that throws on write and one that accepts
the write and drops it.

Two of those 22 were added by `fa1fe41` after auditing `c03db48`, because the
implementation depended on them silently:

1. **`an account's database name is the same one it was before`** — known-good
   literals. The pre-existing "the same account always names the same
   database" compares the hash to itself, so it survives *any* change of
   mixer, encoding or case handling. Verified: changing one cyrb64 multiplier
   left all 20 original tests green. That is the one mistake here that costs
   data — a name that moves does not find a renamed database, it finds no
   database, so the account re-pulls from the server while the rows that were
   never pushed sit under the old name with nothing left that looks there.
2. **`keeps the record of which account owns the legacy database`**
   (`tests/logout.test.ts`) — an unclaimed `"db"` is adoptable, so a logout
   that took `gingko-local-db-owner` along with the session blob would hand
   the departing account's documents to whoever logged in next. Exactly this
   ticket's leak, restored by a plausible tidy-up ("clear the `gingko-*` keys
   we wrote"). Pinned beside the per-document settings logout already promises
   to keep. Verified red by adding that `removeItem` to `logoutUser`.

Suite: **236 bun tests, 206 elm-test**, all green. Build green, `config-check`
exit 0, `package-lock.json` in sync. The module is confirmed present in the
shipped bundle (`web/doc.js`), not orphaned.

## Comments

- **Where the switch actually happens.** Ticket 04's logout hands control back
  to Elm rather than reloading, so an A→B switch happens *in one page load*:
  `openUserDb` sees a different name, stops the departing account's sync,
  closes its connection, and opens B's. That branch is live, not theoretical.
  Boot has the same shape for the case where the stored blob names A and `/me`
  answers B — the database is opened again for whoever `/me` named, before the
  document list is seeded into it.

- **`database-download.js` needed no change.** It enumerates
  `indexedDB.databases()` and exports each one, so it picks up per-account
  names on its own — and it is the reason the name is hashed, since the name
  goes into the filename the user attaches to a bug report.

- **Residual risk, named and accepted: localStorage cleared while IndexedDB
  survives.** The claim goes with it, and the next account to log in can adopt
  `"db"`. This needs storage cleared *selectively* — clearing site data takes
  both — and the session blob lives in the same store, so such a client has
  forgotten who was logged in either way. No data is lost; the pre-ticket
  behaviour is what returns.

- **A pre-27 `"db"` could already hold two accounts' rows, and adoption cannot
  un-mix it.** There was no logout before ticket 04, but boot's `/me`
  auto-login adopts whatever account the server cookie names, so a blob
  cleared while IndexedDB survived could seed a second account's documents
  into the shared `"db"`. The adopter sees the mix (the document list has no
  owner filter). Left as is: this is strictly better than before, where *every*
  account saw it and every new account added to it, and it is now only ever
  the one adopting account. Filtering by owner was considered and rejected —
  `cards` rows carry no owner, and a `trees` owner filter would hide documents
  legitimately shared *with* the account.

- **Adjacent finding, left alone: `userDbName` in `doc.js` is dead.**
  `setUserDbs` assigns `userDbName = \`userdb-${helpers.toHex(email)}\`` and
  nothing ever reads it — a leftover from the CouchDB-per-user replica that no
  longer exists. It never reaches storage, so it is dead code rather than an
  exposure, but note that removing it also orphans `toHex` in
  `doc-helpers.js`, its only caller. Left for ticket 23 (js-robustness) rather
  than widened into this one.
