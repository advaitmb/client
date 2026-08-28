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
| `src/shared/session.js` | The session blob: its key, reading it back (a corrupt one is a guest, not a blank page), the boot probe of the optional `/me` (`fetchAccount`), and the logout sequence (POST /logout, clear, hand back to Elm) |
| `src/shared/cards.js` | Reading the card log: one row per id, the newest, deletions dropped — the document's cards, its root card, and the ImmortalDB backup text |
| `src/shared/documents.js` | Document-level writes: renaming, once, however many times Elm asks |
| `src/shared/local-db.js` | Which Dexie database this account's documents live in: the name derived from the email, and the single account that adopts the legacy `"db"` |
| `src/shared/port-errors.js` | What a failed message *from Elm* is worth telling the user, per tag; and whether an uncaught error is a browser extension rewriting the DOM |
| `src/shared/save.js` | The local half of a save: apply a `SaveCardBased` payload to the document it names (cards, snapshot, tree timestamp) |
| `src/shared/drag.js` | The drag lifecycle: which drag is in progress (a card, or text from outside the app), what Elm is told about it, and drag auto-scroll |
| `src/shared/metadata.js` | Document metadata going out: which `trees` rows the server has not acknowledged, and when they go — on a liveQuery emission, and again when the socket comes back |
| `src/ui/` | TypeScript custom elements (the interface layer) + its README |
| `src/web/container-web.js` | The per-document localStorage settings store (`localStore`), and nothing else since ticket 22 removed the PouchDB/Electron-era exports; aliased as `require("Container")`, which with the file's name is the last trace of the two-container build |
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
`gingko/server` (which provides `/login`, `/signup`, `/export-docx`,
`/templates/*.json` passthrough, and the `/ws` WebSocket). `/me` is optional —
see §6.1 step 3: master does not implement it, and the client's boot treats a
server without it as "nobody is logged in here".

---

## 4. The Elm application

### 4.1 Entry point, pages, routing

`Main.main` is a `Browser.application` (`Main.elm:392`). The model is a flat
union of pages (`Main.elm:34`): `Signup`, `Login`, `Import`, `DocNew`, `App`.
Flags (one JSON object from `doc.js`) are decoded twice: `Session.decode` and
`GlobalData.decode`.

There is **no route parser** in the `Url.Parser` sense: `Route.elm` owns both
directions of the mapping by hand, pattern matching on `AppUrl.fromUrl`'s path
segments. It answers with a **landing** — the page to initialize, plus any
correction to the address bar (a `Route` to *replace* the current URL with;
pushing one would leave the bad URL in the history for Back to land on):

- `Route.loggedInLanding`: `[]` → `Home`; `/new` → `NewDocument` (generates a
  random id, redirects to `/<id>`, and the redirect is treated as a brand-new
  doc); `/import/<template>` → `ImportTemplate` (an unknown template → `Home`);
  `/<dbName>` and `/<dbName>/<title>` → `Document`;
  `/<dbName>/404-not-found` and any deeper path → `DocumentNotFound`;
  `/login`, `/signup` → `Home`, correcting the URL to `/`.
- `Route.guestLanding`: `/login` → `LoginForm`; `/signup` → `SignupForm`; `[]`
  → `SignupForm`, correcting the URL to `/signup`; every other path →
  `LoginForm`, correcting the URL to `/login`.

Both are total and pure, which is what makes them testable (ADR-0001 seam 8) —
`Main`'s pages all carry a `Nav.Key`. `Main.routeUrl` is the only place that
carries a landing out, and both `init` and `handleUrlChange` go through it, so
the first page of a cold load runs its init commands like any other. Before
ticket 14, `init` discarded them and half the URL shapes returned `Cmd.none`
(CODE_REVIEW.md E4).

Login/signup completion uses a `transition : Maybe LoggedIn` field on the auth
pages; `Main.loginInProgress` picks it up when the redirect the auth page
triggered arrives, and routes it as the logged-in session it is, so
`Page.App`/`Page.Import` is initialized with the new session.

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

