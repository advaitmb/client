# 25: Data-layer performance (Dict-keyed hot paths)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 05, 06, 12 · **Owner decided (2026-08-27):** in scope,
scheduled last — after all correctness tickets are green.

**Covers:** CODE_REVIEW.md P1, P2, P3, P4, P5.

**What to build:** Multi-thousand-card documents stay responsive: the
per-save O(n²) hot paths (tree materialization, sync-state grouping, delta
generation, descendant scans) move to Dict-keyed structures (by id /
children-by-parentId); sort-to-take-max becomes single-pass max; the
duplicated per-card-recompiled search regex is unified and hoisted; the
triplicated save-card logic collapses; the misleading lazy-view key is fixed.
Behavior must not change — the correctness tickets' tests (05, 06, 12) are the
safety net, which is why they block this.

## Acceptance criteria

- [x] All existing `Doc.Data` tests pass unchanged.
- [x] Demonstrated complexity win (benchmark or op-count reasoning in
      Comments) on a synthetic multi-thousand-card document.
- [x] P3/P4/P5 duplications removed.
- [x] CI green.

## Answer

Eleven commits on `selfhost` (claim: `e9e241a`):

| # | commit | what |
|---|---|---|
| 1 | `bae8a5f` | P1 — the tree is materialized from a children-by-parent index |
| 2 | `9878030` | P1 — the subtree walk reads the same index; its ids go into a `Set` |
| 3 | `a6d1656` | P1 — the version log is grouped by card id in one pass, not pairwise |
| 4 | `c630d53` | P1 — deltas are built from the grouped rows |
| 5 | `91e55ed` | P2 — `UpdatedAt.maximum` is a single pass, and the two indicator times use it |
| 6 | `dc05a29` | P1 — `Set` membership on the staged-row and push-acknowledgement paths |
| 7 | `cef85f8` | P3 — one `searchFilter`, regex compiled once per search |
| 8 | `be8c2b5` | P5 — `lazy2` on what `treeView` actually renders |
| 9 | `50e38f6` | `tests/DataPerfTest.elm` — the five-thousand-card fixture |
| 10 | `0b20746` | naming pass on the grouping's accumulators |
| 11 | `00b42c8` | P1's twin in `src/shared/cards.js` (the ImmortalDB backup walk) |

