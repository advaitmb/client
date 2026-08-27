# Code Review — issues, bugs, and improvement opportunities (`selfhost` branch)

Full-codebase review performed 2026-08-27. Every finding below was verified
against the code (file:line references are to this branch). Companion
architecture documentation: [ARCHITECTURE.md](./ARCHITECTURE.md).

Severity legend — **CRITICAL**: security or guaranteed loss of core function;
**HIGH**: data loss / sync corruption; **BUG**: incorrect behavior a user can
hit; **SMELL**: dead code, drift, fragility; **IMPROVEMENT**: performance or
maintainability.

> ## Status: every finding below is resolved
>
> This document is kept as the **historical catalog** — the text of each
> finding describes the code as it was on 2026-08-27, and file:line references
> are to that state, not to the current branch. Do not read it as an open bug
> list.
>
> The findings were worked as tickets under
> `.scratch/selfhost-hardening/` (see `map.md` for the index and the
> decision log; each ticket's `## Answer` records what actually changed and
> why, including where a fix went deeper than the finding). The binding
> decisions taken along the way are ADRs in `docs/adr/`.
>
> | Findings | Ticket |
> |---|---|
> | C1 | 02 · sanitize rendered markdown |
> | C2 | 03 · remove the trial/payments ring |
> | C3 | 04 · a working logout path |
> | D1 D2 D10 S9 | 05 · newest-version-per-id everywhere |
> | D3 | 06 · conflict resolution discards the whole unsynced line |
> | D4 | 07 · the editor survives re-parenting |
> | D5 | 08 · self-describing save payloads (import race) |
> | D6 | 09 · offline metadata re-sent on reconnect |
> | D7 | 10 · numeric HLC stamp comparison |
> | D8 | 11 · position rebalancing |
> | D9 | 12 · history restore writes only what changes |
> | E1 E2 E3 | 13 · session preferences persist |
> | E4 | 14 · cold-loading any URL runs its commands |
> | E5 E6 E11 E13 E14 | 15 · small functional fixes |
> | E7 E8 E9 E15 | 16 · drag-drop correctness |
> | E10 E12 | 17 · theme restore, title input |
> | E16 | 18 · swallowed errors surface |
> | A1 A2 A3 A4 | 19 · auth pages |
> | B1 B2 B3 B6 | 01 · test infrastructure and CI |
> | B4 B5 B7–B13 | 20 · build scripts and docs match reality |
> | §6 (Elm) | 21 · dead-code purge, Elm (−2,201 lines) |
> | §6 (JS/TS) | 22 · dead-code purge, JS/TS; port contract made symmetric |
> | S5 S6 S7 S8 S13 | 23 · JS robustness |
> | S1 S2 S3 S4 S10 S12 | 24 · Elm consistency |
> | P1 P2 P3 P4 P5 | 25 · data-layer performance |
>
> Ticket 26 (a deploy workflow) was closed `wontfix` by the repo owner.
> Tickets 27–35 are **new** bugs found while fixing these — each traceable to
> the ticket whose work exposed it; see `map.md`.

---

## 1. Critical

**C1 · CRITICAL · Stored XSS in card markdown rendering.**
`src/ui/markdown.ts:82` — `holder.innerHTML = marked.parse(preprocess(src))`.
marked ≥5 has no sanitizer and passes raw inline HTML through, so a card
containing `<img src=x onerror=…>` executes in every viewer's session. Content
is not strictly self-authored: the app has collaborators (`rt` messages,
shared docs), JSON import (`gw-import-json`), and external text drag-drop
(`DropExternal`). `preprocess()` (markdown.ts:36–42) itself injects raw
`<ins>/<del>` tags for CriticMarkup, and the export preview renders through
the same element. No DOMPurify or equivalent exists in the bundle.
*Fix: sanitize `marked.parse` output (e.g. DOMPurify with an allowlist that
keeps `ins`/`del`/checkbox inputs) before assignment.*

**C2 · CRITICAL · The 14-day trial lockout survived the payments strip-down;
editing hard-locks 14 days after signup with no recourse.**
`src/elm/Page/App.elm:1504–1511` — every `setBlock Nothing` (doc load,
settings sync, history close) re-derives the block:
`if daysLeft <= 0 then Just (tr TrialExpired)`. Nothing on this branch ever
supplies a `paymentStatus`, so decoders default it to `Trial` +14 days
(`src/elm/Session.elm:333, 354, 413`), and `StoreUser` persists the expiry to
localStorage so it survives reloads. The only exit ramps were removed:
`Upgrade.view` is a stub returning `[]` (`Upgrade.elm:79`) and nothing ever
produces `ToggledUpgradeModal` (declared App.elm:383, handler :1161 — zero
producers). Result: every self-hosted user is permanently blocked from
editing two weeks after account creation.
*Fix: remove the trial block (and the `PaymentStatus`/`daysLeft` machinery).*