A server that implements `/me` skips the Elm login screen entirely: `doc.js`
auto-logs-in against it at boot and seeds the local database before Elm starts
(see §6.1). That is also why logging out hands back to Elm instead of reloading
`/login`: a reload would ask `/me` again. `gingko/server` master has no such
route — its last route is `app.get('*')`, which answers `/me` with this app's
own index.html — so against master the login screen is what a first boot shows,
and that is a supported deployment, not a failure (ticket 38).

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
`gw-header` (title edit, menus, history slider, theme picker), `gw-sidebar`,
`gw-switcher-modal`, `gw-template-modal`, `gw-help-modal`,
`gw-wordcount-modal`. String↔type translators for those attributes/events live
in the block after `subscriptions` — `ownershipName`, `headerMenuMsg`,
`themeMsg`, the export and sort pairs. The theme's two are `Page.Doc.Theme`'s
own `name`/`fromName`, because the same spelling is what the setting is saved
under.

History viewing builds `Doc.History` from the data model, blocks editing via
`Page.Doc.setBlock`, and checkout/restore go through `Data.restore`. Moving the
slider is a *checkout* — the version goes into the working tree to be read;
leaving the view is `closeHistoryView`, which puts the tree back to the version
the view opened at unless the exit was a restore (ticket 34: the ✕ and the
history icon used to disagree about that). Export
state is `(ExportSelection, ExportFormat)`, one half per row of the header's
export menu, each an ARIA radio group that reports a choice and waits for
Elm's answer (ticket 34); DOCX goes through
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

Which keystrokes get that far is `src/shared/shortcut-scope.js`, installed as
Mousetrap's `stopCallback` (ADR-0001 seam 14). The bindings are on `document`,
so a keystroke aimed at a control in the app's **chrome** — the header, the
sidebar, the modals — would otherwise act on the document behind it as well:
typing `j` with the export menu open moved the card cursor. Inside the chrome an
unmodified keystroke is the control's; Escape (the way out) and the modifier
chords (`mod+s` means save wherever it is pressed, and its override of the
browser's own shortcut rides on reaching the handler) still reach the app; a
form field is the field's, as it always was; and `.mousetrap` on the card
editor's textarea and the switcher's search box opts them back in.

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
modal, template modal, header (incl. the history slider), the save indicator
(`<gw-save-indicator>`, rendered by the header *and* by the still-Elm
fullscreen view — one implementation, which is why it is its own element),
sidebar, markdown rendering (`<gw-markdown>`), and the card tree (`<gw-tree>`).
(`src/ui/index.ts`'s header is the canonical list, beside the imports that
register them; ticket 22 removed the copy in `src/ui/README.md`, which had
drifted to naming one of the nine.)

`Toast.elm` is a **vendored third-party module** (documented in its header);
Elm's `--optimize` dead-code elimination strips the unused parts, so its size
is intentional.

Translation: `Translation.elm` is English-only — `tr` takes no language
argument and the 25 language tables were deleted. Ticket 21 then cut the union
down to the 56 constructors the surfaces above actually render: help,
template, word-count, theme, export-settings, save-state and account strings
went with their views, and each of those surfaces now hardcodes its English in
TypeScript. A string wanted by both sides is spelled on the side that renders
it, not shared.

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

The card-based machinery above is the only conflict machinery. The legacy
git-era one — `Doc/Data/Conflict.elm`, `Diff3.elm`,
`TreeStructure.setTreeWithConflicts`, `Data.conflictList`, `Data.resolve` —
was deleted by ticket 21: it had no caller, and `Diff3.diff3Merge` was a stub
returning `[]` that `conflictToMsg` would have joined into a card's content,
blanking it.

### 5.5 History

JS snapshots the full non-deleted card set on every content save
(`tree_snapshots` table, id `"<ts>:<treeId>"`): the newest version row per card
id, then the deleted cards dropped (ADR-0005 §1), stamped with the newest row
in the document's log — so a save that deletes a card gets a history entry of
its own instead of overwriting the one that still had the card. JS also pulls
server-side history metadata (`pullHistoryMeta`/`pullHistory`). `Doc.History`
wraps the snapshot list in a zipper for the header's history slider; restore
diffs the current card set against the chosen snapshot and emits add/delete
rows through the normal save path.

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
   `seed`, `isMac`, `currentTime`). A value that is missing, unparseable or not
   an object is a guest session (`readSessionData`): this is the first step of
   boot, so an unguarded parse here was a blank page (CODE_REVIEW.md S8).
