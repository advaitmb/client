# Gingko Writer Client — Architecture (`selfhost` branch)

This document describes the codebase as it exists on the `selfhost` branch: a
fork of the Gingko Writer web client being slimmed down for self-hosting.
Payments/trial UI, the git-like document format, 25 interface languages, the
text/OPML importers, and several Electron-era subsystems have been removed or
stubbed; UI surfaces are migrating out of Elm into TypeScript custom elements.

A companion catalog of known bugs, dead code, and improvement opportunities
lives in [CODE_REVIEW.md](./CODE_REVIEW.md).

---

## 1. Big picture

Gingko Writer is a tree-structured writing app: a document is a tree of
markdown "cards" rendered as columns (depth 1 in column 1, its children in
column 2, and so on). The client is:

- **An Elm application** (`src/elm/`, ~14k lines) that owns all state,
  keyboard handling, and document logic.
- **A JavaScript port layer** (`src/shared/doc.js` + `doc-helpers.js`) that
  owns persistence (Dexie/IndexedDB, localStorage), the WebSocket sync
  protocol to the companion [gingko/server](https://github.com/gingko/server),
  and the hidden `<textarea>` editor.
- **A TypeScript "interface layer"** (`src/ui/`) of framework-less custom
  elements (`<gw-tree>`, `<gw-header>`, `<gw-sidebar>`, modals…) that render
  the surfaces Elm used to render. Elm decides *when* a surface is on screen
  and what state it carries (as JSON attributes); the elements own markup and
  report back with bubbling `CustomEvent`s.

```
        attributes (JSON)                    ports (tagged JSON)
Elm ───────────────────────▶ gw-* elements   Elm ◀──────────────▶ doc.js
    ◀───────────────────────                                        │
        bubbling CustomEvents                       Dexie ◀─────────┤
                                                    localStorage ◀──┤
                                                    WebSocket /ws ◀─┘
```

---

## 2. Repository layout

| Path | Contents |
|---|---|
| `src/elm/` | The Elm application (entry: `Main.elm`) |
| `src/shared/doc.js` | JS side of the Elm ports: storage, sync, dispatch table |
| `src/shared/doc-helpers.js` | Shared helpers + the `gw-textarea` custom element |
| `src/shared/stamps.js` | Stamp (HLC) ordering and the pure sync helpers built on it: checkpoint, backup selection |
| `src/shared/session.js` | The session blob's key and the logout sequence (POST /logout, clear, hand back to Elm) |
| `src/shared/save.js` | The local half of a save: apply a `SaveCardBased` payload to the document it names (cards, snapshot, tree timestamp) |
| `src/ui/` | TypeScript custom elements (the interface layer) + its README |
| `src/web/container-web.js` | Web build's "container" (per-doc localStorage store); aliased as `require("Container")` |
| `src/web/database-download.js` | Standalone IndexedDB export page (bundled to `web/database-download.js`, loaded by `database-download.html`) |
| `src/static/` | `index.html`, CSS, fonts, images, `templates/*.json`; copied verbatim into `web/` |
| `elm-kernel-replacements/` | Patched copies of `elm/html`, `elm/browser`, `elm/virtual-dom` |
| `tests/` | `*.elm` (elm-test) and `*.test.ts` (bun test) suites |
| `web/` (gitignored) | Build output / deploy root |
| `.github/workflows/ci.yml` | The only workflow: build + both test suites on `selfhost` |
| `docs/` | This documentation |

---

## 3. Build pipeline

Everything is `bun run newbuild` (`package.json`); there is no dev/watch
script on this branch. The steps:

1. **`bun patches.mjs`** — copies `elm-kernel-replacements/elm-stuff/` into the
   repo-local `ELM_HOME` (`elm-home/`) and invalidates compiler artifacts when
   fingerprints change. The replacements are Simon Lydell's forks of
   `elm/virtual-dom`, `elm/html`, and `elm/browser`, which make Elm's renderer
   diff against the *actual* DOM. This is what makes it safe for the `gw-*`
   custom elements (and browser extensions / page translators) to own DOM
   inside the Elm-rendered tree.
2. **`bun esbuild.mjs`** — bundles three entry points (minified):
   `src/shared/doc.js → web/doc.js`, `src/ui/index.ts → web/ui.js`, and
   `src/web/database-download.js → web/database-download.js` (dexie +
   dexie-export-import for the export page, which therefore makes no external
   request). `require("Container")` is aliased to `src/web/container-web.js`.
   The root `config.js` (gitignored; created from `config-example.js`) is
   `require`d by `doc.js` and therefore **inlined into the bundle** — config
   changes require a rebuild. The script derives its own directory from
   `import.meta.url`, so it runs under Node as well as Bun (Bun stays
   canonical — ADR-0004).
3. **`cp -r src/static/. web/`** — static assets.
4. **`bunx tailwindcss -i src/static/style.css -o web/style.css`** — Tailwind
   (preflight off, `content` scans `src/elm/**/*.elm` and `src/ui/**/*.ts`)
   inlines `shared.css`/`home.css` into one stylesheet.
5. **`ELM_HOME=elm-home/elm-stuff elm-watch make --optimize`** — compiles
   `src/elm/Main.elm → web/elm.js` per the `app` target in `elm-watch.json`,
   then postprocesses with `elm-postprocess.mjs`, which substitutes the
   build-time placeholders `{%SUPPORT_EMAIL%}`, `{%SUPPORT_URGENT_EMAIL%}`,
   and `{%HOMEPAGE_URL%}` from `config.js` — in every compilation mode, so
   non-optimize builds don't show raw placeholders either.
6. **`bun run minifyelm`** — double `uglify-js` pass over `web/elm.js`.

`web/index.html` loads `/elm.js`, `/doc.js`, and `/ui.js` (all deferred), plus
`style.css`, `theme.css`, and self-hosted fonts (`desktop-fonts.css`; no
external requests by design).

**Self-hosting checklist:** install Bun; `cp config-example.js config.js` and
set the four values; `bun i`; `bun run newbuild`; serve `web/` behind
`gingko/server` (which provides `/login`, `/signup`, `/me`, `/export-docx`,
`/templates/*.json` passthrough, and the `/ws` WebSocket).

---

## 4. The Elm application

### 4.1 Entry point, pages, routing

`Main.main` is a `Browser.application` (`Main.elm:398`). The model is a flat
union of pages (`Main.elm:34`): `Signup`, `Login`, `Import`, `DocNew`, `App`.
Flags (one JSON object from `doc.js`) are decoded twice: `Session.decode` and
`GlobalData.decode`.

There is **no route parser**; `Route.elm` only builds URLs, and parsing is
hand-rolled in `Main.handleUrlChange` (`Main.elm:70–167`) over
`AppUrl.fromUrl`:

- Logged in: `[]` → App home; `/new` → `Page.DocNew` (generates a random id,
  redirects to `/<id>`, and the redirect is treated as a brand-new doc);
  `/import/<template>` → `Page.Import`; `/<dbName>` → App with that document;
  `/<dbName>/404-not-found` → not-found screen; anything else no-ops.
- Guest: `[]` → Signup, `/login`, `/signup`, and `/import/<t>` mid-login
  transition.

Login/signup completion uses a `transition : Maybe LoggedIn` field on the auth
pages; `Main.loginInProgress` picks it up during the redirect to `/` and
initializes `Page.App` with the new session.

### 4.2 Session and global data

`Session` (`Session.elm`) is `GuestSession Guest | LoggedInSession LoggedIn`.
`UserData` carries `email`, `confirmedAt`, `shortcutTrayOpen`, `sortBy`, the
document list (`Doc.List.Model`), and `features` (no payment status — ADR-0002;
a `paymentStatus` left in stored session data by an older build is ignored). Auth HTTP: POST `/signup`, POST `/login` (via `Http.riskyRequest`
for the session cookie). On success the session is persisted through the
`StoreUser` port; JS writes it to `localStorage["gingko-session-storage"]` and
echoes `userLoggedInMsg`. Logout is the mirror image: `<gw-sidebar>`'s logout
button → the `LogoutUser` port → the sequence in `src/shared/session.js`
(POST `/logout`, blob cleared, then doc.js's `stopSyncing`) →
`userLoggedOutMsg` → the login page (§7).

On selfhost the Elm login screen is normally skipped entirely: `doc.js`
auto-logs-in against `/me` at boot and seeds the local database before Elm
starts (see §6.1). That is also why logging out hands back to Elm instead of
reloading `/login`: a reload would ask `/me` again.

`GlobalData` is `{ seed, currentTime, isMac }`; time ticks every 9 s from
`Page.App`, and the random seed is threaded through card-id generation.

### 4.3 Page.App — the logged-in shell

`Page.App.Model` (`App.elm:55`) owns everything around the document:

- `documentState : Empty … | Doc DocState | DocNotFound …`, where `DocState`
  bundles the session, `docId`, the `Page.Doc.Model`, the persistence model
  `Doc.Data.Model`, and save timestamps.
- UI state machines: `SidebarState`, `HeaderMenuState` (export preview,
  history view, settings), `ModalState` (file switcher, template selector,
  help, word count…), toast tray, tooltip, theme.

The view instantiates the custom elements and maps their events to messages:
`gw-header` (title edit, menus, history slider), `gw-sidebar`,
`gw-switcher-modal`, `gw-template-modal`, `gw-help-modal`,
`gw-wordcount-modal`. String↔type translators for those attributes/events live
at `App.elm:2013–2160`.

History viewing builds `Doc.History` from the data model, blocks editing via
`Page.Doc.setBlock`, and checkout/restore go through `Data.restore`. Export
state is `(ExportSelection, ExportFormat)`; DOCX goes through
`Api.exportDocx` (POST `/export-docx`), other formats are built client-side
(§4.5).

### 4.4 Page.Doc — the editor

`Page.Doc.Model` (opaque) holds the working tree (`Doc.TreeStructure.Model`),
the view state, dirtiness, and a `block : Maybe String` that disables editing
(used by history view). The mode machine is
`ViewMode = Normal cardId | Editing {cardId, field} | FullscreenEditing …`;
`changeMode` (`Doc.elm:1036–1200`) is the heart of the editor — a transition
matrix computing focus, scroll commands, save-on-exit, and collaboration
broadcasts.

Communication with the parent uses
`MsgToParent = ParentAddToast … | CloseTooltip | LocalSave CardTreeOp`.
`CardTreeOp` (`Types.elm:30`) is the operation vocabulary: insert, update,
remove, move, merge, and paste-subtree. `Page.App` turns `LocalSave` into
`Data.localSave` and the outgoing `SaveCardBased` port message.

All keyboard input is captured by Mousetrap in JS and forwarded as
`Keyboard "mod+j"` etc. through the `docMsgs` port; `Page.App` intercepts
app-level shortcuts per modal state and hands the rest to `Page.Doc.incoming`
(a full vim-ish navigation/move/merge/insert/cut/copy map).

The card tree renders as the `<gw-tree>` element: the document is encoded into
a `tree` attribute and the cursor state into a separate `view-state`
attribute so tree reconciliation and mode changes stay independent. Fullscreen
editing is the one document surface still fully Elm-rendered
(`Doc/Fullscreen.elm`).

### 4.5 View layer inventory

Still Elm-rendered: login/signup pages, fullscreen editing, toasts, tooltips,
shortcut tray, breadcrumbs, search field, mobile buttons, conflict banner,
export preview pane, loading spinners, empty/not-found screens.

Moved to `src/ui/` custom elements: help modal, word-count modal, switcher
modal, template modal, header (incl. save indicator + history slider),
sidebar, markdown rendering (`<gw-markdown>`), and the card tree (`<gw-tree>`).
(`src/ui/README.md`'s "what has moved" table predates most of these moves.)

`Toast.elm` is a **vendored third-party module** (documented in its header);
Elm's `--optimize` dead-code elimination strips the unused parts, so its size
is intentional.

Translation: `Translation.elm` keeps the upstream `TranslationId` union but
the fork is English-only — `tr` takes no language argument and the 25 language
tables were deleted. Surfaces that moved to TS hardcode their English strings.

Export: JSON/OPML/plain-text are built client-side
(`Coders.treeToJSON` / `treeToOPML` / `treeToMarkdownString`) and saved with
`File.Download`; DOCX round-trips through the server.

---

## 5. Document data model and sync

### 5.1 Card version rows

The persistence model (`Doc/Data.elm`) is **not** the tree — it is an
append-mostly log of card *version rows*:

```elm
type alias Card t =
    { id, treeId, content : String
    , parentId : Maybe String     -- Nothing = child of root
    , position : Float            -- fractional sibling ordering
    , deleted, synced : Bool
    , updatedAt : t               -- UpdatedAt (HLC) stamp
    }
```

A card may have several rows at once: the Dexie `cards` table's primary key is
`updatedAt`, so every save appends a new version. The current tree is
materialized by `toTree` (`Data.elm:758`): sort rows newest-first, keep the
newest row per id, drop deleted, then recurse by `parentId` sorting siblings
by `position`. Sibling positions are assigned by `getPosition`
(`Data.elm:693`): midpoint of neighbors, `left+1` at the end, `right-1` at the
start (index `999999` is the "append" sentinel).

### 5.2 UpdatedAt — hybrid logical clocks

`UpdatedAt.elm` wraps HLC stamps `{timestamp, counter, hash}` with string form
`"ts:counter:hash"`, totally ordered by timestamp, then counter, then hash.
JS generates values with `@tpp/hybrid-logical-clock`'s `hlc.nxt()` at write
time and feeds received stamps back with `hlc.recv()`.

### 5.3 Local save

`Data.localSave docId op model` turns a `CardTreeOp` into a
`DBChangeLists = { toAdd, toMarkSynced, toMarkDeleted, toRemove }`, encoded for
the port with the id of the document it is for: `{ treeId, toAdd, … }`. JS
applies it transactionally (`src/shared/save.js`, reached from `doc.js`'s
`SaveCardBased`): `toAdd` rows get fresh HLC stamps, content changes also write
a local history snapshot, the document's `trees` row is stamped unsynced, and
Dexie `liveQuery` subscriptions echo the new row set back to Elm as
`CardDataReceived`.

Every sender of `SaveCardBased` names its document, and the handler refuses a
payload that does not: a save is not always for the document on screen. A JSON
import saves into a document nobody has opened — its cards and the `trees` row
that makes them a document travel as two port messages in one `Cmd.batch`,
whose order is unspecified — so keying the snapshot and the timestamp off the
port layer's current-document global wrote another document's rows, or failed
outright on a fresh session (CODE_REVIEW.md D5).

### 5.4 Sync states and deltas

On every `CardDataReceived`, `getSyncState` (`Data.elm:826`) groups rows by
card id and classifies each card:

- unsynced rows, ≤1 synced → **Unsynced** (needs push)
- unsynced rows, >1 synced → **Conflicted** `{original, ours, theirs}`
- no unsynced, >1 synced → **CanFastForward** (drop all but newest synced)

Unsynced state triggers `PushDeltas`: per-card ops diffed against the newest
synced base — `ins`/`upd`/`mov`/`del`/`undel`, each `upd`/`del` carrying an
`expectedVersion` — plus a checkpoint `chk` (max synced stamp). The server
acks with `pushOk` (→ rows ≤ ack marked synced, then fast-forwarded away) or
`pushError`/`cardsConflict`.

Delete-vs-edit conflicts are auto-resolved by `resolveDeleteConflicts`
(edits win; the losing deletion rows are removed). Remaining conflicts are
surfaced to the user (`Ours`/`Theirs`/`Original` preview and commit via
`Data.resolveConflicts`).

The legacy git-era conflict machinery (`Doc/Data/Conflict.elm`, `Diff3.elm`,
`TreeStructure.setTreeWithConflicts`) is dead code from the format removal —
`Diff3.diff3Merge` is a stub that returns `[]`.

### 5.5 History

JS snapshots the full non-deleted card set on every content save
(`tree_snapshots` table, id `"<ts>:<treeId>"`), and pulls server-side history
metadata (`pullHistoryMeta`/`pullHistory`). `Doc.History` wraps the snapshot
list in a zipper for the header's history slider; restore diffs the current
card set against the chosen snapshot and emits add/delete rows through the
normal save path.

### 5.6 Trees in memory

`Doc.TreeStructure` applies `Ins/Upd/Mov/Rmv/Mrg/Paste` messages to the
in-memory `Tree` for optimistic updates and recomputes the column view;
`Doc.TreeUtils` provides read-only queries (parents, children, columns,
next/prev in column, descendants, scroll-position calculation, `sha1` ids).

---

## 6. The JS interface layer

### 6.1 Bootstrap

`doc.js` runs `initElmAndPorts()` at module load:

1. Read `localStorage["gingko-session-storage"]`; build Elm flags (plus
   `seed`, `isMac`, `currentTime`).
2. **Auto-login**: if there is no stored email or the local `trees` table is
   empty, fetch `/me`, merge the response into the session blob, and seed
   Dexie with the server's document list.
3. `setUserDbs(email)`: open the WebSocket, subscribe a Dexie `liveQuery` on
   `trees` that pushes `documentListChanged` to Elm and sends unsynced
   metadata to the server.
4. `Elm.Main.init({flags})`, then subscribe `gingko.ports.infoForOutside` to
   the `fromElm(tag, data)` dispatch table.
5. Global listeners: `window.checkboxClicked` (used by rendered markdown),
   a `beforeunload` dirty guard, fullscreen-change, and print.

`ui.js` (`src/ui/index.ts`) registers the custom elements; `gw-textarea` is
registered from `doc-helpers.js`.

### 6.2 Storage inventory

| Store | Key/Table | Contents |
|---|---|---|
| localStorage | `gingko-session-storage` | session blob (email, sidebar, sortBy, …) — read as Elm flags |
| localStorage | `gingko-local-store/<treeId>/settings` | per-document settings (`last-actives`, `theme`) |
| Dexie `trees` (PK `id`) | | document metadata rows (`name`, `owner`, timestamps, `synced`) |
| Dexie `cards` (PK `updatedAt`) | | append-only card version rows (§5.1) |
| Dexie `tree_snapshots` (PK `snapshot`) | | local + pulled history snapshots |
| ImmortalDB | `backup-snapshot:<treeId>` | write-only plain-text backup of newest card versions |

### 6.3 WebSocket protocol

`pws` (persistent WebSocket) to `origin/ws`, JSON messages `{t, d}`, 30 s
pings.

Client → server: `pull [treeId, chk]`, `push {dlts, tr, chk}`,
`pullHistoryMeta`, `pullHistory`, `trees` (unsynced metadata), `rt`/`rt:join`
(collab cursors), `ping`.

Server → client: `user` (settings sync), `cards` (bulk-put synced rows),
`cardsConflict`, `pushOk`/`pushError`, `doPull`, `trees`/`treesOk`,
`historyMeta`/`history`, `rt`/`rt:users` (collaborator state), `removedFrom`,
`pong`.

On reconnect: the send queue drains, `rt:join` is re-sent for the open
document, and Elm gets `SocketConnected` (which re-triggers a push of
unsynced deltas).

### 6.4 The editor element

Cards are edited in a real `<textarea>` wrapped by `gw-textarea`
(`doc-helpers.js`), rendered by `tree.ts` for the editing card and by
`Doc/Fullscreen.elm` in fullscreen. It seeds from a `start-value` attribute,
reports keystrokes (`FieldChanged`), cursor state (`TextCursor`), and
debounce-autosaves in fullscreen. Elm remains the source of truth for the
field; JS-side text mutations (bold/italic wrap, markdown link, heading
rewrite) echo the new value back.

### 6.5 Custom elements

All are rendered by Elm as `Html.node "gw-…"` with JSON-string attributes and
report back with bubbling `CustomEvent`s (`emit` in `dom.ts`). `tree.ts` is the
largest: keyed reconciliation of columns/groups/cards by id, class-only
updates for cursor changes, and native HTML5 drag-drop with CSS-revealed drop
regions. `markdown.ts` renders card content with `marked` (GFM + breaks) plus
a CriticMarkup preprocessor. `header.ts`, `sidebar.ts`, and the modals are
render-once surfaces following the rules in `src/ui/README.md`.

---

## 7. Port contract reference

One outgoing port (`infoForOutside`, tagged `{tag, data}`) and several
incoming ones (`docMsgs`, `appMsgs`, `documentListChanged`, `importComplete`,
`userLoggedInMsg`, `userLoggedOutMsg`, `userSettingsChange`).

**Live Elm → JS tags:** `StoreUser`, `SaveUserSetting`, `Alert`, `SetDirty`,
`DragDone`, `ConfirmCancelCard`, `InitDocument`, `LoadDocument`,
`GetDocumentList`, `RequestDelete`, `RenameDocument`, `SaveCardBased`,
`SaveImportedTree` (JS tag `SaveCardBasedTree`), `PushDeltas`,
`SendCollabState`, `ScrollCards`, `ScrollFullscreenCards`, `DragStart`,
`CopyCurrentSubtree`, `CopyToClipboard`, `SelectAll`, `TextSurround`,
`InsertMarkdownLink`, `SetCursorPosition`, `HistorySlider`,
`SetSidebarState`, `SaveThemeSetting`, `Print`, `EmptyMessageShown`,
`ConsoleLogRequested`, `LogoutUser`.

`SaveCardBased` carries `{ treeId, toAdd, toMarkSynced, toMarkDeleted,
toRemove }` — the document it saves into is part of the payload, not the port
layer's current document (§5.3). `SaveImportedTree` carries `(docId, name)` for
the same document; the two are batched by the import and arrive in either
order, and neither depends on the other having landed.

`LogoutUser` is the one round trip that ends in JS telling Elm to change
pages: `<gw-sidebar>`'s `gw-logout` → `Page.App.LogoutRequested` →
`Session.logout` → `doc.js` (POST `/logout`, drop the session blob, close the
socket, `src/shared/session.js`) → `userLoggedOutMsg` →
`Main.UserLoggedOut` → the login page. Local document data is deliberately
kept; see `src/shared/session.js`.

**Live JS → Elm:** `docMsgs` — `CancelCardConfirmed`, `InitialActivation`,
`DragStarted`, `DragExternalStarted`, `DropExternal`, `Paste`, `PasteInto`,
`FieldChanged`, `AutoSaveRequested`, `FullscreenCardFocused`, `TextCursor`,
`ClickedOutsideCard`, `CheckboxClicked`, `Keyboard`, `WillPrint`,
`RecvCollabState`, `RecvCollabUsers`, `CollaboratorDisconnected`
(⚠ JS also sends `FullscreenChanged`, which has no decoder);
`appMsgs` — `SocketConnected`, `CardDataReceived`, `HistoryDataReceived`,
`PushOk`, `PushError`, `MetadataUpdate`, `SavedRemotely`, `ErrorAlert`,
`NotFound`.

Dead tags on both sides (never sent and/or never handled) are cataloged in
CODE_REVIEW.md.

---

## 8. CI and testing state

One workflow, `.github/workflows/ci.yml`, runs on every push and PR to
`selfhost`: `bun install --frozen-lockfile`, a check that `package-lock.json`
is still in sync with `package.json` (ADR-0004), `config-check`, `bun run
newbuild`, then `bun run test:elm` and `bun run test:ts`. The upstream
Electron-era `build.yml` and `master`-only `web-deploy.yml` are deleted, as is
the phantom `@playwright/test` devDependency.

Tests live in `tests/`: `*.elm` for elm-test (`Doc.Data`, `Session`) and
`*.test.ts` for bun test (custom elements against jsdom, the extracted
sequences in `src/shared/stamps.js`, `src/shared/session.js` and
`src/shared/save.js`, and the build's `config-check` / `elm-postprocess`
seams). The pre-agreed seams are ADR-0001's.