**C3 · CRITICAL · There is no logout path, and the port behind it is broken
anyway.**
No view, subscription, or TS event produces `LogoutRequested`
(`App.elm:332/434`; the account menu that hosted it was removed —
`ToggledAccountMenu` at App.elm:374/1077 also has zero producers). Even if it
fired, `doc.js`'s dispatch table has no `LogoutUser` case, so the port throws
"Unexpected message from Elm" (`src/elm/Outgoing.elm:76`, `doc.js:724–728`);
and no JS ever sends `userLoggedOutMsg`, so `Main.elm:390`'s subscription is
unreachable. Users cannot log out or switch accounts.

---

## 2. Data-integrity bugs (sync / persistence)

**D1 · HIGH · Deleting a subtree can delete cards that were moved *out* of
it.** `src/elm/Doc/Data.elm:784–800` — `getDescendants` scans **all** version
rows (`List.filter (\c -> c.parentId == Just id)`) with no
newest-version-per-id dedupe (contrast `getPosition`, Data.elm:698–700).
Because Dexie's `cards` PK is `updatedAt`, stale rows persist until push +
fast-forward. If card X was moved from parent A to B (old row still says
`parentId = A`, indefinitely while offline) and the user deletes A, `CTRmv`
(Data.elm:519–522) marks X's **newest** version deleted — X vanishes from B.

**D2 · HIGH · Merging cards re-parents stale and deleted child rows.**
`src/elm/Doc/Data.elm:608–675` — `childrenOfCurrent/Other` filter without
`deleted == False` and without newest-version dedupe. Consequences: position
offsets computed from invisible (deleted) children, and a fresh unsynced row
emitted for a stale row can become the newest version, yanking a child that
was moved elsewhere back under the merged parent.

**D3 · HIGH · Conflict resolution can resurrect discarded local edits.**
`src/elm/Doc/Data.elm:288–304` — `resolveConflicts` removes only
`versions.ours` = the *newest* unsynced row (`getOurs`, Data.elm:980–987).
Offline editing creates one unsynced row per save; choosing **Theirs** (or
**Original**) leaves the older unsynced rows in place, the card re-classifies
as `Unsynced`, and the next push sends the stale local content the user just
chose to discard.

**D4 · HIGH · Mid-edit tree changes silently disconnect the editor.**
`src/shared/doc-helpers.js:50–107` — `gw-textarea` binds its listeners once in
the constructor; `disconnectedCallback` removes them and `connectedCallback`
never re-adds them. `tree.ts` re-parents the reused editing-card element
whenever the `tree` attribute changes mid-edit (tree.ts:119–131), firing
disconnect+connect. After that, typing no longer emits
`FieldChanged`/`TextCursor` — Elm's field goes stale and the next save writes
old content. Reachable via a second tab, collaborator edits, or checkbox
toggles while a card is open.

**D5 · BUG · JSON import races the open document's state.**
`src/elm/Page/Import.elm:77–81` and `App.elm:1123–1124` batch
`SaveCardBased` with `SaveImportedTree` — but `Cmd.batch` order is
unspecified, and the JS `SaveCardBased` handler (doc.js:513–558) snapshots and
updates `dexie.trees` using the *global* `TREE_ID`, which only
`SaveCardBasedTree` sets. If `SaveCardBased` lands first it writes another
document's snapshot/timestamps (or errors on a fresh session where `TREE_ID`
is undefined).

**D6 · BUG · Metadata changed offline is never re-sent on reconnect.**
`src/shared/doc.js:187–190` — the trees liveQuery sends unsynced rows with
`wsSend('trees', unsyncedTrees, false)`; the `false` means "don't queue if the
socket is down", and `ws.onopen` only drains the explicit queue and re-joins
`rt:`. A rename/delete performed offline sits unsynced until some unrelated
tree-table change or a reload.

