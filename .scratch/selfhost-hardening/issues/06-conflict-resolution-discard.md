# 06: Conflict resolution discards the whole local unsynced line

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D3 · Decision: ADR-0005 §2.

**What to build:** When the user resolves a conflict by picking **Theirs** or
**Original**, none of their discarded local edits ever reach the server: ALL
unsynced rows for that card id are removed, not just the newest. Picking
**Ours** keeps exactly the winning newest unsynced row.

**Note from ticket 05's resolution:** `cardDataReceived`'s auto-resolve
condition still tests `toAdd`/`toMarkSynced`, both of which
`resolveDeleteConflicts` now always leaves empty (the dead D10 limb was
removed). Check that condition still gates correctly while you're in there.

## Acceptance criteria

- [x] Failing test first (seam 1): offline-edit a card three times (three
      unsynced rows), receive a conflicting synced row, resolve as Theirs →
      the card classifies as Synced and the next delta push contains nothing
      for it.
- [x] Same for Original; Ours keeps one unsynced row.
- [x] CI green.

## Answer

Landed in commit `c9ee1cd` on `selfhost` (claim: `29dff4c`). CI run
<https://github.com/advaitmb/client/actions/runs/33066575789> green on
`c9ee1cd`.

`Doc.Data.resolveConflicts` now reads the card rows it was already given
(`CardBased allCards _ (Just versions)` — `allCards` used to be discarded) and
rewrites the whole version log of the conflicted cards, per ADR-0005 §2:

| selection | `toAdd` | `toRemove` |
| --- | --- | --- |
| `Theirs` | — | the original synced row **+ every unsynced row** of the conflicted ids |
| `Original` | the original content as a fresh unsynced row (unchanged) | same as `Theirs` |
| `Ours` | — | the original synced row + every unsynced row **except** `versions.ours` |

Three things make that correct rather than merely bigger:

- **All of our line, not just its newest row.** `versions.ours` is
  `getOurs`, i.e. the single newest unsynced row, so the old
  `toRemove` left every earlier offline save in the DB. With
  `historyLimit = 1`, dropping the original brought the synced count back to 1
  and the surviving unsynced rows re-classified the card as `Unsynced` — so the
  next `pushDelta` sent an `UpdOp` built from the newest *survivor*. Discarded
  content, pushed. The red test showed exactly that: after choosing Theirs, the
  push carried `"Edit 2"`.
- **Ours keeps exactly one row.** The winning row is identified by stamp
  (`UpdatedAt.areEqual` against `versions.ours`), not by "newest", so it is
  literally the row the conflict viewer showed as Ours.
- **Removals are confined to the conflicted ids.** Unsynced rows of other
  cards are unrelated local work still waiting to be pushed; the fixture keeps
  a second card with its own unsynced edit, and all three tests assert that
  card still pushes.

Dropping the original synced row (all three selections, pre-existing
behaviour) is what takes the card out of `Conflicted`: it brings the synced
count back under `historyLimit`. That reasoning is now in the function's doc
comment, which previously had none.

### The auto-resolve gate: verdict

It **gates correctly** — no behaviour change needed. `resolveDeleteConflicts`
returns non-empty `toRemove` exactly when it auto-resolved a delete-vs-edit
conflict (our unsynced deletions, or their pre-deletion synced row), and
returns everything empty for a pure content conflict, which is the case that
must reach the user. Since ticket 05 removed the D10 limb, `toAdd`/
`toMarkSynced`/`toMarkDeleted` are always empty, so the two conditions the old
`if` tested besides `toRemove` were dead but harmless.

What changed is only how the gate is written: one named
`mergeHandledIt` binding that asks whether the merge staged *anything*, across
all four lists (the old expression tested three and skipped `toMarkDeleted`,
which was the inconsistent one). Same truth value today; a future limb that
stages rows can no longer fall through the gate and have its save silently
dropped. Both directions are now pinned by tests: ticket 05's delete-conflict
test asserts `hasConflicts == False` with non-empty `toRemove`, and all three
new tests go through `Data.hasConflicts newData == True` before resolving.

