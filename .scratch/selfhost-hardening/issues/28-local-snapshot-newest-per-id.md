# 28: Local snapshots must use newest-per-id (restore can undelete cards)

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 12 (resolved) · 10 (resolved — `newestVersionPerId` exists in
`src/shared/stamps.js`)

**Covers:** new finding from ticket 12's resolution (not in CODE_REVIEW.md).
ADR-0005 §1 applied to the JS side.

**What to build:** The port layer's local snapshot write (`doc.js` — the
`SaveCardBased` path querying `dexie.cards.where({ treeId, deleted: 0 })`)
snapshots raw rows, not newest-per-id: a deleted card still contributes its
stale pre-deletion row, so restoring that snapshot undeletes the card. Reduce
the queried rows with `newestVersionPerId` (already exported from
`src/shared/stamps.js`) AND drop cards whose newest row is deleted — note the
order (dedupe first, then drop deleted; see `newestVisible`'s comment in
`Doc/Data.elm`). The Dexie `deleted: 0` filter runs per-row, which is exactly
the bug — decide whether to keep it as a pre-filter or query all rows for the
tree and reduce in JS; document the choice. Server-pulled snapshots are fine
(one LWW row per card).

## Acceptance criteria

- [ ] A snapshot taken after deleting a card contains no row for that card
      (test at seam 2/4 with a fixture row set: edit, delete, edit-other,
      snapshot).
- [ ] Existing snapshot behavior for live cards unchanged.
- [ ] Tests red first; full suite + build green; CI green.