**D7 · BUG · HLC stamps are compared lexicographically in JS with an unpadded
counter.** `src/shared/doc.js:822` (`getChk`: `.sort().reverse()[0]`), `:261`
(`_.max(data.d)`), `:836` (`sortBy('updatedAt')`). The HLC library emits
`"${ts}:${counter}:${id}"` with an **unpadded** counter, and a multi-card save
stamps many rows in the same millisecond — so `…:10:x` sorts before `…:9:y`.
Consequences: too-low pull checkpoints (redundant re-pulls) and
`saveBackupToImmortalDB` picking a stale version for the backup. Elm's
`UpdatedAt` parses and compares numerically, so this is JS-side only.

**D8 · BUG · Fractional card positions are never rebalanced.**
`src/elm/Doc/Data.elm:713–727` — midpoint insertion halves the gap every time;
~50 inserts at the same spot exhaust Float precision, after which siblings
share a position and order becomes unstable (ties broken by row order). Also,
`localSave` computes positions from data that only refreshes after the
Dexie round-trip, so two rapid inserts can mint identical positions. No
rebalancing code exists anywhere.

**D9 · BUG · History restore re-deletes already-deleted cards and pushes
empty deltas.** `src/elm/Doc/Data.elm:126–159` — `mergeRestoreData` marks
every card absent from the snapshot deleted, including rows already
`deleted = True` (snapshots exclude deleted cards), appending a fresh unsynced
deletion row per ever-deleted card on each restore; `cardDelta` then emits
`Delta … []` for them, which `pushDelta` sends anyway.

**D10 · BUG · `resolveDeleteConflicts`' second limb is provably dead.**
`src/elm/Doc/Data.elm:1084–1088` — `theirDeletionsLocalVersions` filters ids
*out of* the very set they were derived from, so it is always `[]`,
contradicting the comment ("add new unsynced undeleted versions…"). Either
the filter is inverted or the `toAdd` limb is vestigial.

---

## 3. Functional bugs — Elm application

**E1 · BUG · Closing the sidebar records it as open.**
`src/elm/Page/App.elm:736–744` — both branches call
`Session.setFileOpen True`; the closed branch should pass `False`. Any
re-init of Page.App (navigating docs, deleting the current doc) and the
loading spinner then render the sidebar open again until a full reload.

**E2 · BUG · "Reopen last document" is dead: `lastDocId` is decoded and then
discarded.** `src/elm/Session.elm:327/344/357` — the decoder binds
`lastDocId` to `_` and hardcodes `Nothing`; nothing else sets it, so
`App.init`'s redirect branch (App.elm:198–200) is unreachable and `/` always
lands on the doc list.

**E3 · BUG · Logging in resets `shortcutTrayOpen` and `sortBy` preferences.**
`src/elm/Session.elm:405–416` — `responseDecoder` hardcodes `True` /
`ModifiedAt` instead of decoding them (the flags decoder at :355–356 reads
both correctly); `storeLogin` then persists the clobbered values.

**E4 · BUG · Cold-loading an unhandled URL yields a page with no init
commands.** `src/elm/Main.elm:54` — `init` discards the initial page's `Cmd`
(`( initModel, _ ) = …`); `handleUrlChange` branches like `[dbName, _]`
(Main.elm:127–128) and the guest fallthrough return `Cmd.none`, so e.g. a
two-segment `Route.Doc`-style URL boots to a spinner whose
`GetDocumentList` never ran, until an unrelated `documentListChanged` push
redirects to the *most recently updated* doc instead of the one in the URL.

**E5 · BUG · A blocked document still broadcasts phantom "editing" collab
state.** `src/elm/Page/Doc.elm:1138–1158` — `preventIfBlocked` reverts the
model but the subsequent `|> andThen (updateCollabState …)` still sends
`SendCollabState (CollabEditing …)`; collaborators see an editor that isn't
there. (`insert` at Doc.elm:1705 orders the guard correctly — the pattern is
inconsistent.)

**E6 · BUG · Esc-from-fullscreen is broken: `FullscreenChanged` has no
decoder.** `src/shared/doc.js:380` sends it on every fullscreen change;
`src/elm/Page/Doc/Incoming.elm` has no case, so it lands in `onError` and
logs "Unexpected info from outside" — Elm never learns the browser left
fullscreen.

**E7 · BUG · Same-parent downward drag-drops land one slot too far.**
`src/elm/Page/Doc.elm:297–309` — `CardDropped` computes the drop index on the
*unpruned* tree (the dragged card still counts), unlike the old elm-dnd path
which pruned at `DragStarted`. After `Mov` prunes and re-inserts, the card
lands one position below the intended slot (persisted positions agree, so it
sticks).

