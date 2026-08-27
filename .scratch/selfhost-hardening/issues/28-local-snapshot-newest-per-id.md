# 28: Local snapshots must use newest-per-id (restore can undelete cards)

Part of `../map.md`. **Type:** task · **Status:** resolved

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

- [x] A snapshot taken after deleting a card contains no row for that card
      (test at seam 2/4 with a fixture row set: edit, delete, edit-other,
      snapshot).
- [x] Existing snapshot behavior for live cards unchanged.
- [x] Tests red first; full suite + build green; CI green.

## Answer

Landed in `63b4145` on `selfhost` (claim: `862e078`). One function changed:
the snapshot write inside `applyCardBasedSave` (`src/shared/save.js`), where
ticket 08 moved it.

**The bug, end to end.** `cards.where({treeId, deleted: 0})` asks a per-row
question of an append-mostly log. A deleted card's rows are its newest one
(`deleted: 1`, filtered out) *plus every row it outgrew* (`deleted: 0`, kept),
so the snapshot held the card at its pre-deletion content. `doc.js` then hands
Elm every snapshot row as `deleted: 0` (`historyDataSubscription`), and
`getRestoredData` compares card *state*, so the card came back — the restore
half was already correct after ticket 12; the snapshot it was given was not.

**The query: the pre-filter had to go.** It is not an optimisation that happens
to be wrong at the margin, it is the bug — the newest row of a deleted card is
exactly the row it hides, so no reduction downstream of it can recover the
answer. The document's rows are now read through the plain `treeId` index and
reduced in JS:

```js
const rows = await db.cards.where({ treeId: treeId }).toArray();
const cards = newestVersionPerId(rows).filter((c) => !c.deleted);
```

Dedupe **first**, then drop the deleted: the other order resurrects a deleted
card from one of its older rows (ADR-0005 §1; `newestVisible` in `Doc/Data.elm`
carries the same note).

*Perf.* The query returns the document's whole log instead of its non-deleted
rows, and `newestVersionPerId` sorts it — one sort per content save, on the
save path that already writes rows and a snapshot in the same tick. The log is
kept near one row per card by fast-forward, and the rows were already all being
read, mapped and stored as the snapshot's `data`. The `[treeId+deleted]`
compound index is now unused by application code; it is left in the schema
because removing an index means a Dexie version bump, which is not this
ticket's to spend.

**The snapshot's id, and why it moved.** `snapshotId` is `"<ts>:<treeId>"`, and
`tree_snapshots` is keyed by it, so the id decides whether a save adds a history
entry or overwrites one. It is now the newest stamp in the **log**
(`maxStamp(rows.map(...))`), deletion rows included — not the newest row the
snapshot holds. Taking it from the snapshot's own rows would stamp a
post-deletion snapshot with the timestamp of the last surviving edit and
overwrite the entry that still had the deleted card, which would turn this fix
into history loss. Two consequences, both intended and tested:

- Deleting a card now leaves a restore point of its own. Before, a deletion
  save re-wrote the previous entry's id with content identical to it (the stale
  row was still in there), so deletions were invisible in the slider even
  though the handler has always snapshotted them (`toAdd.length > 0 ||
  toMarkDeleted.length > 0`).
- The `reduce`-on-empty crash a save that deleted the last card would have hit
  is gone: `rows` is non-empty whenever the snapshot branch runs.

Server-pulled snapshots are untouched, and correct as they were: the server's
`cards` table holds one LWW row per card, so its `WHERE deleted != 1` means
what it says.

### Tests

`tests/save.test.ts`, seam 4, 4 new tests (11 in the file) on one fixture —
`documentEditedOffline`: since the server last saw the document, `a` was edited
then deleted, `b` was edited, `d` was deleted then brought back by a restore,
and every one of those rows is still in the table.

1. *a card whose newest row is a deletion is left out of the snapshot* — `a`,
   the ticket's fixture in full (edit, delete, edit-other, snapshot).
2. *every card the document still holds contributes exactly its newest row* —
   the whole card set as `[id, content]` pairs, so a stale row shows up as a
   second pair for that id rather than passing quietly.
