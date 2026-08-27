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

## Not yet specified

- Nothing — all fog cleared by the 2026-08-27 questionnaire answers.
