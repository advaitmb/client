# 11: Rebalance fractional card positions

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D8.

**What to build:** Card order stays stable no matter how many times cards are
inserted at the same spot. Midpoint insertion halves the gap each time (~50
inserts exhaust Float precision, after which siblings tie and order becomes
row-order-dependent). Strategy: when the computed gap between neighbors falls
below a safe epsilon, emit rebalanced positions for the affected siblings
(fresh version rows through the normal save path) instead of a degenerate
midpoint. Also address the rapid-insert case where two inserts mint identical
positions before the Dexie round-trip refreshes.

## Acceptance criteria

- [x] Failing test first (seam 1): repeated same-spot inserts (>60) keep
      strict ordering; positions after rebalance are well-spaced.
- [x] Rapid consecutive inserts can't mint identical positions.
- [x] Rebalance rows sync like any other move (delta `mov` ops).
- [x] CI green.

## Answer

Landed in commit `34d92c7` on `selfhost` (claim: `a67d933`).

`getPosition` is now `placeCard`, which answers a wider question: not just
"what number does this card get" but "and which of its siblings have to move to
make room". Two halves, one per symptom.

### Half 1 — the gap floor, and what a rebalance lays down

**Epsilon: `positionGapFloor = 1.0e-6`, an absolute floor on the gap, checked
before the midpoint is taken.** Not relative, and not derived from the
neighbours' magnitude. Reasoning:

- The cliff being avoided is `fl((l + r) / 2) == l`, which happens once
  `r - l` reaches `ulp l` = `l * 2^-52`. For any position below 2^32 that is at
  most `2^-21` ≈ 4.8e-7, so 1e-6 is above the cliff for every position this
  model can hold — and positions here start life as sibling indices (`fromTree`
  uses `toFloat idx`) and grow only by whole-number merge offsets, so they stay
  many orders of magnitude below that bound. At realistic magnitudes (< 10^4) a
  1e-6 gap still has ~10^5 representable Floats inside it.
- An absolute floor also catches the case a relative one misses: after a
  rebalance the leftmost sibling sits at 0, and `(0 + g) / 2` halves *exactly*,
  all the way down to Float's denormals (~1e-308). Precision never fails there,
  but a gap of 2^-500 is not an order anyone should be storing. The floor is a
  statement about the model, not about Float.
- It is deliberately generous, not minimal: at the unit spacing below, ~20
  same-spot inserts fit into one gap before the next rebalance. A tighter floor
  (1e-12, say) would double that at no benefit; a looser one would rebalance
  more often than it needs to.

**Spacing: `positionSpacing = 1.0`.** A rebalance renumbers the whole sibling
list onto `0, 1, 2, …` with the new card's slot left free — the same whole
numbers a freshly imported tree gets, so a rebalanced row is indistinguishable
from an imported one, and every neighbouring gap is 10^6 times the floor. A
wider grid buys only `log2` more inserts per rebalance (10x the spacing is 3
more inserts) in exchange for positions that no longer read as the card's index,
so it isn't worth it.

**Trigger point: the placement itself, not a background pass.** `placeCard`
takes the midpoint when `sibRight.position - sibLeft.position >=
positionGapFloor` and calls `rebalance` when it doesn't. So the renumbering is
part of the save the user's own insert (or move, or paste) already makes: no new
message, no new code path, no timer. Only the siblings that actually change
position get a row — a sibling already sitting on its new number has nothing to
say, and staging it anyway would write an unsynced row whose delta carries no
ops (D9).

### Half 2 — rapid inserts: the model remembers what it staged

**Chosen: carry the staged rows in the model, not tie-break-and-repair.** The
ticket offered "tie-break deterministically, or detect-and-rebalance on the next
save". Both were rejected as the primary fix, because neither makes an identical
position unmintable:

- The position of a new card is a pure function of (sibling rows, index). Two
  saves in the same window see the same rows, so *any* deterministic function
  gives them the same answer. The only escape is to make the answer depend on
  something else — a hash of the card id, say — and that orders two cards the
  user created in sequence by hash rather than by when they made them. Wrong
  answer to the wrong question.
- Detect-and-rebalance repairs the tie one save later. In between, the DB holds
  two siblings at one position and the tree materializes in Dexie row order,
  which is the exact instability D8 is about.

So `localSave : String -> CardTreeOp -> Model -> ( Model, Enc.Value )`: it
returns the model as well as the save, and the model carries `StagedRows` — the
rows just handed to the port layer, one per card id, until `cardDataReceived`
clears them (the DB has spoken; whatever was staged is either in the rows it
sent or superseded). `placeCard` places against `visibleWithStaged`, so the
second insert of a double keystroke sees the first one's row and lands after it.
`Page.App.localSave` stores the returned model, which is all the plumbing the
caller needed.

Two supporting points fell out of it:

- **An out-of-range index is an append.** `Page.Doc` derives `idx` from the
  *working tree*, which is a save ahead of these rows whenever one is in flight,
  so `idx` routinely points past the end of the sibling list here. It used to
  fall through to the no-siblings case and mint position **0** — a straight
  collision with the first sibling, and the actual behaviour behind "hold Enter
  and watch the order scramble". `clamp 0 (List.length siblings) idx` makes it
  an append. The caller's `999999` append sentinel clamps to the same place, so
  its special case is gone.
- **Tie-break as defence in depth, not as the fix.** `placeCard`'s sibling sort
  and `treeHelper`'s are now `(position, id)`, a total order. Local saves can no
  longer mint a tie, but rows written by another client still can, and sorting
  on position alone leaves that order up to Dexie.

