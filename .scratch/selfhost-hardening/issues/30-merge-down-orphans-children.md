# 30: Merging down into a childless card orphans the source's children

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 29 (resolved)

**Covers:** new finding from ticket 29's resolution (not in CODE_REVIEW.md).

**What to build:** In `Doc/Data.elm`, `mergeCards`' `not isUp` branch has the
`isUp` branch's one-sided limbs unswapped: for
`( lastPosOfCurrent, firstPosOfOther )`, the `( Nothing, Just _ )` case —
current card childless, other card HAS children — returns `[]`, so merging
**down** into a childless card gives the source card's children no
re-parenting rows while the same save deletes their parent. The children
become unreachable (parent deleted, never re-parented). Fix the case
analysis so both merge directions re-parent children symmetrically.

Read ticket 29's `## Answer` first — `mergeCards` now takes the visible
cards and works in `Card ()`; build on that shape.

## Acceptance criteria

- [x] Red first: merge a card with children DOWN into a childless sibling →
      every child gets a re-parenting row targeting the surviving card; the
      materialized tree keeps them.
- [x] Symmetric test for merge up (already-working direction pinned).
- [x] Full suite + build green; CI green.

## Answer

Landed in commit `386f913` on `selfhost` (claim: `18d93cc`; the test/glossary
follow-up from the self-review is `c10ab62`).

Merging is not two operations. **Whether the children of the card merged away
come with it is not a question either direction gets to answer — they always
do; only *where* they land is directional.** The old code asked the question
twice, once per direction, and the merge-down copy answered it wrong.

### The case analysis, limb by limb

Both branches cased on a pair of `Maybe Float`s — the edge of each card's child
positions — and both mapped `childrenOfOther`, the children needing a new
parent. `mergeCards` keeps `currCard` (the card the user is on) and deletes
`otherCard`: the card *below* for a merge down, *above* for a merge up.

Merge up cased on `( lastPosOfOther, firstPosOfCurrent )` and was right in all
four limbs. Merge down cased on `( lastPosOfCurrent, firstPosOfOther )` — the
same pair with the roles swapped — but kept merge up's limbs in merge up's
order, so the two one-sided limbs were exchanged:

| limb | merge up (`lastPosOfOther`, `firstPosOfCurrent`) | merge down (`lastPosOfCurrent`, `firstPosOfOther`) |
|---|---|---|
| `( Just, Just )` | both have children: offset `firstPos - lastPos - 1` ✓ | both have children: offset `lastPos - firstPos + 1` ✓ |
| `( Just _, Nothing )` | other has children, current none: re-parent, positions kept ✓ | **current** has children, other none: re-parents an empty list — wrong limb, right answer by luck |
| `( Nothing, Just _ )` | other childless: `[]` ✓ | **the bug**: current childless, other *has* children → `[]` |
| `( Nothing, Nothing )` | `[]` ✓ | `[]` ✓ |

So exactly one limb was wrong in effect and one in intent. The intent-only one
is harmless because `firstPosOfOther == Nothing` is *equivalent* to
`childrenOfOther == []` (`List.minimum []`), so the list it maps is empty
exactly when that limb is taken — the mirror bug was invisible, which is why
only half the defect showed.

### The bug's cost

`( Nothing, Just _ )` on a merge down is: the surviving card has no children to
sit clear of, and the card being merged away has children to carry. Returning
`[]` staged no re-parenting row for any of them while the same save wrote
`{ otherCard | deleted = True }`. `toTree` builds the tree from the root down
(`treeHelper` filtering on `parentId`), so a child of a deleted card is not
reachable from any root: the whole subtree left the document. It is still in the
`cards` table, and `TreeStructure.Mrg` had already put it on screen under the
surviving card, so the loss showed up on the next data receive — and only a
history restore brought it back.

### The fix

Eight limbs became one offset and one map:

```elm
offset =
    if isUp then
        Maybe.map2 (\lastPos firstPos -> firstPos - lastPos - 1) lastPosOfOther firstPosOfCurrent
            |> Maybe.withDefault 0

    else
        Maybe.map2 (\lastPos firstPos -> lastPos - firstPos + 1) lastPosOfCurrent firstPosOfOther
            |> Maybe.withDefault 0

modifiedChildren =
    childrenOfOther
        |> List.map (\card -> { card | parentId = Just currCard.id, position = card.position + offset })
```

