# 08: JSON import must not race the open document's state

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D5.

**What to build:** Importing a JSON tree never writes another document's
snapshot or timestamps, and works on a fresh session. Today the import batches
two port commands whose order is unspecified, and the card-save handler keys
off a JS-global current-tree id that only the *other* command sets.

## Acceptance criteria

- [x] The save path used by import carries its tree id explicitly (or the two
      commands are strictly sequenced) — no dependence on `Cmd.batch` order or
      a global set elsewhere.
- [x] Fresh-session import (no document ever opened) succeeds.
- [x] Importing while a different document is open leaves that document's
      snapshots/timestamps untouched (test at whichever seam is practical).
- [x] CI green.

## Answer

Landed in commits `e0b0646`, `5bbd202` and `9aeeddb` on `selfhost`
(claim: `b9cb77f`).

**The design: a self-describing payload, for every save — not sequencing.**
`SaveCardBased` now carries `treeId`, and `src/shared/save.js` — the extracted
handler — reads it and never a global. The race is gone by *construction*: the
handler's target is data it was handed, so there is no arrival order that can
make it write the wrong document, and no fresh session in which the target is
missing.

Sequencing the two commands was the alternative the ticket allowed, and it is
weaker on the thing that matters: it would make *this* pair of messages safe by
timing discipline maintained across two files, while leaving the handler's
dependence on an ambient current-document intact for the other five senders of
`SaveCardBased`. A `payload.treeId || TREE_ID` fallback was rejected for the
same reason — it keeps the global live and the invariant unenforceable, which is
the shape of the original bug. Instead `treeId` is **required**: a payload
without one is refused with the existing "Invalid data sent to DB" alert, which
is also the regression guard against a future fallback creeping back (a test
asserts the refusal, so re-adding a fallback turns it red).

### What moved, per side of the port

| | Before | After |
| --- | --- | --- |
| Elm payload | `{toAdd, toMarkSynced, toMarkDeleted, toRemove}` | `{treeId, toAdd, toMarkSynced, toMarkDeleted, toRemove}` |
| `Doc.Data.toSave` | `DBChangeLists -> Value` | `String -> DBChangeLists -> Value` |
| senders | 6 call sites, treeId in scope at 3 | `restore`, `resolveConflicts`, `pushOkHandler` gained a `treeId` parameter (`Page.App` had `docId` at all three call sites); `localSave`, `importTree` and `cardDataReceived` already had it |
| JS handler | 45 lines inline in `doc.js`, keyed off `TREE_ID` | `applyCardBasedSave(payload, deps)` in `src/shared/save.js`, keyed off `payload.treeId`; `doc.js` passes the db, three clock/id sources and two callbacks |
| `SaveCardBasedTree` | `TREE_ID = elmData[0]` | leaves `TREE_ID` alone — the imported document is not on screen until Elm navigates and sends `LoadDocument` |

The tag names did not change, so there is no Elm→JS drift; the payload shape
did, and both sides plus `docs/ARCHITECTURE.md` §5.3 and the §7 port table
moved in the same commit.

**Why removing the `TREE_ID` write is part of D5, not extra.** The finding
names it: "the *global* `TREE_ID`, which only `SaveCardBasedTree` sets". With
the payload authoritative nothing in the import path reads it, and setting it
early was actively wrong in the window before navigation — every other reader
(`rt:join` on reconnect, `cardsConflict`, the `pull` guard `data.d === TREE_ID`,
`RenameDocument`, `SendCollabState`, `HistorySlider`, sync-info, image upload)
means "the document on screen", and that was still the *old* document, whose
liveQueries were still running.

**Why the unordered `Cmd.batch` is now safe both ways round.** Whichever lands
first:

- `SaveCardBased` first — the cards are written and the snapshot is taken for
  the imported document. `dexie.trees.update` finds no row yet and writes
  nothing, which loses nothing: the row `SaveCardBasedTree` then adds carries
  its own `updatedAt`, and `treeDocDefaults` has no `synced` key, so the trees
  liveQuery's `filter(t => !t.synced)` still pushes it.
- `SaveCardBasedTree` first — the row exists, the save stamps it
  `updatedAt`/`synced: false`, same end state.

`importComplete` can still reach Elm before the cards commit, and that is
benign: `loadCardBasedDocument` subscribes a Dexie `liveQuery`, so the cards
arrive as a `CardDataReceived` the moment they land, and a brand-new document
has no per-document `localStore` for the initial read to carry.

### Tests

8 new, all red first, plus `treeId` made a required field of every save payload
the existing seam-1 tests decode (evidence in Comments).

