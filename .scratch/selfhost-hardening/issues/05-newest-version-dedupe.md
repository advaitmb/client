# 05: Newest-version-per-id everywhere (subtree delete / merge / conflict tree)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D1, D2, D10, S9 · Decision: ADR-0005 §1.

**What to build:** Operations that scan version rows respect
newest-version-per-id and deletion visibility, so: deleting a subtree never
deletes a card that was moved out of it (D1); merging cards never re-parents
stale or deleted child rows (D2); the dead/contradictory limb of
`resolveDeleteConflicts` is fixed or removed with its intent documented (D10);
conflict-tree building doesn't depend on JS row order (S9).

## Acceptance criteria

- [x] Failing tests first (seam 1): move-then-delete-old-parent keeps the
      moved card; merge with a deleted child doesn't resurrect it; merge
      position offsets ignore deleted children.
- [x] `getDescendants`-family scans dedupe to newest row per id.
- [x] D10's filter is corrected or the limb removed, with a test pinning the
      chosen behavior.
- [x] All tests green in CI.

## Answer

Landed in commit `ab4a495` on `selfhost` (claim: `858872e`).

One view of the version log now feeds every scan in `src/elm/Doc/Data.elm`
(ADR-0005 §1):

- `newestPerId` — newest version row per card id (`sortNewestFirst` +
  `uniqueBy .id`).
- `newestVisible` — `newestPerId`, then drop cards whose newest row is a
  deletion. The order matters: filtering deleted rows *first* (what
  `getPosition` used to do) can resurrect a deleted card from one of its
  older rows.

Per finding:

- **D1** — `getDescendants` reduces once to `newestVisible` and the recursion
  (`descendantsOf`) walks that list, so a stale row naming the deleted card as
  parent no longer drags a moved-away card into `CTRmv`'s `toMarkDeleted`.
  Already-deleted descendants drop out too (no redundant second deletion row).
  The card lookup that starts the walk also went from "first row with this id"
  to the newest visible one.
- **D2** — `mergeCards` gathers `childrenOfCurrent`/`childrenOfOther` from
  `newestVisible data`, which fixes both halves at once: no fresh row is
  emitted for a stale child row (which, being newest after the write, would
  have yanked a moved-away child back under the merged card — and undeleted a
  deleted one), and the `firstPos`/`lastPos` offsets are computed only from
  children the user can see.
- **D10 — decision: the `toAdd` limb is removed** (`toAdd = []`), with the
  reasoning recorded in the comment on `theirDeletionsToRemove`. Rationale:
  the limb was not merely dead, it was wrong in the direction that matters.
  It filtered `theirDeletionCards` down to ids *not* in `idsOfConflicts`,
  which is the set they were derived from, so it was provably `[]` — but had
  the filter been inverted it would have staged an undeleted row built from
  the **pre-deletion synced row**, i.e. the content from before our edit. The
  port layer stamps a staged row as it writes it, so that row would have
  become both the newest row for the card (what the user sees) and the newest
  unsynced row (what `cardDelta` diffs), silently reverting the local edit
  that delete-vs-edit resolution exists to preserve. What is left is
  sufficient and already correct: dropping the pre-deletion synced row leaves
  their deletion as the only synced row and our edit as the only unsynced one,
  which is exactly the pair `cardDelta` turns into `UndelOp` +
  `UpdOp{our content}` — edits beat deletions, matching the intent stated on
  the `ourDeletionTimestamps` limb. The auto-resolve branch in
  `cardDataReceived` still fires, because `toRemove` is non-empty.
- **S9** — `conflictToTree`'s `toDict` maps `newestPerId` instead of the raw
  rows, so `Dict.fromList`'s last-in-wins can no longer pick a stale row.
  Selected conflict versions still override (`Dict.union` prefers them) even
  when a local row is newer, which is the point of the union.
- Adjacent, same family: `getPosition` now dedupes before dropping deleted
  rows (it was the one place D1 cited as "dedupes correctly", but its filter
  ran first), and `toTrees` is expressed in terms of `newestVisible` —
  behaviour-identical, it was the definition the helper was extracted from.

Tests (`tests/DataTest.elm`, ADR-0001 seam 1, driven through `localSave` /
`cardDataReceived` / `conflictToTree` and the `DBChangeLists` JSON):

1. *deleting a card leaves a card that was moved out of it alone* (D1) —
   red before: `toMarkDeleted` also carried `x` with `parentId = "b"`.
2. *deleting a card marks its whole visible subtree deleted* — guards the
   dedupe against over-pruning real descendants (`["a","x","y"]`).
3. *merging cards skips a child whose newest version is deleted* (D2) — red
   before: two rows for the deleted child `d` (one with `deleted = 0`,
   resurrecting it under `c`) and the live child `e` offset to position 3
   instead of 2.
4. *a remote deletion conflicting with a local edit drops only the
   pre-deletion row* (D10) — pins `toAdd = []`, `toRemove = ["1000:0:orig"]`
   and `hasConflicts == False` (no user prompt for delete-vs-edit).
5. *the conflict tree is newest-version-wins, whatever order the rows arrive
   in* (S9) — asserts the same tree from a row list and from its reverse; red
   before on the first of the two.

Verification (rebased on `selfhost` at `34bfc37`): `bun run test:elm` 12/12
(8 DataTest + 4 SessionTest, was 7), `bun test` 28/28 across 4 files,
`bun run newbuild` succeeds, `node config-check.js` exit 0.

## Comments

- Red-first evidence, before the `Doc/Data.elm` changes: 3 failures (tests 1,
  3, 5 above), with the diffs quoted in the Answer. Test 2 and the D10 pin (4)
  passed from the start by construction — test 2 is a don't-over-prune guard,
  and D10's limb was provably `[]`, so pinning the current output is what makes
  its removal *provably* behaviour-preserving.
- `tests/DataTest.elm` now imports `Outgoing` to unwrap `SaveCardBased`'s
  payload from `cardDataReceived`'s `outMsg`. elm-test compiles and runs a
  suite that imports a `port module` fine (checked before relying on it), so
  the delete-conflict path needed no new test-only export. Its `ChangeLists`
  decoder also decodes `toRemove` as `List String` now (stamps,
  `"ts:counter:hash"`); the three pre-existing tests are unaffected.
- Out of scope, seen while in the file and left to their owners: `localSave`'s
  `CTUpd`/`CTMov`/`CTMrg` newest-row lookups duplicate `getCardById`
  (harmless, already correct); the auto-resolve condition in
  `cardDataReceived` still tests `toAdd`/`toMarkSynced`, both of which
  `resolveDeleteConflicts` now always leaves empty (ticket 06 owns D3 in that
  function); `mergeRestoreData` re-deleting deleted cards is D9/ticket 12;
  position rebalancing is D8/ticket 11.
- `docs/CODE_REVIEW.md` is left as the catalog as found, matching how tickets
  02/03/07 resolved.