`Maybe.map2` is `Nothing` exactly when one of the two cards is childless, and
that is exactly when there is nothing to sit clear of — so `withDefault 0`
*is* the one-sided case, in both directions, and the childless-other case maps
an empty list either way. Checked limb by limb against the old code: identical
in seven, fixed in the eighth.

Per ticket 11's spacing: one offset for every moved child preserves the gaps
they had between them, and it is the whole-number distance to a slot past (or
before) the surviving card's own children, so nothing lands on a sibling's
position and no gap is narrowed. Merge up still produces negative positions
when the surviving card's first child is at 0 (`-2, -1` in the test) — that was
already true, and positions are an ordering, not an index.

### Tests

`tests/DataTest.elm`, ADR-0001 seam 1, 8 new tests (83 in the elm suite at the
time of writing, 122 with tickets 15/16's, which landed alongside). Two were
red first:

1. *merging down into a childless card re-parents the merged card's children* —
   red with `[ ( "c", Nothing, 0 ) ]`: the two children got no row at all.
2. *the tree after merging down into a childless card keeps the children* —
   the same merge saved, written and read back, red with `( [ "c" ], [] )`: the
   children gone from the document.

The other six pin what was already right, so the collapse above could not
change it quietly: the mirror direction (rows and tree), both-have-children in
both directions (the offsets: `2, 3` down, `-2, -1` up), both-childless in both
directions, and a childless card merged into one with children (the survivor's
own children get no rows — they do not move).

One fixture, `MergeScenario` — the direction plus which card has children —
builds the rows and drives the merge, so a test cannot lay out one scenario and
save another. `mergedRows` sorts by id: the port writes the whole list, so the
order it arrives in says nothing, while the positions in it are the order the
user sees.

### Verification

Rebased on `selfhost` at `0dbe35f`: `bun run test:elm` 122/122, `bun test`
84/84 across 11 files, `bun run newbuild` succeeds, `node config-check.js` exit
0. Reverting only `Doc/Data.elm` to its pre-fix state with the final tests in
place fails exactly the two named above — the red is the fix's, not the
fixture's. `elm-format` is still unavailable in this session (not a repo
dependency, and the proxy blocks the npx download); the new code follows the
file's formatting, checked hunk by hunk.

CI on `selfhost`: run <https://github.com/advaitmb/client/actions/runs/33074332243>
(`386f913`, the code) green.

## Comments

- **`CTMrg`'s direction is a `Bool`, and that is what made this possible.** The
  same flag decides three things — which card is absorbed (`Page.Doc.merge`
  picks prev or next in column), the order the two texts join, and the order
  the two child lists join — and nothing ties the three together. A
  `MergeDirection = MergeUp | MergeDown` would not have caught this on its own;
  what would is what the fix does, making the direction decide only an offset,
  so there is one code path for both directions and no limb to get wrong. The
  `Bool` reaches `Types.CardTreeOp` and `TreeStructure.Msg`, so renaming it is
  a wider change than this ticket; left alone.
- **The optimistic tree and the save now agree by construction, but not by
  shared code.** `TreeStructure.Mrg` concatenates the two child lists (reversed
  for a merge up) and `mergeCards` offsets one past the other; they produce the
  same order, and the tests here pin the save side to the tree the round trip
  materializes, which is the only place the two can be compared. Two
  descriptions of one rule is exactly the shape this bug grew in, but the two
  live on opposite sides of the port boundary (in-memory `Tree` vs version
  rows), and merging them is ADR-0001's seam question, not this ticket's.
- **A merge still does not rebalance.** Ticket 11's floor (`1.0e-6`) applies to
  inserts; a merge shifts positions by a whole-number offset and so cannot
  narrow a gap. But it can carry a *crowded* child list into another card
  unchanged — if the merged card's children were already ~50 same-spot inserts
  deep, they stay that crowded under their new parent. The next insert among
  them rebalances, as it would have before the merge, so there is nothing to
  fix; noted because "merge" now appears in the position story.
- **`docs/CODE_REVIEW.md` left as the catalog as found**, matching tickets
  02/03/04/05/06/07/10/11/12/28/29 — this defect was never in it (found while
  writing ticket 29's merge tests).
- `CONTEXT.md` gains one glossary entry, **Merge**: the survivor keeps its id,
  the absorbed card's children come with it in both directions, and the
  direction decides only the order the texts and the child lists are joined in.
  The last clause is the invariant this ticket restores and it was nowhere a
  reader could find it.
