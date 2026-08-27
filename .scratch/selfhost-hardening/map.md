# Selfhost hardening — wayfinder map

## Destination

Every finding in [docs/CODE_REVIEW.md](../../docs/CODE_REVIEW.md) resolved:
the selfhost fork is safe (no XSS, no trial lockout, working logout), sync is
correct under tests, CI is real and green, and the strip-down residue is gone.

## Decisions so far

- ADR-0001 — testing stack (elm-test + bun test) and the three pre-agreed
  TDD seams; CI shape.
- ADR-0002 — trial/payments machinery is removed, not bypassed.
- ADR-0003 — all markdown-derived HTML goes through one DOMPurify allowlist.
- ADR-0004 — Bun is canonical; package-lock.json kept in sync, CI-checked.
- ADR-0005 — sync invariants: newest-version-per-id, conflict resolution
  discards the whole unsynced line, numeric stamp comparison.
- Tracker: local markdown under `.scratch/` (GitHub Issues disabled on repo).
- Ticket 01 resolved — test infra + CI live: `bun run test` (elm-test 3,
  bun test 7), config-check is a real gate, `.github/workflows/ci.yml` green
  on `selfhost`; `build.yml`/`web-deploy.yml` deleted. Details in
  `issues/01-test-infrastructure.md`.
- Ticket 02 resolved — C1 closed: `renderMarkdown()` in `src/ui/markdown.ts`
  (marked → DOMPurify with one explicit allowlist) is the only path to
  `innerHTML`, and both Elm call sites render through `<gw-markdown>`. The
  bun-test DOM moved happy-dom → jsdom because happy-dom cannot run DOMPurify
  (`Node.prototype.nodeName` is `''`; `NodeIterator` dies on removal), so the
  harness could not tell a working sanitizer from a missing one. Details in
  `issues/02-sanitize-markdown.md`.
- Ticket 03 resolved — payments/trial ring removed per ADR-0002 (trial block
  derivation, `PaymentStatus`/`daysLeft`, upgrade modal ring, `Route.Upgrade`,
  `Upgrade.elm`, `FlashPrice`/`CheckoutButtonClicked` + JS handler,
  `Chadtech/elm-money`); stale stored `paymentStatus` is ignored and dropped on
  next store; `setBlock` is history-view only. Unblocks 21 and 22. Details in
  `issues/03-remove-trial-lockout.md`.
- Ticket 07 resolved — `gw-textarea`'s listener lifecycle is symmetric and
  idempotent (`_bindListeners`/`_unbindListeners` driven by
  connected/disconnected), the document click handler is tracked per instance,
  and `start-value` seeds the textarea on first connect only, so a mid-edit
  re-parent by `tree.ts` no longer drops keystrokes or reverts in-flight text.
  7 tests at seam 3 in `tests/textarea.test.ts`. Details in
  `issues/07-editor-reconnect.md`.
- Ticket 05 resolved — every version-row scan in `Doc/Data.elm` goes through
  `newestPerId`/`newestVisible` per ADR-0005 §1, so subtree delete keeps
  moved-away cards (D1), merges neither re-parent stale children nor offset by
  deleted ones (D2), and the conflict tree is order-independent (S9).
  `resolveDeleteConflicts`' dead `toAdd` limb is **removed**, not repaired:
  inverting its filter would have pushed pre-deletion content over the local
  edit that delete-vs-edit resolution exists to keep — the surviving
  `toRemove` already yields `UndelOp` + our edit. 5 new tests at seam 1.
  Details in `issues/05-newest-version-dedupe.md`.
- Ticket 10 resolved — D7 closed: stamp ordering lives in one pure module,
  `src/shared/stamps.js` (seam 2), whose `compareStamps` orders numerically by
  timestamp then counter then hash, mirroring `UpdatedAt.elm` (Elm's `"0"`
  zero encoding included). `doc.js` delegates all four stamp orderings to it —
  `maxStamp` for `pushOk`, `computeCheckpoint` for both pull checkpoints
  (`getChk` deleted), `newestVersionPerId` for the ImmortalDB backup — so a
  12-card save no longer re-pulls its two-digit-counter rows or backs up a
  stale card version. 9 tests in `tests/stamps.test.ts`. Details in
  `issues/10-hlc-numeric-comparison.md`.
