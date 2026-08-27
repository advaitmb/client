# 29: Saves built from stale rows can revert a concurrent move/edit

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 11 (resolved — its `StagedRows` memory is the foundation)

**Covers:** new finding from ticket 11's resolution (not in CODE_REVIEW.md).
Same class as D8's second half, but for content/parentage instead of
positions.

**What to build:** `CTUpd`/`CTMov`/`CTRmv`/`CTMrg` in `Doc/Data.elm` build
their new row from `data`'s newest row for the card, which lags a save
already handed to the port layer. Move-then-edit within one Dexie round trip
writes an update row carrying the OLD position/parent — silently reverting
the move (and symmetrically for the other op pairs). Ticket 11 added
`StagedRows` (cleared on `cardDataReceived`) and `visibleWithStaged` for
placement; extend the same memory to the four op limbs (a
`newestRowOf id` lookup that consults staged rows first). Read ticket 11's
`## Answer` and `## Comments` first — including its noted limitation that
staging is cleared by ANY rows echo (improve if cheap, else keep and
document).

## Acceptance criteria

- [x] Red first: move card then edit it before the rows echo → the edit row
      keeps the new parent/position; symmetric tests for the other limbs
      where meaningful.
- [x] `StagedRows`' docstring updated (no longer "placement only").
- [x] Full suite + build green; CI green.

## Answer

Landed in commit `5319ac4` on `selfhost` (claim: `1c993bd`).

