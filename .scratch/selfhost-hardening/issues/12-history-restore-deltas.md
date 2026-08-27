# 12: History restore stops re-deleting already-deleted cards

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D9.

**What to build:** Restoring a snapshot produces deltas only for cards whose
state actually changes. Today every card ever deleted gets a fresh unsynced
deletion row on each restore (snapshots exclude deleted cards, and the merge
marks every absent card deleted), and empty deltas are pushed anyway.

## Acceptance criteria

- [x] Failing test first (seam 1): restore over a doc with previously deleted
      cards emits no new rows for cards already `deleted = True`.
- [x] Empty per-card deltas are not pushed.
- [x] Restore still deletes cards that exist now but are absent from the
      snapshot, and restores content/positions per snapshot.
- [x] CI green.

## Answer

Landed in commits `d2ba1d2` and `0c7cf25` on `selfhost` (claim: `ac85372`).

Both halves of D9, one per seam.

### Seam 1 — a restore writes only what changes

`getRestoredData` reduces both card sets with `newestPerId` (ADR-0005 §1 — it
was already deduping by newest row via `sortOldestFirst` + `Dict.fromList`;
now it says so), and `mergeRestoreData` decides per card:

| the card is | before | now |
| --- | --- | --- |
| here, absent from the snapshot, already deleted | a fresh unsynced deletion row, on every restore | untouched |
| here, absent from the snapshot, alive | a deletion row | a deletion row |
| in both, same state, different stamp | the snapshot row re-staged | untouched |
| in both, different state | the snapshot row staged | the snapshot row staged |

So two changes: skip the already-deleted, and compare card **state** rather
than version stamps. `sameCardState` is that comparison — content, parentId,
position, deleted: every field a delta can carry, and nothing else. Rows can
differ by stamp and still say the same thing, and D9's own empty deltas were
one of the ways that happened (see below), which is what made the bug
self-sustaining: the server bumped the stamp, the bumped row came back, and the
next restore staged that card again.

`restore` also returns no message when the change lists come back all empty.
That case is newly reachable — the port layer's `SaveCardBased` stamps the tree
row `synced: false` with a fresh `updatedAt` for every save it is handed, so an
empty save would queue a tree-metadata push for nothing. `Page.App`'s `Restore`
branch already closed the history view on an empty message list, so the caller
needed nothing.

### Seam 2 — where the empty-delta guard lives, and why there

Two guards, each at a funnel:

- **`toDelta` drops `Delta … []`.** Every push and every test goes through
  this one function, and `cardDelta` can emit an op-less delta from either of
  two limbs (newest unsynced vs. synced base, and the newest-vs-oldest pair of
  a never-synced card), so filtering the assembled list is the seam that can't
  be bypassed. Filtering inside `cardDelta` would mean the same guard repeated
  per limb, with the next limb free to forget it; filtering in the push
  encoder would leave `toDelta_tests_only` — the tested view — disagreeing
  with the wire.
- **`pushDelta` became `pushDeltas : String -> List (Card UpdatedAt) -> List
  Outgoing.Msg`**, which returns no message when no delta survives. That is
  necessary, not tidiness: `dlts: []` is not a way to say "nothing to push".
  The server reads `msg.d.dlts[msg.d.dlts.length - 1].ts` *before* it looks at
  the list (gingko/server `src/index.ts:337`), so an empty push is a
  TypeError in its socket handler. Both call sites — `cardDataReceived`'s
  `Unsynced` branch and `triggeredPush` — now splice in the result.

For the record, what an op-less delta *did* when the server could read it:
`runDelta` treats `ops.length === 0` as `runUpdTs`, "set this card's
`updatedAt` to this stamp" (`src/index.ts:1176`/`:1284`). So every ever-deleted
card, on every restore, produced a server write nobody made, a `doPull`
broadcast to every collaborator, and an ack that marked the pointless local row
synced.

### Tests