2. **Open this account's database**, if the blob named one: `openUserDb(email)`
   in `doc.js`, whose name comes from `src/shared/local-db.js` (§6.2). There is
   no database before an account is known, so the `trees` count in step 3 is
   skipped when there is no stored email.
3. **Auto-login**: if there is no stored email or the local `trees` table is
   empty, ask `/me` (`session.js`'s `fetchAccount`), merge an account answer
   into the session blob, open the database of the account it names, and seed it
   with the server's document list. The answer is classified rather than
   trusted: JSON is an account; a 200 that is not JSON, or a 404, is a server
   without the endpoint; 401/403 is a server that has it and no session here;
   anything else is reported on the console once. Only the last of those is
   worth telling anyone about — the rest boot to the login page, which is a
   working app (ticket 38).
4. `setUserDbs(email)`: open this account's database (again — idempotent by
   name, and the switch point when the account has changed), start the
   session's metadata sync
   (`src/shared/metadata.js`), open the WebSocket, and subscribe a Dexie
   `liveQuery` on `trees` that pushes `documentListChanged` to Elm and hands
   each snapshot to that sync, which sends the unsynced rows (§6.3).
5. `Elm.Main.init({flags})`, then subscribe `gingko.ports.infoForOutside` to
   the `fromElm(tag, data)` dispatch table. A tag with no handler is reported as
   an unexpected message; a handler that fails — including the `async` ones,
   whose rejections used to reach nobody — is reported by tag, and reaches the
   user when the failure means a change did not persist
   (`src/shared/port-errors.js`).
6. Global listeners: `window.checkboxClicked` (used by rendered markdown),
   a `beforeunload` dirty guard, fullscreen-change, and print.

`ui.js` (`src/ui/index.ts`) registers the custom elements; `gw-textarea` is
registered from `doc-helpers.js`.

### 6.2 Storage inventory

| Store | Key/Table | Contents |
|---|---|---|
| localStorage | `gingko-session-storage` | session blob (email, sidebar, sortBy, …) — read as Elm flags |
| localStorage | `gingko-local-db-owner` | which account owns the legacy Dexie database `"db"` (its email hash), see below |
| localStorage | `gingko-local-store/<treeId>/settings` | per-document settings (`last-actives`, `theme`) |
| Dexie `trees` (PK `id`) | | document metadata rows (`name`, `owner`, timestamps, `synced`) |
| Dexie `cards` (PK `updatedAt`) | | append-only card version rows (§5.1) |
| Dexie `tree_snapshots` (PK `snapshot`) | | local + pulled history snapshots |
| ImmortalDB | `backup-snapshot:<treeId>` | write-only plain-text backup of newest card versions |

**One Dexie database per account** (`src/shared/local-db.js`). The name is
`db-<hash>`, where the hash is a 64-bit non-cryptographic hash (cyrb64) of the
lower-cased address: the whole database, not a per-row filter, so nothing an
account did not write can be read back, and each account's unsynced offline rows
survive a switch away and back. The address is hashed rather than spelled
because the name is readable through devtools and `indexedDB.databases()`, and
`database-download.js` puts it in the filename of an export a user attaches to a
bug report. `crypto.subtle` is not an option: it is undefined outside a secure
context, which a self-host on plain HTTP is.

Before ticket 27 there was one database called `"db"` for everyone, which was
harmless until logging out existed (ticket 04) and a leak the moment it did. The
migration is **adoption**: the first account to log in takes `"db"` as its own
and records its hash under `gingko-local-db-owner`; that account keeps opening
`"db"`, every other account opens `db-<hash>`. No rows are copied, so no upgrade
can be half-done, and an account that cannot record the claim (denied storage)
opens its own database rather than adopting on faith. The name derivation is
frozen by known-good literals in `tests/local-db.test.ts`: changing it is a
silent migration, because an account whose name moves finds no database
rather than a renamed one. The claim survives logout for the same reason —
an unclaimed `"db"` is adoptable (`tests/logout.test.ts`).