- Ticket 04 resolved — C3 closed: logout is a real chain again —
  `<gw-sidebar>`'s new bottom-of-rail button emits `gw-logout` →
  `Page.App.LogoutRequested` (which now refuses while the document is dirty,
  sharing the router's alert via `SharedUI.unsavedChangesAlert`) →
  `Session.logout` → the previously unhandled `LogoutUser` tag → new
  `src/shared/session.js` (verified POST `/logout`, clear
  `gingko-session-storage`, doc.js's new `stopSyncing`) → `userLoggedOutMsg`,
  which finally reaches `Main.UserLoggedOut`. Every step is best-effort, so a
  down or out-of-date server cannot trap a self-host user in a session;
  handing back to Elm rather than reloading `/login` keeps boot auto-login
  (`/me`) from undoing the logout. **Local data is kept** — unsynced rows are
  the only copy of offline work, so logout is never a delete; the flip side
  (one global Dexie `"db"`, so a switched-to account still sees the previous
  document list) is a schema property to fix at login, not at logout. 12 tests
  (4 at seam 3, 8 at a new **seam 4** the ADR now records for session
  sequences extracted from `doc.js`). Details in `issues/04-logout.md`.
- Ticket 06 resolved — D3 closed per ADR-0005 §2: `resolveConflicts` now sees
  the card rows (not just the conflict versions) and removes **every** unsynced
  row of the conflicted ids for Theirs and Original, all but the winning
  `versions.ours` row for Ours. Before, only the newest was removed, so the
  older offline saves re-classified the card as `Unsynced` and the next push
  sent content the user had just discarded ("Edit 2", in the red test).
  Removals stay confined to the conflicted ids, so another card's unsynced work
  still pushes. `cardDataReceived`'s auto-resolve gate **still gates
  correctly** (only `toRemove` can be non-empty since ticket 05, and it is
  non-empty exactly for auto-resolved delete conflicts); it is now one named
  check over all four staged lists so a future limb can't fall through it.
  3 new tests at seam 1. Details in `issues/06-conflict-resolution-discard.md`.
- Ticket 13 resolved — E1/E2/E3 were one defect in three places: a preference
  written by one path and read back by another with a constant in between. The
  sidebar's two halves now share one flag (`Page.App.sidebarIsOpen`);
  `lastDocId` decodes *and* is written (`Session.storeLastDocId`, called when a
  document opens, cleared when the remembered document turns out to be gone, so
  `/` can't loop into a 404); a login decodes `shortcutTrayOpen`/`sortBy` and
  defaults to what the user already had — which is why those two preferences
  moved into `SessionData`, the client-owned half a guest session carries
  across a logout. Self-host's own login path (doc.js merging `/me`) had the
  same defect and now protects client-owned keys (`mergeUserIntoSession`).
  Review of the diff also found `Session.encode` — the blob `StoreUser`
  *replaces* — dropping `sidebarOpen`/`lastDocId`, so logging in forgot E1's
  and E2's preferences too; it is now lossless, pinned by a round trip.
  ADR-0001 gains seam 5 (`Session`'s stored-blob surface). 12 tests. Details in
  `issues/13-session-prefs.md`.
- Ticket 12 resolved — D9 closed: a restore stages a row only for cards whose
  **state** changes (`sameCardState`: content/parent/position/deleted, not the
  version stamp), so cards already deleted are left alone instead of collecting
  a fresh unsynced deletion row per restore, and an unchanged card is not
  re-staged; `restore` sends no save at all when nothing changed. Op-less
  deltas are dropped in `toDelta` — the one funnel every push and every test
  goes through, while `cardDelta` can emit one from two limbs — and
  `pushDeltas` (was `pushDelta`) sends no message when none survive: `dlts: []`
  is not a no-op either, the server reads `dlts[dlts.length - 1].ts` before it
  looks at the list. An op-less delta it *can* read is a "bump this card's
  stamp" write broadcast to every collaborator, which is what made the bug
  self-sustaining. 5 new tests at seam 1. Details in
  `issues/12-history-restore-deltas.md`.
- Ticket 20 resolved — B4, B5, B7–B13 all closed, nothing deferred: the
  README quickstart is re-verified from `git clean -xdf` (and now names
  `scripts/install_elm_pkgs.sh`, without which `elm make` hangs forever behind
  a zipball-blocking proxy), CONTRIBUTING/ARCHITECTURE §2–§3/§8/CLAUDE.md are
  re-synced, `esbuild.mjs` runs under Node too, and the Electron/SaaS residue
  is gone (gpg config blob, 13 static files, electron-builder block, phantom
  @playwright/test, stale ignores + .DS_Store, .vscode, ~230 lines of payments
  and account-menu CSS from tickets 03/04). `database-download.html` is
  **vendored** rather than pinned+SRI — dexie + dexie-export-import bundle as a
  third esbuild entry point, so it makes no external request like index.html.
  ADR-0001 gains **seam 6** (build-time gates): `tests/postprocess.test.ts` and
  ticket 01's `tests/config-check.test.ts` sat outside the pre-agreed list, and
  `elm-postprocess.mjs` now exposes a pure `substitutePlaceholders(code, conf)`
  per that seam's rule. `build/` (Electron packaging assets, now unreferenced)
  and the producerless `#migrate-modal`/`#help-dropdown`/`styles/github.css`
  are left for a follow-up, flagged in the ticket. Details in
  `issues/20-build-and-docs-cleanup.md`.
- Ticket 11 resolved — D8 closed: `getPosition` became `placeCard`, which
  refuses to split a sibling gap below `1.0e-6` (above `ulp x` for any position
  this model can hold) and renumbers the siblings onto whole numbers instead,
  leaving the new card's slot free — through the same save, so they sync as
  ordinary `mov` ops. The rapid-insert half is fixed by **memory, not
  tie-breaking**: `localSave` now returns the model as well as the save and
  carries the rows it staged until `cardDataReceived` clears them, because the
  position of a new card is a pure function of (sibling rows, index) and two
  saves in one round trip see the same rows — no deterministic rule can tell
  them apart without ordering the user's cards by hash. An out-of-range index
  (what the working tree hands down mid-flight) is now an append instead of
  minting position 0 onto the first sibling. Sibling sorts are `(position, id)`
  as defence against ties another client writes. 7 new tests at seam 1. Details
  in `issues/11-position-rebalancing.md`.
- Ticket 19 resolved — A1-A4 closed: the auth pages no longer speak for a
  hosted service. The forgot-password link and its two zero-caller request
  functions are **removed**, not implemented (owner's decision; the ticket
  records what to restore when the deployment can send email). Login dropped
  the 7-character minimum — whether a password is acceptable is the server's
  answer, and the rule locked out any account whose password predates it —
  which also ended the two-messages-for-one-blank-field stacking; the length
  rule stays on signup, where a password is chosen. Signup's labels point at
  their real input ids, its 409 talks about the email address it actually
  collects, and the mailing-list opt-in is gone end to end (checkbox, `Msg`,
  model field, request parameter, POST field — the server assigned
  `req.body.subscribed` to a variable it never read). `Session.fromLegacy`
  stayed: only its copy named gingkoapp.com. ADR-0001 gains seam 7 (auth
  forms, Elm, pure); 6 tests. Details in `issues/19-auth-pages.md`.
- Ticket 08 resolved — D5 closed by making the payload self-describing rather
  than sequencing the two import commands: `SaveCardBased` carries `treeId`,
  and the handler — extracted to `src/shared/save.js` — works on the document
  the payload names and reads no global. Sequencing would have made *this* pair
  of messages safe by timing while leaving the other five senders keyed off an
  ambient current document; a `treeId || TREE_ID` fallback would have kept the
  invariant unenforceable, so `treeId` is **required** and a payload without one
  is refused — which is also the guard against a fallback creeping back.
  `SaveCardBasedTree` stops claiming `TREE_ID`: the imported document is not on
  screen until Elm navigates, and every reader of that global means "on screen".
  Either arrival order now converges (`trees.update` on an absent row writes
  nothing, and the row the other message adds is unsynced from birth). ADR-0001
  seam 4 gains the rule for a sequence that writes the database: inject it and
  assert on the rows left behind. 8 new tests (7 at seam 4, 1 at seam 1), and
  `treeId` is now a required field of every save payload the seam-1 tests
  decode. Details in `issues/08-import-race.md`.
- Ticket 29 resolved — the follow-up ticket 11 filed on itself: a save is now
  built from the newest *state* of a card, not from the newest row of the log,
  so `CTUpd`/`CTMov`/`CTRmv`/`CTMrg` stopped writing back what the previous
  save had just changed (edit-after-move reverting the move, move-after-edit
  reverting the edit, a subtree delete missing a child moved in and taking one
  moved out, a merge dropping an edit and orphaning a child moved into the card
  it deletes). Two lookups do it — `stagedOrNewestRow` for one card,
  ticket 11's `visibleWithStaged` for the subtree walk and the merge's children
  — and `mergeCards` takes the visible cards rather than deriving them.
  Ticket 11's clear-on-any-echo is now clear-on-*known*-echo: the echo carries
  the open document's whole card set, so an id it has no row for cannot have
  been written and its staged row survives (a pull landing between two inserts
  used to forget it); for an id it does know, ours cannot be told from a
  superseding row without a stamp, and a phantom that outlives the DB's answer
  is worse than the fraction of a save the clear costs. Restore staging stays
  unstaged (modal, per 11). 9 new tests at seam 1, 8 red first. Details in
  `issues/29-stale-row-save-reverts.md`.
- Ticket 14 resolved — E4 closed: the URL→page decision is a pure total
  function in `Route` (`loggedInLanding`/`guestLanding` → a **landing**: the
  page to initialize plus an optional `Route` to correct the address bar to),
  and `Main.routeUrl` — which both `init` and `handleUrlChange` call — is the
  only thing that carries one out, so a cold-loaded URL runs its page's
  commands like any other. No shape answers `Cmd.none` any more:
  `/<dbName>/<title>` opens `<dbName>`, three-plus segments and
  `/<dbName>/404-not-found` reach the not-found screen (which now asks for the
  document list it tells the user to look at), and a guest at any signed-in-only
  URL gets the login form with the address bar corrected to `/login`. Landings
  correct by `Replace`, never `Push` — a pushed redirect leaves the bad URL for
  Back to land on — and a just-completed login now routes as the user it signed
  in for *every* path, not the two the old guest branch special-cased. ADR-0001
  gains seam 8 (routing, Elm, pure); 23 tests, including a round trip of every
  URL `Route.toString` builds back to the page it names. Details in
  `issues/14-cold-url-init.md`.
- Ticket 28 resolved — the local snapshot is the card set again, not the
  version log: `applyCardBasedSave` reads the document's rows through the plain
  `treeId` index and reduces them in JS (`newestVersionPerId`, then the deleted
  dropped — that order, per ADR-0005 §1). The `[treeId+deleted]` pre-filter
  could not stay: the newest row of a deleted card is exactly the row it hides,
  so the snapshot kept the card at its pre-deletion content and — `doc.js`
  handing Elm every snapshot row as `deleted: 0` — restoring it brought the
  card back. The snapshot's id keeps being the newest stamp in the log,
  deletion rows included, rather than the newest row it holds: otherwise a save
  that deletes is stamped with the last surviving edit and overwrites the
  history entry that still had the card. So deleting now leaves a restore point
  of its own. 4 tests at seam 4. Details in
  `issues/28-local-snapshot-newest-per-id.md`.
- Ticket 15 resolved — five findings and one carried over from 07, each its own
  commit. E5: `preventIfBlocked` now comes **last** in `changeMode`'s two
  guarded branches (the order `insert` used), so a blocked document no longer
  broadcasts `CollabEditing` for an editor it refused to open — a phantom that
  made the fullscreen view disable the card for whoever really held it. E6:
  `Incoming`'s tag→`Msg` mapping is a pure total `fromOutside` (a `Sub msg`
  cannot be run, which is how a tag with *no branch* went unnoticed), and
  `FullscreenChanged False` lands where the exit button lands. E11: a session
  start is recorded the first time a document's content reaches `Page.Doc` and
  never again, so the modal's "Session" row stops being a copy of "Total". E13:
  the OPML option **stays** and is made to work — a flat selection of cards is a
  tree of depth one, so leaves/column go through the same `stringFn` as the
  other selections (JSON and Markdown byte-identical by construction) — and
  `toMimeType` replaces the list-not-a-type `"application/xml, text/xml,
  text/x-opml"` with `text/x-opml`. E14: the tray's three placeholder strings
  now read `Alt` `(1-6)` `to Set Title Level`, in the tray's own voice rather
  than the help modal's sentence. Plus `gw-textarea` finally watches `disabled`.
  **E5 is the one fix with no test**: blocked and unblocked differ only in the
  `Cmd`, which elm-test cannot inspect — ADR-0001 seam 10 (added here) records
  that limit, and the adjacent hole it exposes (`changeMode`'s
  `FullscreenEditing` targets ignore `block` entirely, so shift+enter edits a
  history view) is written up for 24. 37 tests. Details in
  `issues/15-small-functional-fixes.md`.

- Ticket 30 resolved — the follow-up ticket 29 filed on itself, and a plain
  case-analysis bug: `mergeCards`' merge-down branch cased on the merge-up
  branch's pair with the roles swapped but kept its limbs in the old order, so
  a merge down into a *childless* card staged no re-parenting rows for the
  merged card's children while the same save deleted their parent — and
  `toTree` builds from the root down, so the whole subtree left the document
  (recoverable only from history). Its mirror limb was wrong the same way and
  harmless by luck: it mapped a list that is empty exactly when that limb is
  taken. Whether the children come over is not directional — they always do;
  only where they land is. So the eight limbs became one offset (past the
  survivor's last child going down, before its first going up, zero when
  either card is childless and there is nothing to clear) applied to every
  child of the merged card, which preserves their gaps per ticket 11. 8 tests
  at seam 1, 2 red first (the dropped rows, and the tree the user is left
  with); the other 6 pin both directions of the cases that already worked.
  `CONTEXT.md` gains **Merge**. Details in
  `issues/30-merge-down-orphans-children.md`.
- Ticket 16 resolved — E7/E8/E9/E15 were one story: the port layer could not
  tell a **card drag** from text dragged in from **outside** the app (the only
  setter of that flag was the dead elm-dnd `DragStart` port), and Elm computed
  the drop against a tree that still held the card being dropped. Where a card
  lands is now `Doc.TreeStructure.dropPlacement`, read on the *pruned* tree —
  the one `Mov` inserts into and the sibling list `placeCard` positions among —
  which fixes the one-slot-too-far downward drop and makes a drop into the
  card's own subtree no move at all, where before `insertSubtree` looked for a
  parent that had just been pruned away and lost every card under it. A card
  drag reports itself through the `gw-drag-start`/`gw-drag-end` pair
  `<gw-tree>` already emitted and nothing listened to: `dragend` fires at the
  source whatever the drag ended in, which is the reset `stopPropagation` on an
  internal drop had made unreachable, and `CardDropped` sends `DragDone` as
  well. Dropping a card on the card being edited now inserts nothing (empty
  payload *and* the default prevented for a card drag only) while text from
  outside still lands at the caret, told to nobody — deliberately, because the
  one message Elm has for "dropped, nothing to insert" would risk a blank card.
  Autoscroll over the header no longer dereferences a column that isn't there.
  The handlers live in `src/shared/drag.js` (seam 4 gains it; ADR-0001 gains
  **seam 9**, drop placement); 39 tests, 14 red first. The 14 CI-only failures
  were the fixture borrowing the `gw-tree` tag — a defined custom element wipes
  its children on connect, and bun 1.3.14 shares one `customElements` registry
  across test files while 1.3.11 does not; `tests/dom.ts` now records that
  rule. Details in `issues/16-drag-drop.md`.
- Ticket 31 resolved — the hole ticket 15 filed beside E5: `changeMode`'s three
  `FullscreenEditing` targets carried no `preventIfBlocked` at all, so
  `shift+enter` on a blocked document (history open, public document) opened a
  fullscreen editor and broadcast `CollabEditing` while it did. Four routes in,
  three branches: `shift+enter` from the normal view, the card editor's
  fullscreen button, and the fullscreen view moving focus to another card —
  inserting from a fullscreen editor was already covered by `insert`'s own
  guard. All three now end with the guard, so it replaces the whole triple and
  no mode change, save or collab broadcast survives the block. The fullscreen
  **exits** stay unguarded on purpose: guarding them would trap a reader in an
  editor and undo E6 (leaving browser fullscreen must close the fullscreen
  editor). ADR-0001 gains **seam 11** (the mode machine: which mode an event
  leaves the document in); 6 tests, 3 red first, one per guard, and the button's
  test simulates `gw-edit-fullscreen` on `Page.Doc.view` because
  `Page.Doc.Msg` exports no constructors. Guard *ordering* is still invisible to
  a test, as seam 10 records. Details in
  `issues/31-fullscreen-bypasses-block.md`.
- Ticket 09 resolved — D6 closed: `ws.onopen` now asks for the document
  metadata the server has not acknowledged, so a rename or delete made while
  the socket was down goes out on reconnect instead of waiting for an unrelated
  tree-table change or a reload. Both senders of the `trees` message live in
  `src/shared/metadata.js` (seam 4), which keeps the trees table as the
  liveQuery last emitted it and **re-derives** the message at send time. The
  ticket's two suggested designs were both rejected for the same reason: they
  can put stale state on the wire *after* newer state. Queueing holds one
  message per emission, so two offline renames push the first name and then the
  second, and a server taking the last at face value echoes the older name back
  over the newer Dexie row; an `await db.trees.toArray()` in `onopen` can be
  overtaken by an emission and then answer with the pre-rename state. Reading
  the last emission takes no turn of the event loop, and one code path for both
  senders makes every `trees` message a read of the same monotonic sequence, so
  none can be older than one already sent. The queue keeps the messages that
  are **events** (`pull`, `rt:join`). `stop()` (called by ticket 04's
  `stopSyncing`) makes an instance inert for good, so a reconnect cannot push
  the rows of the account that logged out. 10 tests at seam 4, 3 red first;
  `CONTEXT.md` gains **document metadata**. Details in
  `issues/09-offline-metadata-resend.md`.
- Ticket 17 resolved — E10 and E12 were one shape twice: a value crossing a
  boundary and a reader replacing it with a constant on the way back. E10: the
  per-document theme is read back off the localStore blob a document load
  attaches to its card rows — the ride `last-actives` already takes — through
  `Theme.fromLocalStore` (*the theme a card-data message names, or the one
  already in effect*, since only the first message of a load carries settings
  and every liveQuery echo after it must change nothing); `decoder` stops being
  exposed, because an exported decoder with no importers is how E10 hid.
  **Its write half is still unreachable**: the theme picker was removed in
  `a203a9c`, so `ThemeChanged`/`SaveThemeSetting` have no producer and the
  restored value can only come from an older build's store — restoring a picker
  or removing the ring is an owner call for 21/22. E12: `<gw-header>`'s title
  input is no longer rebuilt at all. Guarding attributes one at a time could
  not work (`menu`, `export-settings` and `history` rebuilt the field too), so
  the `#title` span is built once and kept while everything after it is
  replaced, and the field's value is written only while it lacks focus.
  `replaceChildren()` detaches even a node that goes straight back, taking
  focus, caret, selection, undo stack and IME with it — the old code
  hand-restored two of six — and dropping the re-`focus()` also ends the tick's
  phantom `gw-title-focus`, which Elm answered with `SelectAll`. 25 tests
  (15 at seam 10, 10 at seam 3), 12 red first. Details in
  `issues/17-theme-and-title.md`.
- Ticket 18 resolved — E16 closed: every swallowed error surfaces, none needed
  a silence exemption. The three `Doc.Data` payload readers answered an
  unreadable payload the same way they answer "nothing changed", so they now
  carry the decoder's reason out (`cardDataReceived` gains a third answer:
  `Err` / `Ok Nothing` / `Ok (Just …)`) and `Page.App` turns each into a
  persistent toast plus a console line. Toast text is **fixed per site** and the
  reason goes to the console, for two reasons that both bind: `Toast.addUnique`
  dedupes on content, and `Doc.UI.viewToast` renders a message through
  `Markdown.Parser` with `<parse error>` as the fallback — so no filename, URL
  or server body may be interpolated into one. `ws.onmessage`'s catch-all is now
  judged per message type (`src/shared/ws-errors.js`, an allowlist of the benign
  types so a new case is loud by default; `cards` — lost incoming sync data — is
  surfaced), `JSON.parse` moved inside the try it belonged in, and all three
  clipboard sites share `src/shared/clipboard.js`. New ADR-0001 **seam 12**.
  A push ack that does not parse no longer counts as a successful sync. 158
  elm-test + 143 bun test. Details in `issues/18-error-surfacing.md`.
- Ticket 24 resolved — S1, S2, S3, S4, S10, S12 and P4, all one shape: a
  decision that existed twice, or a question asked of the wrong thing. The save
  indicator is now **one** `<gw-save-indicator>` rendered by the header *and*
  `Doc/Fullscreen.elm` (parity would have left two), with `Doc.UI.encodeSaveState`
  the single Elm-side payload; the import's port tag is `SaveImportedTree` on both
  sides; `Session.isOwner` becomes `ownership` with a third answer, `Unknown`,
  which both callers **withhold** on rather than guess (a load-gated `True` was
  rejected: `RenameDocument` has no ownership check but the disabled title field,
  so guessing would open a real rename window); `copyNaming` drops the regex and
  compares names, taking the first free number; `Metadata.encode` writes every
  field its decoder reads and the `oneOf` fallback that hid the bug is one decoder
  with optional fields; `UpdatedAt`'s *parser* learns `"0"`, because that spelling
  is the wire format `stamps.js` shares. The `<img src="" onerror>` and the no-op
  `EmptyMessageShown` it fired are gone; the empty-state and password controls are
  real buttons (the latter moved out of their `<label>`), while a breadcrumb stays
  a `div` made keyboard-operable — its label is rendered markdown, which may
  contain a link. `mod+j`/`k`/`l` collapse into one `splitCard` whose guard sees
  the unmutated model, over a single `stageCardText`. New ADR-0001 **seam 13**;
  seams 10 and 11 widened (chrome views that need no `Nav.Key`; the cards an event
  leaves, which makes a guard's ordering over a model change test-visible). 199
  elm-test + 201 bun test. Details in `issues/24-elm-consistency.md`.
- Ticket 23 resolved — S5–S8 and S13: the port layer waits for events instead of
  clocks. Every catalogued `setTimeout` is now the signal it was guessing at —
  `SocketConnected` when the socket is open *and* Elm has its cards,
  `pullHistoryMeta` with the ordered `pull` it trailed by 500 ms, the slider and
  the first-load activation through a new `whenReady` (MutationObserver, then one
  animation frame, never synchronously — both callers are inside Elm's update
  cycle), the rename idempotent **by value** in one transaction rather than
  guarded by a flag that dropped whichever message lost the race, and the
  permanent 800 ms header-geometry poll replaced by a `ResizeObserver` plus
  `<gw-header>`'s new `gw-header-rendered`. The fillet scroll listener is one
  shared function object, so re-registering it per navigation keystroke is a
  no-op. The dispatch table separates "no such tag" from "that handler failed",
  and catches the `async` rejections that were every Dexie write in it, with
  `src/shared/port-errors.js` deciding what the user hears (allowlist of the
  benign, `alert` not toast — toasts are the sync channel). Boot survives its own
  storage: a session blob that is missing, unparseable or not an object is a
  guest session, a `localStore` read before any write is the fallback, a
  root-cardless document opens, and an empty card log skips its snapshot instead
  of throwing inside the save's `try`. New seam-4 modules `cards.js`
  (newest-per-id then drop-deleted, which the backup was half-applying) and
  `documents.js`; `session.js` gains the blob's writer. 205 bun test + 199
  elm-test. Details in `issues/23-js-robustness.md`.
- Ticket 32 resolved — the theme picker is back in `<gw-header>`'s settings
  menu, so ticket 17's round trip has the producer it lacked. The decision was
  *who names a theme*: `Page.Doc.Theme.name`/`fromName` are now the module's
  string vocabulary and `toValue`/`decoder` are written in terms of them, so
  the `theme` attribute, the `gw-theme` detail and the string in localStorage
  are one spelling by construction — which is what makes "chosen in the menu"
  and "restored on the next load" the same theme, and it leaves `Page.App` with
  `themeMsg = Theme.fromName >> ThemeChanged` and no table of its own. The
  element never marks its own choice: a click only reports, and the mark
  follows the attribute Elm hands back after `applyTheme` and
  `SaveThemeSetting` (pinned). Entries are real `<button>`s (S12) — "Word
  count..." included, it was a clickable div — whose keydown stops for Enter
  and Space only, because Mousetrap's `document` bindings ignore just form
  fields and an escaping Enter would open the active card's editor;
  `render()` also refocuses the rebuilt control by its id, so choosing a theme
  with the keyboard no longer drops the user on `<body>` (the history slider
  gains the same). **Still mouse-only to open**: the three header icons are
  `div`s, a pre-existing S12 gap ticket 24 did not cover, and converting them
  needs the same keydown guard — worth its own ticket. Ticket 22's "don't
  delete the theme write ring" warning is discharged. 16 tests (9 at seam 3,
  7 at seam 10), 7 red first plus a mutation red for the Elm pair. Details in
  `issues/32-restore-theme-picker.md`.
- Ticket 27 resolved — the leak ticket 04 opened: one global Dexie `"db"` meant
  the next account to log in read the departing account's documents as its own.
  The name is derived per account instead (`src/shared/local-db.js`:
  `db-<cyrb64 of the lower-cased address>`, hashed because the name is readable
  through devtools, `indexedDB.databases()` and the *filename*
  `database-download.js` hands the user; `crypto.subtle` is unusable — undefined
  outside a secure context, which a plain-HTTP self-host is, and async before
  the first Dexie call). Nothing is cleared on a switch, so unsynced offline
  rows survive A→B→A. The migration is **adoption, not a copy or a re-pull**:
  the first account to log in takes `"db"` and records its hash under
  `gingko-local-db-owner`; everyone else opens their own. Its whole crash-safety
  argument is that the only write is one `setItem` and *no row is touched on the
  strength of it* — it cannot be half-done, cannot run twice, and a claim that
  will not land simply means no adoption (copying could finish, fail to delete,
  and be re-copied on a later boot, putting older rows over newer via `bulkPut`;
  re-pulling would discard the unsynced rows 04 and 27 both exist to keep).
  `writeDbClaim` reads back rather than trusting `setItem`, because a storage
  that drops the value would let the *next* account adopt too. The two
  treeId-keyed stores stay per document, and the usual premise for that is
  **false** — verified: treeIds are client-minted (`RandomId.generate`, 7 base62
  chars), not server-issued — so the case rests on consequence instead:
  `backup-snapshot:<treeId>` has no read path anywhere in the client, and
  `gingko-local-store/<treeId>/settings` is `last-actives` + `theme`, so a clash
  costs a wrong theme and namespacing would cost two migrations. Audit of the
  implementation added the two pins it depended on silently: known-good hash
  literals (the pre-existing stability test compares the hash to itself — a
  changed multiplier left all 20 tests green, while a moved name finds *no*
  database and strands the unpushed rows) and "logout keeps the claim" (an
  unclaimed `"db"` is adoptable, so tidying `gingko-*` away restores the leak).
  22 tests at seam 4, ADR-0001 gains local-db.js there. Details in
  `issues/27-per-account-local-data.md`.
- Ticket 21 resolved — §6's Elm side, all of it: net **−2,204 lines** over
  eleven commits, five modules deleted, four `elm.json` pins dropped and
  `elm/parser` demoted to indirect. The method mattered more than the list.
  Re-verifying every entry against the *current* tree rather than the review's
  snapshot changed five answers — `GlobalData.public`,
  `Page.Doc.publicTreeLoaded` and `Doc.Metadata.encode` had grown test
  callers, `userLoggedOutMsg` had grown a sender (ticket 04), and the dead
  `TranslationId` count was 144 of 200, not 138 of 203, because tickets 24 and
  32 moved the save indicator and theme labels to TS in between. Two classes
  the inventory's shape could not see: **private** zero-caller declarations,
  which have no exposing-list entry to look wrong — and two of the four found
  (`Export.toExtension`, `RandomId.fromObjectId`) had been *half*-removed
  earlier in this same ticket, taken out of the exposing list with the body
  left behind, so "removed from the exposing list" is not "removed"; and the
  question of whether a dead branch is a hole — `SavedRemotely` was only safe
  to delete because `lastRemoteSave` has a better producer
  (`Data.lastSyncedTime`, read off the synced rows rather than from a report
  about them), which was checked first. Two mechanical invariants now hold and
  are worth re-running after any port change: every `Outgoing.Msg` constructor
  has an Elm producer, and every incoming tag has a reachable JS sender. Left
  deliberately: 14 more unimported direct pins (pre-fork, and dropping them is
  a solver re-solve, not a line edit) and `Toast.elm`'s vendored surface.
  Ticket 22 still owns the `doc.js` halves — none can fire, which matters
  because an unknown incoming tag toasts rather than being ignored (18).
  Details in `issues/21-deadcode-elm.md`.

## Owner decisions (answered 2026-08-27)

All four questionnaire answers in
(`docs/to-questionnaire-selfhost-scope.md`): no password-reset emails —
remove the dead link (19); test-only CI — 26 resolved wontfix; full
dead-code purge (21, 22); perf refactor in scope, scheduled last (25). No
ticket carries `needs-info` any more.

## Notes

- Conventions: `docs/agents/issue-tracker.md`. Claim before work
  (`Status: claimed`, commit). A ticket is unblocked when every ticket in its
  `Blocked by:` line is `resolved`.
- Every ticket follows `/implement`: TDD at the ADR-0001 seams, `/code-review`
  before commit, work lands on `selfhost`.
- **Ticket-implementing agents run on Opus 5** (`model: "opus"` when spawning
  them). Orchestration/chat may run on a faster model, but implementation,
  TDD and code-review work does not.

## Tickets

| NN | Ticket | Covers | Blocked by |
|----|--------|--------|------------|
| 01 | test-infrastructure | B1 B2 B3 B6 | — |
| 02 | sanitize-markdown | C1 | 01 |
| 03 | remove-trial-lockout | C2 | 01 |
| 04 | logout | C3 | 01 |
| 05 | newest-version-dedupe | D1 D2 D10 S9 | 01 |
| 06 | conflict-resolution-discard | D3 | 01 |
| 07 | editor-reconnect | D4 | 01 |
| 08 | import-race | D5 | 01 |
| 09 | offline-metadata-resend | D6 | 01 |
| 10 | hlc-numeric-comparison | D7 | 01 |
| 11 | position-rebalancing | D8 | 01 |
| 12 | history-restore-deltas | D9 | 01 |
| 13 | session-prefs | E1 E2 E3 | 01 |
| 14 | cold-url-init | E4 | 01 |
| 15 | small-functional-fixes | E5 E6 E11 E13 E14 | 01 |
| 16 | drag-drop | E7 E8 E9 E15 | 01 |
| 17 | theme-and-title | E10 E12 | 01 |
| 18 | error-surfacing | E16 | 01 |
| 19 | auth-pages | A1 A2 A3 A4 | 01 |
| 20 | build-and-docs-cleanup | B4 B5 B7–B13 | 01 |
| 21 | deadcode-elm | §6 (Elm) | 03 |
| 22 | deadcode-js-ts | §6 (JS/TS, translations) | 03 |
| 23 | js-robustness | S5 S6 S7 S8 S13 | 01 |
| 24 | elm-consistency | S1 S2 S3 S4 S10 S12 | 01 |
| 25 | perf-data-layer | P1–P5 | 05 06 12 |
| 26 | deploy-workflow | (new) | resolved: wontfix |
| 27 | per-account-local-data | new (from 04) | 04 |
| 28 | local-snapshot-newest-per-id | new (from 12) | 12 |
| 29 | stale-row-save-reverts | new (from 11) | 11 |
| 30 | merge-down-orphans-children | new (from 29) | 29 |
| 31 | fullscreen-bypasses-block | new (from 15) | 15 |
| 32 | restore-theme-picker | owner decision | 17, 24 |
| 33 | header-icons-keyboard | new (from 32) | 32 |

## Not yet specified

- Nothing — all fog cleared by the 2026-08-27 questionnaire answers.