`tests/DataTest.elm`, ADR-0001 seam 1 (which names `restore`), 5 new tests —
29 elm tests in total. One fixture, `rowsBeforeRestore`: since the snapshot was
taken, `b` was edited offline, `c` was added, `f` was deleted, and `g` was given
a new stamp for the same state; `d` and `e` were already deleted when it was
taken (`d`'s deletion pushed, `e`'s still unsynced), so neither is in it. The
tests drive `historyReceived` → `restore` → the `SaveCardBased` JSON, then apply
the staged save the way the port layer does (`applySave`, extended to write
`toMarkDeleted` rows too) and hand the result back through `cardDataReceived`,
so both the tree and the `PushDeltas` payload are the real ones.

1. *restoring a snapshot stages nothing for cards that are already deleted* —
   pins `toAdd` (the two cards whose state changed) and `toMarkDeleted` (the one
   card added since) exactly.
2. *restoring a snapshot reverts the cards it holds and deletes the cards added
   since* — the visible tree afterwards: `b` back to its snapshot content, `f`
   undeleted at its snapshot position, `c` gone, `d`/`e` still gone.
3. *the push after a restore carries an op for every delta and no empty ones* —
   `e`'s pending `del` at its own stamp, `c`'s new `del`, `f`'s `ud`, and
   nothing at all for `b`, whose snapshot content is what the server already
   has.
4. *a card whose unsynced row matches the server is not pushed at all* — the row
   the old restore left behind, straight through `triggeredPush`: no
   `PushDeltas` message, not an empty one.
5. *restoring the state the document is already in saves nothing*.

### Verification

Rebased on `selfhost` at `e80ac48`: `bun run test:elm` 29/29, `bun test` 49/49
across 8 files, `bun run newbuild` succeeds, `node config-check.js` exit 0. CI
green on `selfhost`: run
<https://github.com/advaitmb/client/actions/runs/33068171228> (`0c7cf25`, the
code) and <https://github.com/advaitmb/client/actions/runs/33068424890>
(`625e5bb`, the tracker).

## Comments

- Red-first evidence, before touching `Doc/Data.elm` (16 passed, 3 failed):
  - Test 1 — `toAdd` also carried `g` (unchanged, "Stable") and `toMarkDeleted`
    carried `d` and `e`: the D9 bug verbatim, one deletion row per
    already-deleted card.
  - Test 3 — the pushed deltas were `[{id=b, ops=[]}, {id=c, ops=[del]},
    {id=d, ops=[]}, {id=e, ops=[del]}, {id=f, ops=[ud]}, {id=g, ops=[]}]`:
    three op-less deltas on the wire, and `e`'s pending deletion re-issued at
    the restore's stamp instead of its own.
  - Test 4 — one `PushDeltas` message where none was wanted.
  - Test 2 (the tree) passed from the start; it is the don't-break guard for
    the third acceptance criterion, since the old code reached the same visible
    state by a noisier route. Test 5 was written after seam 1 landed and
    confirmed red there (1 message), because seam 1 is what makes an all-empty
    save reachable.
- **Residue, deliberately left:** a restore can still leave an unsynced row
  with nothing to push — card `b` in the fixture, whose snapshot content is
  what the server already holds. The row is honest local state, but it can
  never be acked, so the card keeps classifying `Unsynced` and the save
  indicator reads "saved offline" until the next successful push of anything
  (`lastSyncedTime` then overtakes the row's stamp). Every alternative is worse:
  pushing an op-less delta *is* the bug; marking the row synced locally would
  put a stamp the server never saw into the push checkpoint (`chk` = max synced
  stamp) and suppress incoming rows; dropping redundant unsynced rows is a
  garbage-collection pass over the version log, well outside D9.
- **Out of scope, found while in the file: the local snapshot can contain a
  deleted card.** `src/shared/doc.js:585` builds it from
  `dexie.cards.where({ treeId, deleted: 0 })` — raw rows, not newest-per-id —
  so a card whose newest row is a deletion still contributes its stale
  pre-deletion row, and restoring that snapshot undeletes the card. ADR-0005 §1
  applies to the JS side too, and that file already has `newestVersionPerId`
  (used by `saveBackupToImmortalDB`). Not D9: it predates this fix and survives
  it, and it lives in the port layer. The server's snapshots are fine — its
  `cards` table holds one LWW row per card, so its `WHERE deleted != 1` means
  what it says.
- `docs/CODE_REVIEW.md` left as the catalog as found, matching tickets
  02/03/04/05/06/07/10. D8 (position rebalancing) remains ticket 11.