### Tests

`tests/DataTest.elm`, ADR-0001 seam 1, three new tests (15 elm tests total).
One fixture, `conflictedRows`: card `a` with a synced original (`1000`), three
offline edits (`2000`/`3000`/`4000`) and their conflicting synced version
(`5000`), plus card `b` (synced `1000`, unsynced `2500`) which is not in
conflict. Each test receives the rows through `cardDataReceived` (so the
conflict under test is the one `getSyncState` actually reports), resolves,
applies the staged save the way `src/shared/doc.js` does — `bulkDelete` by
stamp, then `bulkPut` of the staged rows with a fresh `hlc.nxt()` stamp,
modelled as `applySave` — and then asserts what the DB holds and what
`triggeredPush` carries:

1. *resolving as Theirs discards every unsynced row of the card, not just the
   newest* — `toRemove` is all four of `a`'s rows; no unsynced row of `a`
   survives; the push contains only `b`'s delta.
2. *resolving as Original pushes the original content and none of the
   discarded edits* — same `toRemove`, plus the staged original row, which
   comes back as the only unsynced row of `a` and pushes
   `UpdOp{"Original", expected 5000}`.
3. *resolving as Ours keeps exactly the winning newest unsynced row* —
   `toRemove` is the first three stamps; `("a", "Edit 3")` is the one unsynced
   row left; the push carries `UpdOp{"Edit 3", expected 5000}` at stamp
   `4000`.

"The card classifies as `Synced`" is asserted as *no unsynced row and no delta
of its own* — the document as a whole stays `Unsynced` in these fixtures
because of card `b`, which is the point of including it.

### Verification

Rebased on `selfhost` at `a1ecbe8`: `bun run test:elm` 15/15 (12 + 3),
`bun test` 40/40 across 6 files, `bun run newbuild` succeeds,
`node config-check.js` exit 0, CI green (run 33066575789).

## Comments

- Red-first evidence, before touching `Doc/Data.elm`: all three tests failed
  (12 passed, 3 failed). The Theirs failure is the bug verbatim — actual
  `toRemove = ["1000:0:hash-a-1000","4000:0:hash-a-4000"]`,
  `unsyncedAfter = [("a","Edit 1"),("a","Edit 2"),("b","Child edit")]`, and a
  pushed delta `{ id = "a", ops = [{ content = Just "Edit 2", expectedVersion =
  Just "5000:0:hash-a-5000", t = "u" }], ts = "3000:0:hash-a-3000" }`: content
  the user discarded, on its way to the server. Original and Ours failed on
  `toRemove`/`unsyncedAfter` (all three edits surviving).
- New test-side machinery, kept small and documented: `unsyncedRow`,
  `encodeRows` (the `cards` JSON the port hands Elm), a decoder for the
  `PushDeltas` payload (`dlts` → `{id, ts, ops}`), and `applySave` as the port
  layer's half of a save. The push assertions go through the real encoded
  payload rather than `toDelta_tests_only`, so what they pin is the wire
  contract; no new test-only export was needed.
- Self-review changes, on top of the first green: hoisted the repeated
  `List.map .updatedAt versions.ours` out of the `Ours` filter; dropped a
  `pushMsgCount` field from the test helper that was redundant once the
  decoded deltas are asserted; renamed the stamp fixture to `ourLineStamps`
  with an honest docstring (it lists our line — the four discarded rows — not
  every row of card `a`).
- Out of scope, seen while in the file: `resolveDeleteConflicts`'s
  auto-resolution keeps *our* older unsynced rows, which is right — those are
  edits being preserved, not discarded; `Doc.Data.resolve` is a no-op stub
  from the pre-card-based format; `Page.App`'s `ConflictResolved` only sends
  the save and leaves `conflictViewerState` to be recomputed on the next
  `cardDataReceived`. D8 (position rebalancing) and D9 (history restore)
  remain tickets 11 and 12; `docs/CODE_REVIEW.md` is left as the catalog as
  found, matching tickets 02/03/05/07/10.