**One shape, six times over: the version log was read once per card, where it
only ever needed reading once per pass.** Every fix builds one index (a `Dict`
keyed by parent id, a `Dict` keyed by card id, a `Set` of ids) and then looks
things up in it. Nothing about *what* those functions answer changed — the
group orders `gatherWith` and `List.map .id |> unique` produced are reproduced
exactly, because output order rides on them (conflict versions, fast-forward
stamps, delta order, a merge's re-parented children).

### P1 — four quadratic scans on every save/receive

| where | was | is |
|---|---|---|
| `toTree`/`treeHelper` | one filter of the whole card list per node | `ChildIndex` — `{ roots, byParentId }`, built once per materialization |
| `getSyncState` | `ListExtra.gatherWith` — one `List.partition` of the remaining rows per card id | `groupedByCardId` — one `Dict` fold |
| `toDelta`/`cardDelta` | one filter of the whole log per card id | the same grouping, handed to `cardDelta` |
| `descendantsOf` | a `find` plus a filter over the visible cards per node visited, and then the caller tested every card against the id list it returned | `childIndex` + `subtreeIds`, and a `Set` in `CTRmv` |

Two more of the same shape, found while doing the above and fixed with it:

- **`pushOkHandler` asked which cards a stamp belongs to inside a filter
  predicate**, so `cardIdsFromUpdatedAt` — itself a scan of the whole log — ran
  once per row of the log, per acknowledged stamp. Hoisted out of the predicate
  and turned into a `Set`. This is on the push-acknowledgement path, i.e. after
  every push.
- **`src/shared/cards.js` has `treeHelper`'s JS twin**, and it runs on the same
  trigger: the Dexie liveQuery rebuilds the ImmortalDB backup snapshot on every
  emission, filtering the whole card list once per node. Same fix, a `Map` keyed
  by `parentId`. The sort stays a stable sort by position, so tied siblings come
  out in the order they did before. (`newestVersionPerId` and `maxStamp` in
  `stamps.js` were already linear/`n log n` — the JS side had P2 right.)

### The pre-refactor code did not merely crawl at this size — it threw

`ListExtra.gatherWith` recurses once per *group*, and that recursion is not
turned into a loop, so grouping the version log built one JS stack frame per
card id. Above somewhere between 3,500 and 4,500 cards it overflowed the stack,
which means `cardDataReceived` threw on the **first** card-rows echo: a
document that big could not be opened at all, at any speed.

Pinned down rather than assumed, all three against the pre-refactor code at
4,500 cards:

| probe | result |
|---|---|
| `cardDataReceived`, 4,500 cards (4,500 rows, 4,500 ids) | `RangeError: Maximum call stack size exceeded` |
| `publicDataDecoder`, same 4,500 cards (`toTree` alone, no `getSyncState`) | passes |
| `cardDataReceived`, 4,500 rows but only **10** card ids | passes |

Depth tracks the number of card ids, not the number of rows, and it is not
`toTree`: it is the grouping. The `Dict` fold that replaced it has no recursion.

### The measurement

`tests/DataPerfTest.elm` builds a synthetic ten-ary document (one row per card)
and runs it through the four paths: materialize, classify, push, delete a
subtree. Measured by running that same fixture against the pre-refactor
`src/elm/` (`git checkout e9e241a -- src/elm/`) and against the tip — whole-suite
`elm-test` duration, minus the ~380 ms the 212-test suite costs without the
fixture:

| cards | before | after |
|---|---|---|
| 1,000 | ~275 ms | ~45 ms |
| 3,500 | ~3,010 ms | ~130 ms |
| 5,000 | **cannot finish** (stack overflow, 3 of the 4 tests) | ~210 ms |
| 20,000 | — | ~585 ms |

Before: 3.5x the cards costs 10.9x the time (quadratic would be 12.25x). After:
3.5x the cards costs 2.9x the time, and 4x the cards (5,000 → 20,000) costs
2.8x. The curve changed class, which is the claim; the constants are one run
each on a noisy container and should be read as such.

Op counts for the same document, per card-rows echo, with `n` rows over `c`
cards (`n` = `c` in the fixture):

| | before | after | at 5,000 |
|---|---|---|---|
| materialize the tree | `c²` comparisons | `n` `Dict` inserts + `c` lookups + one sort per sibling group | 25M → ~60k `Dict` ops |
| classify sync state | `n²/2` comparisons, `c` stack frames | `n` `Dict` ops, no recursion | 12.5M → ~60k |
| push (delta per card) | `c·n` comparisons | `n` `Dict` ops, then work proportional to each group | 25M → ~60k |
| delete a 1,111-card subtree | `~2·n` per node visited, plus `n·d` in the caller | one index build, one lookup per node, `Set` lookups in the caller | ~16M → ~70k |

### P2 — sort-to-take-max

`UpdatedAt.maximum` is a `foldl` keeping the newer stamp; `lastSavedTime` and
`lastSyncedTime` (both computed on every data receive, for the save indicator)
call it instead of sorting the whole log and taking the head. Two stamps that
compare equal are equal in all three parts, so which one a max keeps is not
observable.

### P3 — one search filter, one regex

`searchFilter` was two verbatim copies — one in the `SearchFieldUpdated` update
that picks the first matching card to activate, one in `treeView` — and each
compiled the term *inside* the per-card predicate, so every keystroke in the
search field ran the whole document through `Regex.fromStringWith` twice over.
Now one top-level function in `Page.Doc`'s HELPERS with the regex hoisted into
the `Just term` branch. The "subtly different column handling" the review saw is
at the call sites, and stays there: the view drops the root column, the update
does not.

### P5 — the lazy key

`lazy3 treeView (GlobalData.isMac …) …` handed the view an argument it discarded
with `_`. Now `lazy2 treeView model.viewState model.workingTree` — the two
attributes it encodes — and the docstring says that is what it keys on.

### P4 — already done, verified

Ticket 24 collapsed it: `stageCardText` is the one place a card's text is
written into the working tree (`saveCard` is its `andThen`-shaped wrapper), and
`splitCard { into, tailToNewCard }` is the one split idiom. Nothing to do here.

## Comments

- **The prime directive held: no existing test was touched.** The 212 Elm tests
  and 254 TS tests pass unchanged; `tests/DataPerfTest.elm` (5 tests) is added,
  nothing else in `tests/` is modified — `git diff` over `tests/` shows one new
  file and no edits. `bun run newbuild`, `bun run typecheck` and
  `bun run config-check` all exit 0.
- **Every commit was pushed green.** Each of the eleven got its own `ci.yml`
  run on `selfhost` and each came back `success` — the point of working in
  single-move commits here, since a behaviour-preserving refactor that is only
  green at the end cannot say which move broke what.
- **Order is the whole risk in this ticket, and it was the design constraint.**
  Three output orders are load-bearing and each is reproduced deliberately:
  (1) `groupedByCardId` returns groups in the order their ids *first appear* in
  the log, with each group's rows in log order — `gatherWith`'s contract, which
  the conflict versions (`resolveConflicts`'s `toAdd`), the fast-forward stamp
  list and `toDelta`'s tie order all ride on; (2) `childIndex` folds from the
  right so each sibling group keeps its input order, which is what a merge's
  re-parented children (`mergeCards`' `modifiedChildren`) come out in; (3)
  `descendantsOf` still emits depth-first with children in card order. The
  `List.member` → `Set.member` swaps are order-neutral by construction: the
  order comes from the list being filtered, not from the membership test.
- **`newestPerId` was left as a sort.** It is `sortNewestFirst |> uniqueBy .id`
  — `O(n log n)`, not quadratic, so not P1 — and its *output order* (descending
  by stamp) is what `visibleWithStaged` hands to `mergeCards`. A `Dict` fold
  would be a constant-factor win at best (`u ≈ n` for real documents, most cards
  having one or two rows) and would have to re-sort to keep that order. Not
  worth the drift risk in the one function every other reader goes through.
- **`getCardSyncState`'s three sorts per card were left alone.**
  `getOriginals`/`getOurs`/`getTheirs` are each "sort the group, take the head",
  which is P2's anti-pattern — but the group is one card's rows (one to three,
  normally one), not the document, so it is a constant factor per card and not
  the shape P2 names. Fixing it needs an `UpdatedAt.minimum` and a careful
  reading of `getTheirs`' `length > historyLimit` gate; it is a real but small
  win, left on the table deliberately.
- **The conflict-resolution paths were left alone for the same reason.**
  `resolveConflicts` and `resolveDeleteConflicts` do `List.member` over the
  conflicted ids/hashes for every row of the log (`n·c`), which would be one
  more `Set`. They run once, when the document is in conflict and the user
  clicks a choice — not on the save/receive path P1 is about — and they are the
  most delicate code in the file (ADR-0005 §2, tickets 05/06). Not worth it now.
- **`ChildIndex` keeps its roots apart from the `Dict` rather than under a
  sentinel key**, because `Maybe String` is not `comparable` and no string is
  safe to reserve: card ids come from whichever client made the card, so a
  `"__root__"` key is a (remote) collision waiting to happen.
- **`cardDelta` derives its card id from the group's head** rather than being
  handed one, with `Maybe.withDefault ""` for the empty group the grouping cannot
  produce. That is the idiom `getSyncState` right above it already uses for the
  same non-case.
- **The fixture costs the suite ~265 ms**, which is why the naive-walk
  comparison runs at 1,000 cards and not 5,000: the reference *is* the quadratic
  algorithm, and at 5,000 it alone takes ~2.8 s. The equivalence check is the
  test that pins the refactor (indexed walk == filter-per-node walk); the other
  four carry the size.
- **The 20,000-card row of the table is headroom, not a target.** It is not
  committed — `documentSize` is 5,000, the size the ticket named. Worth knowing
  that the paths are still sub-second four times past it.
- **One test-fixture trap worth recording**, since it nearly went into the
  measurements: the first version of the "deleting a card stages its whole
  subtree" expectation computed the expected subtree size by searching the
  document per node — quadratic *in the test*, which at 20,000 cards dominated
  everything the fixture was supposed to be measuring (8.2 s, of which ~7.2 s
  was the helper). It is arithmetic over contiguous id ranges now. When timing
  is the evidence, the assertion has to be cheaper than the thing it measures.