### Interactions checked

- **`toDelta`'s empty-ops filter (ticket 12).** Rebalance rows differ from their
  synced base in `position`, so `cardDelta` emits a real `MovOp` and the row
  survives the filter — that is the assertion in test 4. The one case where a
  rebalance row *would* produce no ops (its grid position happens to equal the
  synced row's, while the unsynced row it was built from differs) is a genuine
  correction of the local row, and 12's filter correctly drops the delta rather
  than pushing an empty one.
- **`sameCardState` (ticket 12).** Compares `position`, so a snapshot taken
  before a rebalance restores the pre-rebalance positions. That is what a
  restore is for; nothing to reconcile.
- **The staged rows are not part of the version log.** They carry no stamp
  (`Card ()`), and nothing but `placeCard` reads them: they cannot be pushed,
  cannot classify a card as synced or unsynced, and cannot reach a delta. The
  type's docstring says so.

### Adjacent refactor, same commit

`localSave`'s limbs are now one funnel, `localChanges : … -> Result (List
SaveError) DBChangeLists`, so there is a single place that turns changes into
either a save or an error payload — which is what let `localSave` stage the rows
it emits without repeating itself six times. Two provably dead things went with
it: `CTUpd`'s `Just []` limb (`Maybe.map (\c -> [ x ])` never yields `Just []`)
and the `mergeUp`/`mergeDown` wrappers, now that `mergeCards` takes the flag.

### Tests

`tests/DataTest.elm`, ADR-0001 seam 1, 7 new tests — 36 elm tests in total. All
7 were red first; the two 61-insert ones only went red after the fixture's first
card moved from position 0 to position 1, which is itself the finding above:
halving from exactly 0 never runs out of mantissa, halving from 1 runs out after
~52 inserts. Red output on the pair was `62` cards holding `54` distinct
positions, with `a` sitting ninth in its own sibling list.

1. *sixty-one inserts at the same spot keep the order they were made in* — each
   insert a full round trip (`localSave` → `applySave` → `cardDataReceived`), so
   every one sees what the last one wrote; asserts the materialized tree's
   sibling order.
2. *…leave no two siblings sharing a position* — the other half of the same
   statement, read off the version log by the test's own newest-row-per-id.
3. *an insert into a gap too small to split rebalances the siblings onto whole
   numbers* — pins the grid exactly: `[ ("n", 1), ("b", 2), ("z", 3) ]`, with
   the sibling already on its number left alone.
4. *a rebalanced sibling syncs as an ordinary move* — the `mov` ops on the wire
   after that save, and none for the sibling that didn't move.
5. *a second insert made before the DB echoes the first lands after it* — the
   double keystroke; red before at position 0, colliding with the first card.
6. *two inserts at the same index before the DB echoes get different positions*
   — red before with both at 1.
7. *a move into a gap too small to split rebalances too* — the placement's other
   caller.

### Verification

Rebased on `selfhost` at `b9cb77f`: `bun run test:elm` 36/36, `bun test` 51/51
across 8 files, `bun run newbuild` succeeds, `node config-check.js` exit 0.
`elm-format --validate` reports the same three files as before the change (the
repo's docstrings use `*emphasis*` where elm-format 0.8.8 wants `_emphasis_`);
diffing each file against its formatted copy shows no new deviation from the new
code. CI green on `selfhost`: run
<https://github.com/advaitmb/client/actions/runs/33070405652> (`34d92c7`, the
code) and <https://github.com/advaitmb/client/actions/runs/33070525250>
(`78fbce3`, the tracker).

## Comments

- **Out of scope, adjacent, and now cheaper to fix: a save based on stale card
  rows can revert a move or an edit.** `CTUpd`/`CTMov`/`CTRmv`/`CTMrg` still
  build their row from `data`'s newest row, not from `visibleWithStaged`, so
  move-then-edit inside one round trip writes an update row carrying the *old*
  position and undoes the move. Same family as D8's second half, same window,
  but it is about content and parentage rather than positions, so it is not D8
  and is not fixed here. The staging memory this ticket added is exactly what a
  fix would use — `newestRowOf id data` becomes a lookup in
  `visibleWithStaged staged data` — but that changes four save limbs at once and
  wants its own red tests. `StagedRows`' docstring deliberately says the rows
  exist for placement only, so nothing silently depends on the narrower scope.
- **The staging memory is cleared by any card-rows echo, not just its own.**
  `cardDataReceived` empties `StagedRows` whenever Dexie emits, so an unrelated
  emission (a websocket pull landing between two inserts) can clear rows whose
  write has not committed yet, putting that pair back on the pre-fix footing. It
  is strictly no worse than before and the window is a fraction of a save; the
  precise alternative — drop a staged row only once the received rows contain
  it — works for inserts (new ids) but not for moves (the id is always there),
  so it would trade a narrow race for an inconsistent rule.
- **`restore` does not stage its rows.** A restore writes positions through
  `getRestoredData`, not `localSave`, so an insert made between a restore and
  its echo places against pre-restore positions. Same window, and the same
  fix shape would apply, but restores are user-initiated and modal (the history
  view is open), so the two cannot realistically overlap.
- `docs/CODE_REVIEW.md` left as the catalog as found, matching tickets
  02/03/04/05/06/07/10/12.
- `CONTEXT.md` gains one glossary entry, **Rebalance** — the term now appears in
  code, tests and commit messages, and the floor is the kind of number a reader
  will want to look up.
