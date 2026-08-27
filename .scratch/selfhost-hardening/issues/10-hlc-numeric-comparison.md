# 10: Numeric HLC stamp comparison in JS

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D7 · Decision: ADR-0005 §3.

**What to build:** JS-side code that orders or maxes HLC stamps
(`"ts:counter:hash"`) agrees with Elm's numeric ordering even when a
multi-card save mints many stamps in one millisecond (unpadded counter:
`…:10:x` currently sorts before `…:9:y` as a string). Fixes too-low pull
checkpoints (redundant re-pulls) and stale backup selection.

## Acceptance criteria

- [x] One exported stamp-comparison helper (extracted per ADR-0001 seam 2),
      unit-tested including the `9` vs `10` counter case and equal-timestamp
      ties.
- [x] Checkpoint computation, delta max, and backup selection all use it —
      no `.sort()` default-order or lodash `_.max` on stamp strings remains.
- [x] CI green.

## Answer

Landed in `34bfc37` (implementation) and `0882f42` (self-review tidy-up) on
`selfhost`.

**New module `src/shared/stamps.js`** (ADR-0001 seam 2 — pure, importable, no
Dexie and no WebSocket). One comparator, three helpers built on it:

| Export | Contract |
|---|---|
| `compareStamps(a, b)` | Total order: numeric timestamp, then numeric counter, then hash (JS `<`, which is Elm's `compare` on `String`). Negative / 0 / positive. |
| `maxStamp(stamps)` | Newest stamp, or `undefined` for `[]` — mirrors `UpdatedAt.maximum : List UpdatedAt -> Maybe UpdatedAt`. |
| `computeCheckpoint(rows)` | Newest stamp among rows with `synced: true`, else the zero stamp `"0"`. |
| `newestVersionPerId(rows)` | One row per card id, the newest, newest card first. |

Parsing mirrors `src/elm/UpdatedAt.elm` exactly: three colon-separated parts,
timestamp and counter integers as strict as Elm's `String.toInt` (optional
sign, digits only — no `1.5`, no `1e3`), plus Elm's special encoding of
`UpdatedAt.zero` as the bare `"0"` → `{timestamp 0, counter 0, hash ""}`.
`ZERO_STAMP` and `parseStamp` stay private; the exported surface is the four
functions above.

**Call sites replaced in `src/shared/doc.js`** (all four stamp orderings the
review found; the Elm side was already correct and is untouched):

| Was | Now |
|---|---|
| `hlc.recv(_.max(data.d))` — `pushOk` (delta max, `:261`) | `hlc.recv(maxStamp(data.d))` |
| `getChk(treeId, cards)` — `.sort().reverse()[0]` (`:809`), called from `loadCardBasedDocument` | `computeCheckpoint(loadedCards)`; `getChk` deleted |
| `getChk(TREE_ID, cards)` — `doPull` (`:283`) | `computeCheckpoint(cards)` |
| `_.chain(cards).sortBy('updatedAt').reverse().uniqBy('id')` — `saveBackupToImmortalDB` (`:823`) | `newestVersionPerId(cards)` |

**Grep proof** (`.sort(`, `_.max`, `_.min`, `sortBy`, `maxBy`, `minBy`,
`orderBy` across `src/`, `tests/`, root scripts):

```
src/shared/stamps.js:8    (comment: never `.sort()` or `_.max` on stamps)
src/shared/stamps.js:55   [...rows].sort((a, b) => compareStamps(...))   <- the numeric comparator
src/shared/doc.js:845     sortBy('position')   <- numeric card positions, not stamps
config-check.js:5,6       Object.keys(...).sort()   <- config key names
```

No default-order `.sort()` or lodash extremum over stamp strings remains.