**E8 · BUG · Internal drags are reported to Elm as external, and drag flags
are never reset.** `src/shared/doc.js:910–915` — `document.ondragenter` fires
`DragExternalStarted` unless `draggingInternal` is set, but the only setter is
the dead elm-dnd `DragStart` port case (doc.js:594–601; its Elm producer's
view attributes are never rendered). Internal drops are `stopPropagation()`ed
inside `gw-tree` (tree.ts:377–384), so the document-level reset
(doc.js:990–1002) never runs, and `CardDropped` sends `SetDirty` but not
`DragDone` — both JS and Elm drag flags stay stale for the session.

**E9 · BUG · Dropping a card onto an open editing textarea pastes its raw
id.** `src/ui/tree.ts:334` sets `dataTransfer` `text/plain` to the card id
(the old path deliberately used `""`), and the document drop handler
(doc.js:938–941) returns early for textareas *without* `preventDefault`, so
the browser default-drops the 24-char id into the card being edited.

**E10 · BUG · Theme is persisted but never restored.**
`SaveThemeSetting` writes `theme` into the per-doc localStore
(doc.js:693–695), but nothing reads it back: `Page.Doc.Theme.decoder` has no
importers and `Model.theme` is hard-initialized to `Default` (App.elm:151).
Every reload resets the theme.

**E11 · BUG · Word-count "Session" row always equals "Total".**
`src/elm/Page/App.elm:1816` hardcodes `startingWordcount = 0` when opening
the modal; nothing records a session-start count, so
`sessionWords = documentWords - 0` (Doc/UI.elm:217, wordcount-modal.ts:52).

**E12 · BUG · Header title input discards in-progress typing every 9
seconds.** `src/ui/header.ts:127–131` — `attributeChangedCallback` only skips
re-render for `doc-title` while focused; the `save` attribute changes on the
9-second clock tick (App.elm:1995), triggering a full `render()` that rebuilds
the input from the last committed title. The caret is restored; the typed
text is not.

**E13 · BUG · Leaves/Column exports in OPML format write plain text into an
`.opml` file.** `src/elm/Page/Doc/Export.elm:83–102` — the wildcard branch
catches OPML for `ExportLeaves`/`ExportCurrentColumn` and joins contents as
plain text; `command` (:42–43) then saves it as `.opml` with the invalid MIME
string `"application/xml, text/xml, text/x-opml"`.

**E14 · BUG · Placeholder translation strings render literally.**
`src/elm/Translation.elm:612–614, 800–806` — `AltKey → "AltKey"`,
`ParenNumber → "ParenNumber"`, `SetHeadingLevel → "SetHeadingLevel"` are
rendered by the live edit-mode shortcut tray (`Doc/UI.elm:427, 392`): users
see "AltKey ParenNumber SetHeadingLevel". The TS help modal fixed the same
strings on its side (help-modal.ts:57–59); the Elm tray was never updated.

**E15 · BUG · Drag auto-scroll throws every 15 ms over non-column areas.**
`src/shared/doc.js:950–964` — `path.filter(…'column')[0]` can be `undefined`
(header/sidebar hover), and the `setInterval` body dereferences it.

**E16 · BUG · Errors swallowed silently, inconsistent with the app's own
toast pattern.** `App.elm:1022–1023` (`Exported _ (Err _)` — failed DOCX
export, no feedback); `App.elm:1113–1114` (invalid JSON import file, no
feedback); `Doc/Data.elm:261–262, 1132–1133, 1385–1386` (malformed card data /
push ack / history payloads silently freeze or no-op); `doc.js:339–341` (the
entire `ws.onmessage` switch wrapped in `catch { console.log }` — a failed
`bulkPut` of pulled cards, i.e. lost incoming sync data, is only console
noise); `doc.js:1053–1065` (clipboard failures other than permission-denied
swallowed or re-thrown inside the catch).

---

## 4. Auth pages

**A1 · BUG · "Forgot your Password?" is a dead link.**
`src/elm/Page/Login.elm:246` links `/forgot-password`; `Main.handleUrlChange`
has no such branch (guest fallthrough no-ops), and the supporting
`Session.requestForgotPassword`/`requestResetPassword` (Session.elm:498/514)
have zero callers.

