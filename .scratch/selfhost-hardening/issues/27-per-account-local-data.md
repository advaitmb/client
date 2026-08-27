# 27: Per-account local data (account switching sees stale cache)

Part of `../map.md`. **Type:** task · **Status:** claimed

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

- [ ] Login as account B after account A never surfaces A's trees/cards.
- [ ] A's unsynced local rows survive a switch A→B→A.
- [ ] Existing single-user installs keep their local data after upgrade.
- [ ] Tests at the practical seam (db-name derivation; migration decision
      pinned).
- [ ] CI green.