The two treeId-keyed stores above are *not* per account, deliberately. Note
that a treeId is **client**-minted, not server-issued: `RandomId.generate`
draws 7 base62 characters (`src/elm/RandomId.elm`), so two accounts sharing a
browser have no *guarantee* of distinct ids — the argument is that a clash
costs nothing. `backup-snapshot:<treeId>` has no read path anywhere in the
client (write-only, for a bug report), and
`gingko-local-store/<treeId>/settings` holds `last-actives` and `theme` — view
state, not content, and an unusable one already reads as "no settings yet".
Neither can surface another account's cards, and neither holds unsynced work:
that is all in Dexie, which *is* per account. Namespacing them would buy a
wrong theme and cost a migration of every per-document key ever written, plus
one for a store nothing reads. A document id is also legitimately shared
between accounts when the document is (ticket 27's Comments).

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

On reconnect: the send queue drains, the unsynced `trees` rows are re-sent,
`rt:join` is re-sent for the open document, and Elm gets `SocketConnected`
(which re-triggers a push of unsynced deltas).

`SocketConnected` waits for both halves of "connected": the socket being open,
and Elm having been handed a document's cards. It does nothing on any other
state, and the socket is opened during boot *before* Elm is initialized, so it
used to be sent on a one-second timer instead (ticket 23, CODE_REVIEW.md S5).
It is sent once per open socket.

The queue and the metadata resend are two different mechanisms on purpose. The
queue holds messages that are **events** (`pull`, `pullHistoryMeta`,
`rt:join`), asked for while the socket was down and sent verbatim when it
returns. Document metadata is **state**: `src/shared/metadata.js` keeps the
`trees` table as the liveQuery last emitted it and derives the message from it
at send time, so a reconnect sends one message however long it was away and can
never carry a name the document has already been renamed away from. Queueing
one message per emission would do exactly that, and a server taking the last
message it received at face value would echo the older name back into Dexie
over the newer row. Reading the emission rather than querying Dexie on
reconnect is the same argument: a query is asynchronous, and a rename that
commits while it is in flight would be sent first and then undone by the older
state the query answers with.

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
regions. A card drag is the element's end to end: it reports the drop to Elm
as `gw-drop` and stops it propagating, and announces the drag itself as
`gw-drag-start` / `gw-drag-end` so `src/shared/drag.js` can tell it from text
dragged in from outside the app. `markdown.ts` renders card content with
`marked` (GFM + breaks) plus
a CriticMarkup preprocessor. `header.ts` and `sidebar.ts` are updated in place
for as long as they are on screen, so what a re-render *preserves* is part of
their contract; the help, word-count and template modals are built once and
dropped when they close. Both kinds follow the rules in `src/ui/README.md`.

One element is rendered from two places rather than one: `save-indicator.ts`
(`<gw-save-indicator>`) is inside the header's title span *and* in
`Doc/Fullscreen.elm`'s button column. Elm encodes the state once
(`Doc.UI.encodeSaveState`) and the header only forwards its `save` attribute
through, so neither surface can come to disagree about what "saved" says — they
had, as two separate implementations (CODE_REVIEW.md S1).

---

## 7. Port contract reference

One outgoing port (`infoForOutside`, tagged `{tag, data}`) and several
incoming ones (`docMsgs`, `appMsgs`, `documentListChanged`, `importComplete`,
`userLoggedInMsg`, `userLoggedOutMsg`, `userSettingsChange`).

**Live Elm → JS tags** — all 28 of `Outgoing.Msg`, every one of them with a
producer in `src/elm`: `StoreUser`, `SaveUserSetting`, `Alert`, `SetDirty`,
`DragDone`, `ConfirmCancelCard`, `InitDocument`, `LoadDocument`,
`GetDocumentList`, `RequestDelete`, `RenameDocument`, `SaveCardBased`,
`SaveImportedTree`, `PushDeltas`,
`SendCollabState`, `ScrollCards`,
`CopyCurrentSubtree`, `CopyToClipboard`, `SelectAll`, `TextSurround`,
`InsertMarkdownLink`, `SetCursorPosition`, `HistorySlider`,
`SetSidebarState`, `SaveThemeSetting`, `Print`,
`ConsoleLogRequested`, `LogoutUser`.

**Every tag is spelled the same on both sides.** It was not: Elm's
`Outgoing.SaveImportedTree` sent the JS tag `SaveCardBasedTree`, so a grep for
either name found only one end of the message (CODE_REVIEW.md S2). Ticket 24
made both `SaveImportedTree` — the name says what the message does, and no
longer reads as a variant of `SaveCardBased`, which is a different message. A
new tag that disagrees with its constructor is the same bug again.

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
`DragExternalStarted`, `DropExternal`, `Paste`, `PasteInto`,
`FieldChanged`, `AutoSaveRequested`, `FullscreenCardFocused`,
`FullscreenChanged`, `TextCursor`,
`ClickedOutsideCard`, `CheckboxClicked`, `Keyboard`, `WillPrint`,
`RecvCollabState`, `RecvCollabUsers`, `CollaboratorDisconnected`;
`appMsgs` — `SocketConnected`, `CardDataReceived`, `HistoryDataReceived`,
`PushOk`, `PushError`, `MetadataUpdate`, `ErrorAlert`, `NotFound`.

**Both lists are now exhaustive in both directions**: every tag above has a
live sender *and* a live handler, and there are no others. Ticket 21 removed
the Elm ends that had no other side (`DragStart`/`DragStarted`, the elm-dnd
path; `ScrollFullscreenCards`; `SavedRemotely`; and the nine outgoing tags no
Elm code constructed), and ticket 22 removed the `doc.js` halves of the same
pairs — the `SaveCardBasedMigration`, `ScrollFullscreenCards`, `DragStart`
(with the `DragStarted` send inside it), `SetField`, `SetFullscreen`,
`RequestFullscreen`, `UpdateCommits`, `InitBeamer` and `SocketSend` handlers,
and `pushSuccessHandler`.

That symmetry is load-bearing rather than tidy, in both directions. An unknown
*incoming* tag is not ignored: `Page.Doc.Incoming`'s catch-all returns
`Err "Unexpected info from outside: <tag>"`, which reaches `onError` and
surfaces as a toast (ticket 18). An *outgoing* tag with no handler is likewise
reported — `doc.js`'s dispatch says "Unexpected message from Elm", and
`port-errors.js` decides whether the user hears about it — so a handler kept
for a tag that can no longer arrive is not inert, it is a claim about this
table that has stopped being true.

`screenfull` survives the removal of the two fullscreen *request* handlers: its
`change` event is still a live `FullscreenChanged` sender, so the app learns
about a fullscreen it never asks for (F11, or the browser's own chrome).

---

## 8. CI and testing state

One workflow, `.github/workflows/ci.yml`, runs on every push and PR to
`selfhost`: `bun install --frozen-lockfile`, a check that `package-lock.json`
is still in sync with `package.json` (ADR-0004), `config-check`, `bun run
typecheck`, `bun run newbuild`, then `bun run test:elm` and `bun run test:ts`.

`bun run typecheck` (`tsc -p src/ui/tsconfig.json`, strict, no emit) is the only
step that reads a type annotation — `bun test` and esbuild both strip types
without checking them — and it is new in ticket 22: `src/ui/README.md` had
documented the gate for months while `typescript` was not a dependency and
nothing in `ci.yml` ran it (CODE_REVIEW.md S11). `src/ui/README.md` says how to
confirm the gate is real, which matters because an unsupported
`moduleResolution` silently degrades cross-module imports to `any` rather than
failing.

The upstream
Electron-era `build.yml` and `master`-only `web-deploy.yml` are deleted, as is
the phantom `@playwright/test` devDependency.

Tests live in `tests/`: `*.elm` for elm-test (`Doc.Data`, `Session`) and
`*.test.ts` for bun test (custom elements against jsdom, the extracted
sequences in `src/shared/stamps.js`, `src/shared/session.js`,
`src/shared/save.js`, `src/shared/drag.js`, `src/shared/metadata.js`,
`src/shared/cards.js`, `src/shared/documents.js`, `src/shared/port-errors.js`,
`src/shared/local-db.js` and `doc-helpers.js`'s `whenReady`, and the build's
`config-check` / `elm-postprocess` seams). The pre-agreed seams are ADR-0001's.