**A2 · BUG · Login enforces a 7-character password minimum and stacks
contradictory errors.** `src/elm/Page/Login.elm:150–159` — `Validate.all`
combines a `< 7` rule with `ifBlank`, so a blank password shows both
messages, and any legitimate account with a shorter password can never
submit. A length rule belongs on signup only (Signup uses `firstError`
correctly).

**A3 · BUG (a11y) · Signup labels point at misspelled ids.**
`src/elm/Page/Signup.elm:220/232` — `for "singup-email"` / `for
"singup-password"` vs ids `signup-email`/`signup-password`; labels are not
associated with their inputs.

**A4 · SMELL · Stale SaaS-era auth copy.** Login 401 message still warns
about gingkoapp.com accounts (Login.elm:136); signup 409 says "Username
already exists" for an email field (Signup.elm:310); the signup mailing-list
opt-in + `subscribed` POST field (Signup.elm:250, Session.elm:456) is
marketing plumbing on a self-hosted build.

---

## 5. Build, CI, config, docs

**B1 · BUG · `config-check.js` can never fail.** On a key mismatch it writes
to stderr but never `process.exit(1)` (verified: missing keys → exit 0). Both
workflows use it as a gate.

**B2 · BUG · `build.yml` runs on every push and cannot succeed.**
`on: push` with no branch filter; final steps call `npm run build` / `npm run
release`, which don't exist; targets retired runners (`ubuntu-20.04`,
`macos-11`), EOL Node 16, mutable `@master` action refs. This Electron-era
workflow should be deleted on this fork (it also keeps the
`CLIENT_CONFIG_PASSPHRASE`/`CSC_*`/`APPLE_ID*` secret wiring alive).

**B3 · BUG · `web-deploy.yml` references removed test infra.** `bun run test`
(no `test` script), `bunx cypress run` (cypress removed, no specs), and copies
a `hidden-config.js` nothing reads. It only fires on `master`, so this branch
has **zero functioning CI** — while the README badge still points at it.

**B4 · BUG (docs drift) · README and CONTRIBUTING describe commands that
don't exist.** README's only dev command is `bun run newwatch` (no such
script; there is no watch/dev script at all) and it still mandates CouchDB,
which `doc.js:171–174` explicitly nulls out. CONTRIBUTING references `npm
start` / `npm run electron` and the `master` branch.

**B5 · BUG · The build is silently Bun-only.** `esbuild.mjs:8` uses Bun's
`import.meta.dir`; under Node it crashes with an opaque AliasPlugin error
(verified). `import.meta.dirname` (Node ≥ 20.11) or
`fileURLToPath(import.meta.url)` would make it runtime-agnostic. The
`result.errors` branch at esbuild.mjs:28–33 is dead — `esbuild.build()`
rejects on failure.

**B6 · SMELL · Dual lockfiles.** `bun.lockb` (canonical for the build) and
`package-lock.json` (used by the cloud-session hook and the dead `build.yml`)
coexist; the npm one had already drifted badly (it still resolved the
pre-slim tree — Sentry, Electron, PouchDB — until regenerated during this
review). Pick one, or add a consistency check.

**B7 · SMELL · Upstream's encrypted config blob is inherited for no
purpose.** `client.config.js.gpg` (symmetric AES256, offline-brute-forceable,
passphrase in an upstream GitHub secret) + `config_decrypt.sh` serve only the
dead `build.yml`. The plaintext is low-sensitivity (4 URLs/emails), but a
self-host fork should delete all three.

**B8 · SMELL · `database-download.html` pulls unpinned scripts from unpkg**
(`<script src="https://unpkg.com/dexie">`, no version, no SRI) — an external
CDN dependency in a page whose job is exporting the user's entire local
database, on a branch whose index.html boasts "no external request".

**B9 · SMELL · Dead static files ship into the deploy root.** `cp -r
src/static/. web/` copies Electron-era files nothing references:
`email.html` (uses `require('electron')`), `list.html`, `support.html`,
`license.html`, `desktop.css`, `modal.css`, `faq-modal.css`,
`videos-modal.css`, `trial-modal.css`, `shortcuts-modal.css`,
`support-modal.css`, `help-menu.png`, `new-doc.png`.

**B10 · SMELL · Phantom test dependency and stale ignores.**
`@playwright/test` is pinned with zero tests/config in the repo; `.gitignore`
still carries entries for cypress artifacts, `app/*`, `src/migration/*`,
`src/legacy-import/*` — none exist. Meanwhile three `.DS_Store` files are
*tracked* and `.gitignore` has no `.DS_Store` entry.

