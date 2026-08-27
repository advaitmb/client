# Domain glossary — Gingko Writer client (selfhost)

Vocabulary used in code, issues, and tests. Full system description:
`docs/ARCHITECTURE.md`.

## The document

- **Card** — the unit of writing: a block of markdown with an id, a parent,
  and a fractional **position** among its siblings. Not "node" or "bullet".
- **Rebalance** — renumbering a card's siblings onto whole numbers when the
  gap at the insertion point is too small to split (below `1.0e-6`). The
  renumbered rows are ordinary version rows and sync as `mov` ops.
- **Tree / document** — one Gingko document, a tree of cards identified by
  `treeId` (aka `dbName` in routes). Rendered as **columns**: depth 1 in
  column 1, children of the active card in the next column, siblings grouped
  by parent into **groups**.
- **Card tree operation (`CardTreeOp`)** — the operation vocabulary between
  editor and persistence: insert, update, move, merge, remove, paste-subtree.
- **Merge** — joining two vertically adjacent cards into one. The card the user
  is on survives and keeps its id; the other is deleted and its children are
  re-parented under the survivor — always, in both directions. The direction
  (up absorbs the card above, down the one below) decides only the order the
  two texts and the two child lists are joined in.

- **Card drag / external drag** — the two drags the app can see, and they are
  not the same thing: a card being moved inside the tree, which `<gw-tree>`
  owns end to end (`gw-drag-start` → `gw-drop` → `gw-drag-end`), and text
  dragged in from outside the app, which only the port layer can see
  (`src/shared/drag.js`).
- **Drop placement** — where a dropped card lands: the parent and the index
  among that parent's children, read on the tree the dragged card has been
  pruned out of, because that is the tree it is re-inserted into. A drop with
  no placement (into the card's own subtree) is no move at all.

## Persistence and sync

- **Version row** — one immutable row in the Dexie `cards` table describing a
  card at a point in time (`content`, `parentId`, `position`, `deleted`,
  `synced`, `updatedAt`). A card = the **newest version row per id**; the
  table is an append-mostly log, so stale rows for the same id persist until
  fast-forward. Any scan that ignores newest-per-id is a bug (see
  CODE_REVIEW.md D1/D2).
- **Staged row** — a version row handed to the port layer whose stamp the DB
  has not issued yet. `Doc.Data` keeps one per card id until the Dexie
  liveQuery echoes that card back, because its view of the log is a round trip
  behind the save: every save built from a card that already exists (placement,
  update, move, delete, merge) reads the staged row first, or it writes back
  the state the previous save had just changed. Staged rows are not part of the
  version log — no stamp, never pushed.
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
- **Landing** (`Route.elm`) — what a URL names: the page to initialize, plus
  any correction to the address bar. Every path has one (a URL nobody planned
  for lands on the not-found screen or the login form), and initializing that
  page is what runs its commands.
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
4. Session and port sequences extracted from `doc.js` (`src/shared/session.js`:
   logout, adopting the server's account on boot; `src/shared/save.js`:
   applying a save) — faked `fetch`, real `localStorage`, injected callbacks
   and, for a database writer, an injected in-memory fake of the tables.
5. `Session`'s stored-blob surface (Elm, pure): `decode`/`encode` of the
   session blob and `responseDecoder` for a login answer — the preferences
   this client persists.
6. Build-time gates: `config-check.js` and `elm-postprocess.mjs`'s
   placeholder substitution — expose the decision as a pure function and test
   that, not the ambient `config.js`.
7. Auth forms (Elm, pure): `Page.Login.credentialsValidator` and
   `Session.signupBody` — what the login and signup forms accept, and what
   the client asks the server to create an account with.
8. Routing (Elm, pure): `Route.loggedInLanding` / `Route.guestLanding` — which
   page a URL names, and `Route.toString` round-tripping back to it.
9. Drop placement (Elm, pure): `Doc.TreeStructure.dropPlacement` — where a
   dragged card lands, and which drops are no move at all.
10. Document chrome (Elm, pure): `Page.Doc.Incoming.fromOutside` (a port
    message's tag → `Msg`), `Page.Doc.Export.toString`/`toMimeType` (what an
    export writes and is saved as), `Doc.UI.documentWordcount` with
    `Page.Doc.getStartingWordcount` (the word-count modal's session row), and
    `Translation.tr` for the shortcut tray. Whether a port command is sent at
    all is out of reach here.
11. The document's mode machine (Elm): `Page.Doc.getViewMode` after
    `opaqueIncoming`/`opaqueUpdate` on a document built from the exported
    setters — which mode an event leaves the document in, including the
    transitions a blocked document must refuse. A transition only a DOM event
    names is reached by simulating that event on `Page.Doc.view`. The `Cmd` is
    still out of reach, as at seam 10.