**Tests** — `tests/stamps.test.ts`, 9 tests at seam 2 (bun test): the `9` vs
`10` counter case; equal timestamp + counter broken by hash; mixed timestamps
(a later millisecond beats a high counter in the earlier one); the zero stamp;
unparseable stamps; `maxStamp` over one save's worth of stamps;
`computeCheckpoint` over a realistic 16-row set (a 12-card save minting
counters 0..11 inside one millisecond, on top of an older synced save, plus
newer unsynced local edits) and its nothing-synced-yet fallback;
`newestVersionPerId` keeping the two-digit-counter row.

**Verification** (post-rebase onto ticket 05's `ab4a495`):

| Check | Result |
|---|---|
| `bun test` | 28/28 across 4 files (stamps 9, markdown 9, textarea 7, config-check 3) |
| `bun run test:elm` | 12/12 |
| `bun run newbuild` | succeeds; `stamps.js` is in the minified `web/doc.js` bundle |
| `bun run config-check` | exit 0 |
| CI | run 33065087066 green on `34bfc37`, run 33065366990 green on `0882f42` |

## Comments

- **Red-first transcript.** Each helper was extracted from `doc.js`
  *verbatim* first, so the failing test proves the shipped bug at the seam,
  not just the new code:

  ```
  compareStamps, string order (the old `.sort()` behavior):
    a higher counter in the same millisecond is newer   Expected: > 0   Received: -1
    stamps sharing a millisecond and a counter …hash    Expected: > 0   Received: 0
    the zero stamp '0' …                                TypeError (Elm's "0" is not 3 parts)
    an unparseable stamp …                              TypeError

  maxStamp as `_.max(stamps)` (doc.js:261):
    Expected: "1755000000000:10:bbb"   Received: "1755000000000:9:ccc"

  computeCheckpoint as getChk's `.sort().reverse()[0]` (doc.js:809):
    Expected: "1755000000123:11:ph6oyrqzgpbo"   Received: "1755000000123:9:ph6oyrqzgpbo"

  newestVersionPerId as `sortBy('updatedAt').reverse().uniqBy('id')` (doc.js:823):
    Expected {"card-a": "tenth edit"}   Received {"card-a": "ninth edit"}
  ```

  The checkpoint line is the user-visible D7 consequence: two rows of every
  12-card save were re-pulled from the server on every load. The last line is
  the stale-backup consequence: the ImmortalDB backup held the 9th edit of
  card-a while the 10th was the live one.
- **Two behaviors are new, beyond ordering** (both flagged in the commit
  message):
  1. `computeCheckpoint` returns `"0"` — Elm's `UpdatedAt.zero` encoding — for
     a document that has rows but nothing synced yet. `getChk` returned
     `undefined` there (`[].sort().reverse()[0]`), which went into
     `wsSend("pull", [treeId, undefined])`. Only the `cards.length === 0` case
     ever reached its `'0'` branch.
  2. A stamp that cannot be parsed orders below every real stamp instead of
     wherever its raw string fell. Needed because rows come straight from
     Dexie and `Array.prototype.sort` is undefined for a non-total comparator;
     it also means a garbage row can never win a checkpoint or a backup
     selection.
- **`getChk`'s `treeId` parameter was unused** — both call sites already
  queried Dexie by `treeId`, so `computeCheckpoint` takes only rows.
- **Not stamp ordering, deliberately left alone:**
  - `dexie.trees.where('updatedAt').belowOrEqual(data.d)` (`doc.js:293`) —
    `trees.updatedAt` is a `Date.now()` number, not an HLC stamp.
  - `cards.map(c => c.updatedAt.split(':')[0]).reduce((a, b) => Math.max(a, b))`
    (`doc.js:551`, snapshot id) — already numeric via `Math.max`, and the max
    timestamp component equals the timestamp of the max stamp. Its
    `reduce`-without-seed throws on an empty card set: robustness, ticket 23.
  - `sortBy('position')` in `treeHelper` — numeric card positions.
- `newestVersionPerId` is the JS half of the newest-per-id rule; ticket 05
  owns the Elm-side scans (ADR-0005 §1). No overlap in the files touched.
- D6/E8/S5–S8 in `doc.js` were left to their owning tickets.