**B11 · SMELL · Electron residue in package.json and .vscode.** The whole
`"build"` electron-builder block (references `./src/bin/${os}/`, which
doesn't exist), the orphaned `minifyjs` script, `.vscode/launch.json`
launching `app\electron.js`, `.vscode/settings.json` pointing at an Elm
0.18-era `elm-make` binary.

**B12 · IMPROVEMENT · Tailwind doesn't scan the interface layer.**
`tailwind.config.js:6` — `content: ["./src/elm/**/*.elm"]` only. Today's
`src/ui/*.ts` uses only semantic classes, but the first Tailwind utility
typed into a TS file will be silently purged. Add `./src/ui/**/*.ts`.

**B13 · IMPROVEMENT · Cosmetics.** `elm-watch.json`'s target is literally
`"My target name"`; `elm-postprocess.mjs` skips placeholder substitution
outside `--optimize`, so dev builds show raw `{%SUPPORT_EMAIL%}` in the UI.

---

## 6. Dead code inventory (strip-down residue)

The removal pattern is consistent: producers (views/menus) were deleted but
Msg constructors, handlers, ports, routes, and plumbing remain. Verified
zero-caller items:

**Payments/trial ring:** `ModalState.UpgradeModal` + `UpgradeModalMsg`
handling incl. `CheckoutClicked` (App.elm:1174–1199), `ToggledUpgradeModal`
(App.elm:383), `Route.Upgrade` (Route.elm:16), outgoing
`CheckoutButtonClicked`/`FlashPrice` (Outgoing.elm:46/62 — the JS
`FlashPrice` handler null-derefs on a element that no longer exists,
doc.js:622–624), `Session.paymentStatus/upgradeModel/updateUpgrade/daysLeft`,
`Chadtech/elm-money` pinned in elm.json with zero imports. (Remove together
with C2.)

**Dead outgoing tags (never sent):** `NoDataToSave`, `SaveToFile`,
`ExportToFile`, `SetField`, `SetFullscreen`, `PositionTourStep`,
`UpdateCommits`, `RequestFullscreen`, `SaveCardBasedMigration`
(Outgoing.elm:28–58). **JS handlers with no Elm sender:** `InitBeamer`,
`SocketSend` (doc.js:714–718), `SaveCardBasedMigration` (doc.js:570),
`UpdateCommits` no-op (doc.js:656). **Dead JS→Elm senders:** `SavedRemotely`'s
sender was removed (`pushSuccessHandler`, doc.js:904–906, uncalled), so the
Elm branch at App.elm:1933 is dead; `userLoggedOutMsg` is never sent.

**Dead custom-element contract ends:** `gw-drag-start`/`gw-drag-end` emitted
but never listened to (tree.ts:337/344); sidebar `context-target` attribute
documented/styled but never set (sidebar.ts:21/213).

**Dead Elm modules/functions:** `UI/Collaborators.elm` (only referenced by
two unused imports); `Feature.elm` (`enabled` uncalled); `Features` variants
decoded into a list nobody reads; the whole legacy conflict machinery —
`Doc/Data/Conflict.elm`, `Diff3.elm` (`diff3Merge` is a stub returning `[]`;
its only consumer would silently blank a card), `TreeStructure.
setTreeWithConflicts`/`conflictToMsg`, `Data.conflictList` (always `[]`),
`Data.resolve` (identity), plus `jinjor/elm-diff`; `Coders.elm:152–263` (the
private `<gingko-card>` parser block); `SharedUI.modalWrapper` (mirrored by
modal.ts); `Doc.List.current/isLoading/viewSwitcher`;
`Doc.Metadata.decoderImport` (and transitively `RandomId.fromObjectId`);
`Session.isFirstRun/endFirstRun/public/requestForgotPassword/
requestResetPassword`; `GlobalData.public`; `Import.Single.encode` (contains
`( "data", Enc.null ) --TODO`); `Doc.UI.countWords/fillet/
viewWordcountProgress`; `Page.Doc.publicTreeLoaded/dropRegions/viewContent`;
`UpdatedAt.uniqueBy`; `Data.parseUpdatedAt/prefixIds/getCardById`; nine
`*_tests_only` exports in Doc/Data.elm with no tests directory in the repo.

**Dead Msgs:** `Main.SettingsChanged` (Main.elm:243 — never produced, falls
into the catch-all; the real one lives in Page.App), `ClickedShowVideos`,
`CopyEmailClicked` (App.elm:371–372 — the latter still referencing
`{%SUPPORT_EMAIL%}` placeholders in dead branches).

**Dead types/fields:** `Types.VisibleViewMode`/`VisibleViewState`,
`dropIdToValue`, `ViewState.copiedTree` (never written),
`ViewState.clipboardTree` (write-only — paste always comes from the system
clipboard); `Page.Doc.ModelData.fileSearchField` (the live one is in
App.Model, itself tagged `-- TODO: not needed if switcher isn't open`).

**Dead JS:** `PULL_LOCK`, `savedObjectIds`, `userDbName` (written never
read), `treeToHtml` (doc.js:55/72/51/854); `container-web.js`'s PouchDB-era
`userStore`, `getInitialDocState`, `showMessageBox`; `doc-helpers.js`'s
`isEditTextarea`, `errorAlert`; the elm-dnd `DragStart` path on both sides;
`window.elmMessages` debug ring buffer; `elm-explorations/markdown` pinned in
elm.json with zero call sites.

**Dead translation keys:** 138 of 203 `TranslationId` constructors have no
call sites (help/template/wordcount/theme/upgrade sections) — their strings
now live hardcoded in the TS modals. ~700 removable lines.

**Degenerate leftovers:** one-armed `case model.modalState of _ -> …`
(App.elm:1270–1273) and two consecutive `case … of _ -> Sub.none`
subscriptions (App.elm:1987–1994); `viewModal` computes an unused
`ctrlOrCmd` (App.elm:1741); unused imports across Page/App.elm (Feature,
Features, File.Select, stray Html tags), Page/Doc.elm (AntIcons, Markdown,
UI.Collaborators, lazy2/4/6/8…), Doc/History.elm and Doc/List.elm
(view-era imports on now-logic-only modules), Page/Doc/Incoming.elm (File,
`Children(..)`, plus an empty `-- === TESTING ===` marker).

---

## 7. Smells and fragility

**S1 · Duplicated save indicator, already drifted.** `header.ts:57–86`
"mirrors" `Doc.UI.viewSaveIndicator` (UI.elm:35–108, still used by
fullscreen) but drops the "Database Error…" branch and the initial-load
special case. Any fix must now be made twice.

**S2 · Misleading name across the port boundary.** Elm's `SaveImportedTree`
sends JS tag `"SaveCardBasedTree"` (Outgoing.elm:102–103 vs doc.js:560) —
grep for either name misses the other side.

**S3 · `isOwner` defaults to False while the doc list loads**
(Session.elm:208–213), so owner-only UI (header `owner` attr, sidebar Delete)
flaps on startup; the double-negative definition (owner = not listed as
collaborator) invites misreading.

**S4 · `copyNaming` builds a regex from an unescaped, unanchored document
name** (Session.elm:160–188): names with regex metacharacters silently fall
back to `Regex.never` (copy keeps a colliding name); `"Doc"` also counts
`"My Doc"`; sparse numbering produces duplicate copy names.

**S5 · Timing hacks instead of signals.** `setTimeout(…, 1000)` before
`SocketConnected` (doc.js:214); 500 ms delay before `pullHistoryMeta`
(doc.js:830); 0/200 ms render guesses in `HistorySlider` (doc.js:665); 20 ms
`InitialActivation` delay (doc.js:799); the `renaming` double-blur hack
(doc.js:500); and a **permanent 800 ms `setInterval`** polling header
geometry (`syncUI`, doc.js:1264). doc.js also still reaches into ui-layer DOM
(`#history-slider`, `#history-icon`, `#document-header`).

**S6 · Listener leak on scroll.** `doc-helpers.js:544–554` adds a new
anonymous `scroll` listener to every column on **every** `ScrollCards`
message (i.e. every navigation keystroke) and never removes them.

**S7 · Port dispatch try/catch mislabels bugs and misses async failures.**
`doc.js:724–728` reports a throwing handler as "Unexpected message from Elm",
and since most handlers are async, their rejections (all the Dexie writes)
bypass the catch entirely. Same pattern at doc.js:477–486.

**S8 · Boot fragility.** `getSessionData` (doc.js:889–896) JSON.parses
localStorage with no try/catch as the first step of boot — a corrupted value
means a blank page (and the constant is named `sessionStorageKey` while
living in localStorage). `localStore.get` (container-web.js:44–51) would
null-deref if ever called before a write. `InitialActivation`
(doc.js:795–801) doesn't filter deleted rows and throws if no root card
exists.

**S9 · `conflictToTree` depends on JS row order.** `Doc/Data.elm:317–326`
dedupes via `Dict.fromList` (last-in wins) instead of newest-version-wins
like `toTrees` — correct only while Dexie returns ascending-`updatedAt`
order.

**S10 · Encoder/decoder asymmetries.** `Doc.Metadata.encode` drops
`collaborators` that `decoder` requires (Metadata.elm:124–144 vs 70–86 —
re-decode silently resets them to `[]`); `UpdatedAt.toString zero` produces
`"0"` which the module's own parser rejects (UpdatedAt.elm:148–171); the dead
`Conflict.opToValue`/`opDecoder` pair could never round-trip
(Conflict.elm:109–144).

**S11 · `src/ui/README.md` is stale and now misleading** — its "what has
moved" table lists only the help modal and claims the tree/header/sidebar/
modals are "still in Elm"; all have since moved (index.ts:12–22).

**S12 · Odd DOM idioms.** Empty-state uses a broken `<img src="" onerror>`
to fire a message (DocMessage.elm:22); toasts wrapped in an attribute-less
extra div (UI.elm:532); clickable non-button divs are pervasive (breadcrumbs,
mobile buttons, show/hide password, empty-state button) — none
keyboard-operable.

**S13 · Hidden couplings.** `CARD_DATA = Symbol.for("cardbased")` defined
independently in doc.js:50 and doc-helpers.js:27; `help-modal.ts` hand-rolls
the modal chrome (and duplicates `CLOSE_ICON`) that `modal.ts`'s `mountModal`
exists to provide; `tree.ts:94–99`'s `disconnectedCallback` clears `cards`/
`contents` but not `data`/`editingId`/`dragged`; sidebar logo uses a relative
URL (`../gingko-leaf-logo.svg`, sidebar.ts:125) that only resolves on shallow
routes; `wordcount-modal.ts` declares no `observedAttributes` (harmless today
— recreated per open).

---

## 8. Performance improvements

**P1 · O(n²) hot paths on every save/receive.** Every keystroke-save
round-trips through `cardDataReceived`, which runs `toTree`/`treeHelper`
(each node filters the entire row list), `getSyncState`'s pairwise
`gatherWith` grouping, and (on push) `toDelta` re-filtering all rows per id
(Doc/Data.elm:775/834/1172). `getDescendants` also rescans the full list per
node without deduping ids. A `Dict` keyed by id / children-by-parentId would
make all of these near-linear; matters for multi-thousand-card documents.

**P2 · Sort-to-take-max on the hot path.** `lastSavedTime`/`lastSyncedTime`
(Data.elm:162–191) sort the whole list to take a head on every data receive
(and `UpdatedAt.maximum` is itself sort-then-head).

**P3 · Duplicated, per-card-recompiled search regex.** `searchFilter` exists
verbatim twice (Page/Doc.elm:167–181 vs 2157–2171) with subtly different
column handling, recompiling the regex per card.

**P4 · `saveCard`/`saveCardIfEditing` triplicate the same logic**
(Page/Doc.elm:1323–1445) and the split-card shortcuts use two different
idioms for the same operation.

**P5 · Lazy-view key mismatch.** `lazy3 treeView` keys on `isMac` but
`treeView` ignores that parameter (Page/Doc.elm:2112/2151) — a leftover that
defeats the reader's expectations, though laziness still works.

---

## 9. Notes — checked and found fine

- All live incoming port tags on both channels have decoder branches
  (except `FullscreenChanged`, E6); unknown tags route to a console log.
- `Toast.elm`'s 886 lines are a documented, deliberately-unabridged vendored
  module; Elm's `--optimize` DCE strips the unused parts (byte-identical
  output verified upstream per its header comment).
- The "odd" dependency versions are real: `marked` 18.0.11 and
  `@playwright/test` 1.62.1 are the current releases; all installed versions
  satisfy their specs. All 11 runtime dependencies are genuinely imported.
- The kernel-replacement machinery (patched virtual-dom for third-party DOM
  mutation tolerance) verifies fingerprints and versions correctly.
- Keyboard move/merge index math is consistent with prune-then-insert
  semantics; `Main.handleUrlChange` pattern order is correct.
