# Domain glossary — Gingko Writer client (selfhost)

Vocabulary used in code, issues, and tests. Full system description:
`docs/ARCHITECTURE.md`.

## The document

- **Card** — the unit of writing: a block of markdown with an id, a parent,
  and a fractional **position** among its siblings. Not "node" or "bullet".
- **Tree / document** — one Gingko document, a tree of cards identified by
  `treeId` (aka `dbName` in routes). Rendered as **columns**: depth 1 in
  column 1, children of the active card in the next column, siblings grouped
  by parent into **groups**.
- **Card tree operation (`CardTreeOp`)** — the operation vocabulary between
  editor and persistence: insert, update, move, merge, remove, paste-subtree.

## Persistence and sync

- **Version row** — one immutable row in the Dexie `cards` table describing a
  card at a point in time (`content`, `parentId`, `position`, `deleted`,
  `synced`, `updatedAt`). A card = the **newest version row per id**; the
  table is an append-mostly log, so stale rows for the same id persist until
  fast-forward. Any scan that ignores newest-per-id is a bug (see
  CODE_REVIEW.md D1/D2).
- **Stamp (`UpdatedAt`)** — a hybrid logical clock value
  `"timestamp:counter:hash"`, totally ordered by numeric timestamp, then
  numeric counter, then hash. Never compare stamps as strings.
- **Sync state** — per-card classification on every data receive: `Synced`,
  `Unsynced` (has local rows to push), `Conflicted` (`{original, ours,
  theirs}`), `CanFastForward` (older synced rows can be dropped).
- **Delta / push / checkpoint (`chk`)** — unsynced cards are pushed as
  per-card ops (`ins`/`upd`/`mov`/`del`/`undel`) diffed against the newest
  synced base, with a checkpoint = max synced stamp; the server acks with
  `pushOk` or reports `cardsConflict`.
- **Snapshot** — a full non-deleted card set stored in `tree_snapshots` on
  every content save; powers the history slider and restore.

## Application layers

- **Elm core** (`src/elm/`) — owns all state and document logic.
  `Page.App` = logged-in shell, `Page.Doc` = editor (mode machine
  Normal/Editing/FullscreenEditing), `Doc.Data` = the version-row model.
- **Port layer** (`src/shared/doc.js`) — the JS side of the Elm ports:
  Dexie, localStorage, the WebSocket protocol, and the tagged-JSON dispatch
  table. Elm→JS tag names and JS handler names must match exactly.
- **Interface layer** (`src/ui/`) — framework-less TypeScript custom elements
  (`gw-tree`, `gw-header`, `gw-sidebar`, modals, `gw-markdown`). Elm passes
  state as JSON attributes; elements report back with bubbling `CustomEvent`s.
  Rules live in `src/ui/README.md`.
- **Kernel replacements** (`elm-kernel-replacements/`) — patched
  `elm/virtual-dom` etc. that diff against the actual DOM, making third-party
  DOM ownership (the `gw-*` elements) safe inside Elm-rendered markup.

## Testing seams (pre-agreed, ADR-0001)

1. `Doc.Data` public API (Elm, pure): localSave, toTree/getSyncState,
   delta generation, conflict resolution, restore.
2. Extracted pure helpers of `doc.js` (stamp comparison, checkpoint
   computation) — extract to module scope to test, don't test via Dexie.
3. Custom elements: attribute-in → DOM/CustomEvent-out, in a DOM test
   environment.