One sentence covers all four limbs: **a save is built from the newest state of
a card, and the newest state can be a row the DB has not stamped yet.** Ticket
11 gave the model that memory for one question ("where does the next card
go"); this ticket makes it the answer to every question a save asks about a
card that already exists.

### What each limb was writing, and what it writes now

The version log `Doc.Data` holds is refreshed only by the Dexie liveQuery —
one round trip *after* the save that changed it. Every op below carries the
card's *whole* state in the row it writes, so inside that window each was
writing back the state the previous save had just changed:

- **`CTUpd`** took `newestRowOf id data` and replaced its content, so an edit
  made after a move carried the pre-move `parentId`/`position`: the update row
  is the newest row of the card, so the move was silently undone. Now
  `stagedOrNewestRow id staged data`.
- **`CTMov`** took the same row and replaced its position/parent, so a move
  made after an edit carried the pre-edit *content* — the symmetric revert.
  Same lookup.
- **`CTRmv`** walked `data` for the subtree, so it missed a child just moved
  *into* the card being deleted (left parented to a deleted card) and marked a
  child just moved *out* of it deleted (CODE_REVIEW.md D1, through the staging
  window instead of through a stale row). It now walks `visibleWithStaged` —
  which also means the deletion rows carry the staged content rather than
  re-stating an outdated one.
- **`CTMrg`** built the joined content from `data`, dropping an unechoed edit
  of either card, and gathered the merged card's children from `newestVisible
  data`, so a child just moved into it got no re-parenting row at all — and
  the same save deletes its parent. Both cards now come from
  `stagedOrNewestRow`, and `mergeCards` takes the visible cards as an argument
  (`visibleWithStaged staged data`) rather than deriving them from the log.

`CTIns`/`CTBlk` needed nothing: they build brand-new rows, and their placement
was already staged-aware.

### Two shapes, not four

`stagedOrNewestRow : String -> StagedRows -> CardData -> Maybe (Card ())` — the
staged row for that id if there is one, else `newestRowOf` mapped through
`asUnsynced`. A staged row is the newer of the two by construction, and it is
already an unsynced, stampless row, so the four limbs stopped calling
`asUnsynced` themselves: `mergeCards` now works in `Card ()` throughout.

`visibleWithStaged` (ticket 11's) is the multi-card half, and it grew a second
caller shape: `descendantsOf` now takes `List (Card a)`, so `getDescendants`'
reduce-then-walk wrapper is gone — its one caller passes the staged-aware view
directly. Nothing else in the module reduced raw rows for these ops, so
ADR-0005 §1 still holds by construction.

### Limitation #2: a rule that is cheap *and* provable, for half the cases

Ticket 11 cleared the whole staging memory on any card-rows echo and noted the
precise alternative ("drop a staged row only once the received rows contain
it") as working for inserts but not for moves. There is a rule that is correct
for exactly the half it can be correct for, and it is the negative one:

- The echo is fired by **any** write to the open document's cards (a websocket
  pull landing mid-save included) and carries that document's **whole** card
  set. So an id the echo has **no row for at all** cannot have been written
  yet: the staged row is still the model's only knowledge of that card, and it
  survives. `unwrittenStaged` is that filter. This is what a pull landing
  between two rapid inserts used to break, putting the pair back on the pre-D8
  footing.
- For an id the echo **does** have rows for, "is ours among them?" cannot be
  answered from state alone, and no cheap rule can make it answerable: a
  staged row carries no stamp, so a newest received row that says something
  else is *either* our write still in flight *or* our write already superseded
  — by a collaborator's version, or by a fast-forward. Keeping it on that guess
  would leave a phantom row overriding the DB's own answer for every save until
  the document is closed; clearing it costs a fraction of one save. Those rows
  are still dropped, and the docstring says why.

Stamping staged rows at stage time would close the remaining half properly
(compare the received newest stamp against it), but `localSave` has no clock —
it would mean threading `Time.Posix` through `Page.App`/`Page.Doc` for a race
measured in one Dexie round trip. Not worth it here; recorded in the comments.

### Restore staging (#3): still not staged, deliberately

`restore` writes through `getRestoredData`, returns only messages, and would
have to return a model for its rows to be staged — a signature change reaching
`Page.App`. Ticket 11's argument stands unchanged: a restore is modal (the
history view is open, no editing behind it), so the pair cannot realistically
overlap. Left as a comment, not code.

### Interactions checked

- **`toDelta`'s empty-ops filter (ticket 12).** These rows now differ from
  their synced base in *more* fields, never fewer, so nothing new can produce
  an op-less delta. The one row that changed shape is `CTUpd` after a delete
  (below), which pushes a `del` rather than an `upd`.
- **Deleted cards.** `stagedOrNewestRow` does not filter deleted rows — same as
  `newestRowOf` — so an edit that lands after a delete inside one window now
  writes a *deleted* row with the new content instead of resurrecting the card
  with its pre-delete parent. That is a behaviour change, in the direction of
  the delete the user just made, and it is pinned by a test.
- **The staged rows still reach nothing else.** Only `localSave` and
  `cardDataReceived` read the field (everything else destructures `_`), so a
  staged row cannot be pushed, cannot classify a card's sync state, and cannot
  reach a delta — even now that it can outlive one echo.
- **Document switch.** `Page.App.init` builds `Data.emptyCardBased` per opened
  document and `Main` re-inits on the route change, so surviving staged rows
  cannot cross into another document.
- **Hot path.** `CTUpd` still touches one card's rows unless a staged row
  answers first; `CTRmv` does one `newestPerId` pass where it used to do two
  sorts.

### Tests

`tests/DataTest.elm`, ADR-0001 seam 1, 9 new tests — 52 in the file's suite at
the time of writing (75 with ticket 14's, which landed alongside). 8 were red
first; the 9th (the isolation pin) must pass either way, which is its point.
One helper, `savedAfter firstOp secondOp rows`, is the window itself: two
`localSave`s with no `cardDataReceived` between them.

1. *an edit made before the DB echoes a move keeps the new parent and
   position* — the headline. Red: `parentId = Nothing, position = 3`, the
   pre-move root slot.
2. *a move made before the DB echoes an edit keeps the new content* — red with
   `content = "Original"`.
3. *removing a card after moving a child out of it leaves the child alone* —
   red with `["a","x"]`.
4. *removing a card after moving a child into it marks the child deleted too* —
   red with `["a"]`.
5. *merging a card after editing it keeps the edit* — red with
   `"Current\n\nOther"`.
6. *merging carries along a child moved into the other card before the echo* —
   red with only the merged card staged, the child left under the card the save
   deletes.
7. *a save for one card is not built from another card's staged row* — the
   isolation pin: green before and after.
8. *an edit of a card deleted before the echo does not resurrect it* — pins the
   deleted-row behaviour above; red with `deleted = 0`.
9. *an echo with no row for a staged card does not forget it* — the echo rule:
   a collaborator's edit of `a` arrives while `b`'s insert is in flight, and the
   next insert must still land between them. Red at position `1`, colliding
   with `b`.

### Verification

Rebased on `selfhost` at `6d1bb34`: `bun run test:elm` 75/75, `bun test` 58/58
across 9 files, `bun run newbuild` succeeds, `node config-check.js` exit 0.
`elm-format` could not be run in this session (the proxy blocks the npx
download and it is not a repo dependency or a CI gate); the new code follows
the file's existing formatting, checked hunk by hunk against it. CI green on
`selfhost`: run
<https://github.com/advaitmb/client/actions/runs/33072207719> (`5319ac4`, the
code).

## Comments

- **Out of scope, found while writing the merge tests: merging *down* into a
  childless card orphans the other card's children.** In `mergeCards`, the
  `not isUp` branch cases on `( lastPosOfCurrent, firstPosOfOther )` but its
  two one-sided limbs are the `isUp` branch's, unswapped: `( Just _, Nothing )`
  (current has children, other has none) maps an empty list, and
  `( Nothing, Just _ )` — current childless, other *has* children — returns
  `[]`, so those children get no re-parenting row while the same save deletes
  their parent. The `isUp` branch, where the pair is
  `( lastPosOfOther, firstPosOfCurrent )`, is correct. It is a plain
  case-analysis bug, nothing to do with stale rows, so it is not fixed here;
  it wants its own ticket and its own red test (merge a childless card up into
  one with children, and vice versa).
- **The remaining half of the echo race wants a stamp, not a better guess.** If
  `localSave` stamped each staged row with the local clock, `cardDataReceived`
  could drop exactly the rows the DB has moved past (received newest stamp >
  staged-at) and keep the rest — correct for moves and edits too, not just for
  ids the echo has never heard of. The cost is a `Time.Posix` argument threaded
  through `Page.App`/`Page.Doc` to every `localSave` call site, for a window of
  one Dexie round trip. Deliberately not taken.
- **`(staged, data)` is a data clump.** Four functions in `Doc.Data` now take
  the pair (`localChanges`, `placeCard`, `stagedOrNewestRow`,
  `visibleWithStaged`), which is a type wanting to be born — "the document as a
  save must see it". Not introduced here: all four are module-internal, and the
  one honest alternative (reduce to the staged-aware newest-per-id list once,
  in `localChanges`, and hand *that* to every limb) makes `CTUpd` — the
  keystroke path — sort the whole version log where today it touches one card's
  rows. Worth revisiting under ticket 25 (perf), where the sort can be measured
  rather than guessed at.
- **A save the port layer fails to write now lingers in the staging memory.**
  `applyCardBasedSave` alerts the user and writes nothing on a Dexie error, so
  the staged rows for ids that never reached the table are kept indefinitely
  (until the document is closed). That is the same state the screen is already
  in — the working tree shows cards the DB does not have — and the failure is
  loud, so keeping the two consistent is the better of the two behaviours.
- `docs/CODE_REVIEW.md` left as the catalog as found, matching tickets
  02/03/04/05/06/07/10/11/12.
- `CONTEXT.md` gains one glossary entry, **Staged row**: ticket 11 introduced
  the concept, this ticket makes it the rule every save follows, and it is now
  a term a reader meets in `Doc.Data`, the tests and two commit messages.