3. *a card deleted and then brought back is in the snapshot, at the row that
   brought it back* — `d`, the guard against over-dropping (a card that has
   *any* deletion row is not a deleted card).
4. *a save that deletes a card leaves the history entry that still had it* —
   the id decision, and the guard against this fix eating history.

The in-memory `fakeDexie` now models one more Dexie fact: `where({...})` is
answered only through a declared index, and `cards` declares `treeId` and
`[treeId+deleted]` — so both the whole-log query and a per-row `deleted`
pre-filter are queryable, and a typo is a schema error rather than a silent
scan.

### Verification

Rebased onto `selfhost` at `4a040d2` (over tickets 14 and 29, which landed
mid-work): `bun test` 62/62 across 9 files, `bun run test:elm` 75/75,
`bun run newbuild` succeeds (the bundle carries the reduction —
`newestVersionPerId(...).filter(...)` is in `web/doc.js`), `node config-check.js`
exit 0. Pre-rebase, on ticket 08's tree, the same checks were 62/62 and 43/43.

CI green on `selfhost` for both commits: run
<https://github.com/advaitmb/client/actions/runs/33073185764> (`63b4145`, the
code) and <https://github.com/advaitmb/client/actions/runs/33073395631>
(`54db121`, the tracker).

## Comments

- **Red-first evidence** (the four tests against the unfixed handler — 7 pass,
  4 fail):
  - Test 1: the snapshot contained `["a", "A, edited just before I deleted
    it"]` — the bug verbatim, the deleted card at its pre-deletion content.
  - Test 2: `b` appeared twice (`"B, as the server has it"` *and* `"B, edited
    since"`) and `d` twice, on top of `a` — the snapshot was the log, not the
    card set. Worth noting on its own: a snapshot has always carried every
    stale row of every *live* card too, and restoring one then depended on
    which duplicate `Dict.fromList` kept.
  - Test 3: `d` was in the snapshot twice, so "the card is back" was true only
    by accident.
  - Test 4: one snapshot id where two were wanted — the deletion save had
    overwritten `1500:open-doc` instead of adding `5000:open-doc`.
- **One existing assertion relaxed, deliberately.** *the snapshot holds the
  named document's cards and nothing else* pinned `data` order as
  `["i1", "i2"]`; `newestVersionPerId` returns newest row first, so the order
  flips. It is compared as a set now (same literal, `.sort()`), because a
  snapshot's row order is not meaningful — Elm rebuilds the tree from
  `parentId` and sorts siblings by `(position, id)` (`treeHelper`,
  `Doc/Data.elm`). Nothing else asserted on that order.
- **`maxStamp` instead of `Math.max` over timestamp prefixes**, on the line the
  fix was already rewriting: one ordering idiom per file, per ADR-0005 §3 and
  CONTRIBUTING's "comparing stamps as strings" rule. The value is identical
  (the newest stamp's millisecond *is* the largest millisecond); the line now
  says "the newest row in the log", which is what the comment above it claims.
- **Adjacent finding, left alone: the ImmortalDB backup keeps deleted cards.**
  `saveBackupToImmortalDB` (`src/shared/doc.js`) reduces with
  `newestVersionPerId` and stops there, and `doc.js`'s `treeHelper` filters
  only on `parentId`, so a card whose newest row is a deletion is still written
  into `backup-snapshot:<treeId>`. Same half-applied ADR-0005 §1, different
  writer, and much lower stakes: that blob is write-only plain text
  (ARCHITECTURE §5.1) that nothing in the app reads back, so it cannot undelete
  anything — it just misrepresents the document to whoever pastes it. Not
  `SaveCardBased`, so not this ticket.
- **Not touched:** `docs/CODE_REVIEW.md` (this finding was never in the
  catalog — it came out of ticket 12's resolution), the `[treeId+deleted]`
  index, and the "don't add new empty cards to history" early return, which
  still returns before `trees.update` (ticket 08's declared residue).
- `docs/ARCHITECTURE.md` §5.5 now states both decisions — newest-per-id then
  deleted dropped, and the id taken from the log — and the doc comment on
  `encodeHistory` in `tests/DataTest.elm`, which described the port as
  filtering `deleted: 0` rows, now describes what it does.