**Seam 4 — `tests/save.test.ts`, 7 tests.** The handler is driven with an
injected in-memory fake of the three Dexie tables it touches; assertions are on
the rows the store is left holding, never on which calls were made. The fake
models the two Dexie behaviors the sequence depends on: `Table.update` on an
absent key writes nothing, and an undefined key is an error rather than a match
on everything. Fixture: a document with two synced cards, a snapshot and a
timestamp, standing in for the one on screen.

1. *writes the local snapshot for the document the save names, and only that
   one*
2. *the snapshot holds the named document's cards and nothing else*
3. *stamps the named document's row unsynced and leaves every other one alone*
   — the `trees` rows compared whole, so a stray field change fails it
4. *an import on a fresh session reports no error and snapshots the new
   document*
5. *an import whose document row has not been written yet still saves its cards*
6. *a save for the document on screen applies its cards, snapshot and
   timestamp* — the don't-break guard, the only test green before the fix
7. *a save that names no document is refused rather than guessed at*

**Seam 1 — `tests/DataTest.elm`.** `changeListsDecoder` now requires `treeId`,
so every existing payload-decoding test pins it (9 expectation literals, 13
tests red before the field existed), and one new test — *importing a tree
stages every card of it, for the document being imported into* — pins the
import payload: the document it saves into, and each staged row's `treeId` and
parent.

ADR-0001 seam 4 records the injected-database rule (and `CONTEXT.md` with it);
`docs/ARCHITECTURE.md` gains `src/shared/save.js` in §2 and mentions it in §8.

### Verification

Rebased on `selfhost` at `3a56472` (over tickets 11 and 19, which landed
mid-work): `bun run test:elm` 43/43, `bun test` 58/58 across 9 files,
`bun run newbuild` succeeds, `node config-check.js` exit 0.

## Comments

- **Red-first evidence.** The handler was first extracted verbatim, with the
  global passed in as a `currentTreeId` dep, and the tests run against it:
  - Importing while `open-doc` was the current document — **6 fail, 1 pass**.
    The open document's snapshot row was rewritten under its own id
    (`1000:open-doc`) and its `updatedAt` moved from 1000 to the save's
    timestamp with `synced: false`; the imported document got no snapshot at
    all and its own `trees` row was never touched. Test 7 showed the payload
    with no `treeId` being applied to `open-doc` instead of refused. Test 6 (the
    ordinary save) passed from the start.
  - The same tests with no current document, i.e. a genuine fresh session —
    **7 fail**, every one with
    `"Error saving data!Error: DataError: Invalid key provided"`: the cards were
    written, then the snapshot query on `treeId: undefined` threw and the alert
    swallowed the rest, so neither the snapshot nor the tree timestamp was
    written.
  - Elm side, `changeListsDecoder` requiring `treeId` before `toSave` had one —
    **13 fail**, all `Expecting an OBJECT with a field named 'treeId'`,
    including the new import test.
  Then `currentTreeId` was deleted from the module and its callers, which is
  what turned them green.
- **Where the "leaves the other document alone" guarantee lives now.** After the
  fix the module has no notion of a current document, so the tests express the
  criterion as data: another document's rows sit in the store, and a save that
  names the imported one must leave them byte-identical. The guard against
  someone reintroducing an ambient fallback is test 7 — a fallback would make
  the refusal succeed.
- **Residue, deliberately left (all pre-existing, none introduced):**
  - The local snapshot is still built from raw `deleted: 0` rows rather than
    newest-per-id — ADR-0005 §1 applied to the JS side, which **ticket 28**
    owns. It is flagged with a `KNOWN GAP` comment at the moved line so a
    reviewer does not read the relocation as new code.
  - A save whose only change is one new empty card returns before
    `trees.update`, so adding a blank card does not stamp the document unsynced.
    Verbatim from the original ("Don't add new empty cards to history") and not
    D5.
  - `SaveCardBasedMigration` still keys off `TREE_ID`. Its Elm tag is never
    constructed — dead on the Elm side — so it is ticket 21/22's, not a live
    instance of D5.
  - The two import paths (`Page.Import` for templates, `Page.App` for a chosen
    file) remain duplicated, comment included; `Cmd.batch` is left in both,
    since the design is that its order no longer matters. Consolidating them is
    ticket 24's kind of work.
- **Incidental, declared:** `console.log("SaveCardBasedTree", elmData)` is gone.
  `fromElm` already pushes every port message into the `window.elmMessages` ring
  buffer, so the line traced what was already recorded.
- **Rebase note.** Ticket 11 refactored `localSave` into `localChanges` +
  `stageRows` mid-work, which *reduced* this diff: `toSave` is now called once
  inside `localSave` and `mergeCards` returns `DBChangeLists`, so the merge
  helpers needed no `treeId` after all. Its side of `Doc/Data.elm` and
  `tests/DataTest.elm` was taken whole and the threading re-applied on top.
- `docs/CODE_REVIEW.md` left as the catalog as found, matching tickets 02–07,
  10, 12, 13, 20.
