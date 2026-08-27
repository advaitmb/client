# 22: Dead code purge — JS/TS and port contract

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 03 · **Owner decided (2026-08-27):** full purge.

**Covers:** CODE_REVIEW.md §6 (JS/TS side): JS handlers with no Elm sender
(`InitBeamer`, `SocketSend`, `SaveCardBasedMigration`, `UpdateCommits`), dead
JS→Elm senders (`pushSuccessHandler` and the dead `SavedRemotely` Elm branch,
`userLoggedOutMsg` — mind ticket 04, which makes logout real), dead
custom-element contract ends (`gw-drag-start`/`gw-drag-end`, sidebar
`context-target`), dead JS (`PULL_LOCK`, `savedObjectIds`, `userDbName`,
`treeToHtml`, PouchDB-era `container-web.js` exports, elm-dnd `DragStart`
path both sides, `window.elmMessages`), and stale `src/ui/README.md` (S11).

**What to build:** The port dispatch table and custom-element contracts
contain only live ends; `src/ui/README.md` describes the actual state of the
migration.

**Added scope (from ticket 20's resolution):** the repo-root `build/`
directory (Electron packaging resources, zero references after B11);
producerless CSS in `src/static/style.css` — `#migrate-modal` /
`#migrate-bugs-modal` (no producers despite the old comment), `#fullscreen-button`
(live element is plural), `#help-dropdown`, `#language-menu*` — plus
`src/static/styles/github.css`; `package.json`'s `repository`/`bugs`/
`homepage` still pointing at `gingko/client`; `docs/images/
how-to-clone-address.png` (last referrer removed); the stale "send … to
Sentry" comment in doc.js. Verify zero references before each deletion, as
ticket 20 did.

**Added scope (from ticket 17's resolution):** `src/ui/README.md` documents
a `tsc` typecheck gate that does not exist (no tsconfig at root, nothing in
ci.yml) — when rewriting the README, either add a real `tsc --strict` check
to CI (it would have caught a field shadowing `HTMLElement.prototype.title`
that tests could not) or stop claiming it. Also: the theme write ring
(`ThemeChanged`, `SaveThemeSetting`, `Theme.toValue`) currently has no
producer — do NOT remove it without checking the owner's pending decision on
restoring the theme picker (see ticket 17's Comments).

**Added scope (from ticket 21's resolution):** the four doc.js handler
halves whose Elm senders ticket 21 just removed can no longer fire — and
matter more than usual because ticket 18's dispatch policy TOASTS an unknown
incoming tag rather than ignoring it. See ticket 21's Comments for the list.

## Acceptance criteria

- [x] All §6 JS/TS items removed or justified in Comments; coordinate with
      04 and 16 (don't delete what they just wired up).
- [x] `src/ui/README.md` rewritten to match reality.
- [x] Bundle builds; full test suite green.

## Answer

**259 lines added, 674 removed — net −415** across 30 files, in six commits on
`selfhost` (claim `a14629a`): `b393fb9`, `869d589`, `218195b`, `32a191e`,
`0c3648e`, `cc5e141`.

Every item was re-verified against the current tree (`src/` *and* `tests/`)
before deletion rather than trusted from §6's snapshot, and that mattered in
both directions: three items §6 lists had gained a caller or a producer in the
thirty tickets since, and **three more handlers had *become* dead** that §6
does not list, because ticket 21 removed their Elm tags after the review was
written.

### The port contract is now symmetric, and that is checkable

The headline result, verified mechanically rather than by reading:

| | Elm side | JS side |
|---|---|---|
| outgoing | 28 `dataToSend` tags | 28 handlers (21 `casesWeb` + 7 `casesShared`) |
| incoming | 26 decoded tags | 26 `toElm` sends |

The two outgoing sets are **identical as sets**, not merely equal in size —
extracted and `diff`ed. Before this ticket the JS side had 37 handlers for 28
tags.

This is load-bearing in both directions, which is why the ticket flagged it.
An unknown *incoming* tag reaches `onError` and toasts (ticket 18). An
*outgoing* tag with no handler is reported too — `doc.js` says "Unexpected
message from Elm" and `port-errors.js` decides whether the user hears it — so
a handler kept for a tag that cannot arrive is not inert, it is a false claim
about the table that the next reader must cross-check to disbelieve.

### What went

*Nine dead dispatch handlers* (`b393fb9`) — the four ticket 21 named
(`SaveCardBasedMigration`, `ScrollFullscreenCards`, `DragStart` including the
`DragStarted` send inside it, and `pushSuccessHandler`'s `SavedRemotely`), the
three §6 named as no-ops (`UpdateCommits`, `InitBeamer`, `SocketSend`), **plus
`SetField`, `SetFullscreen` and `RequestFullscreen`** — declared, not smuggled:
§6 lists those three under *dead outgoing tags*, and ticket 21 removed the Elm
constructors, so their JS halves were orphaned between the review and this
ticket. `port-errors.js`'s benign allowlist loses the eight of the nine it
named, and now says at the list why an entry for an unconstructable tag is a
lie rather than a no-op.

*Write-only globals* (`b393fb9`) — `PULL_LOCK`, `savedObjectIds`, `userDbName`,
and **`remoteDB`/`db`**, the last two being the same PouchDB/CouchDB residue in
the same block (`remoteDB = null; db = null` was the whole of their lifetime).
`treeToHtml` went with them, provably unreachable since ticket 23 moved
`treeHelper` to `cards.js`.

*doc-helpers.js* (`b393fb9`) — `toHex` (orphaned by `userDbName`, its only
caller — ticket 27's note), `isEditTextarea`, `errorAlert`, and the four
exports left with no importer. Its export list and `doc.js`'s `helpers.*` uses
are now the same eight names.

*container-web.js* (`869d589`) — `userStore`, `getInitialDocState`,
`showMessageBox`, seven `justLog` IPC/export no-ops, and the unused lodash
import. The file is 101 → 40 lines and is now only the per-document settings
store. `localStore.get` went too (ticket 17's third adjacent note): it *was*
the S8 bug, and it has no caller, because `load` hands the whole blob to Elm
as `loadedCards.localStore` and Elm decodes what it wants.

*The sidebar `context-target` attribute* (`869d589`) — documented, styled,
observed and never set. Elm's `SidebarContextClicked` renders the menu itself
over an overlay and tells the rail nothing, so the row-mark never appeared.
Removed rather than wired, with the one-line alternative recorded in the
element's own contract block.

*Ticket 20's added scope* (`218195b`) — `build/` (11 files of Electron
packaging), `src/static/styles/github.css` (and so `web/styles/`), the
producerless rules `#migrate-modal` + its five children, `#migrate-bugs-modal`,
`#help-dropdown`, `#language-menu{,.selected}` and `#fullscreen-button`
(singular, and `display: none` — hiding an element that does not exist; the
live `#fullscreen-buttons` is untouched), `docs/images/
how-to-clone-address.png`, `package.json`'s three upstream URLs, and the
"send encrypted unsynced local cards to Sentry" comment, which outlived its
call by years.

### The tsc gate: added, and confirmed to be real

Ticket 17's added scope offered "add it or stop claiming it". Added
(`32a191e`): `typescript` pinned `~5.9.3`, `bun run typecheck`, and a CI step —
placed *before* the Elm cache, which it needs nothing from.

`moduleResolution` moves `node` → `bundler` (`module` → `ESNext` with it), and
this is a floor rather than a preference. Measured: **TypeScript 7.0.2 answers
the previously committed setting with `error TS5108: Option
'moduleResolution=node10' has been removed` and then checks nothing at all** —
which is exactly what ticket 32 hit while 5.9.3 merely accepted it. `bundler`
is clean on both, and it is also what describes reality, since esbuild builds
this directory: `node10` reads neither a package's `exports` map nor its ESM
build, which is why `import DOMPurify from "dompurify"` was the one error
standing between the repo and a green gate.

**The gate was verified to check something**, per the README's own instruction,
because an unsupported `moduleResolution` is not an error — it silently
degrades cross-module imports to `any`. Passing `42` where `modal.ts`'s
`mountModal` wants a `string` was caught across the module boundary (`TS2345`)
under both resolutions.

### The README rewrite

Four of its claims were false (S11). Its "what has moved" table named one
element of nine; its "no framework" rule said these surfaces "render once when
opened and are discarded when closed", true of three and wrong about the six
Elm keeps handing new attributes, `gw-tree` included; its typecheck command
pointed into a sibling checkout; and it credited a build gate and a
`verify/smoke.mjs` that do not exist here.

**The moved-element list is deleted rather than corrected.** It drifted because
it was a copy — `src/ui/index.ts`'s header holds the same list beside the
imports that register the elements. The README keeps what index.ts cannot: the
boundary, what is still Elm's to render, the two kinds of surface (built once
vs. updated in place), and eight rules, each one behaviour an earlier ticket
paid for — the `isConnected` guard, `disconnectedCallback` clearing state and
not only listeners (S13's stale drag), uncontrolled text inputs, the keydown
guard against Mousetrap (ticket 32), the `static` loading convention, and the
shared-jsdom fixture rule (ticket 16's CI-only failure).

### Kept, against the review

- **`window.elmMessages`** — §6 calls it a dead debug ring buffer, and it has
  no reader in the code. Kept, and now says why: `doc.js` boots the app at
  module load and so is importable by nothing (ADR-0001 seam 4 exists because
  of it), which makes this the only runtime record of what crossed the port.
  Ticket 08 deleted a handler's `console.log` on exactly that ground, so
  removing the buffer would retroactively void that deletion.
- **`gw-drag-start` / `gw-drag-end`** — §6 calls them emitted and never
  listened to. Ticket 16 gave them listeners in `drag.js`; they are how a card
  drag is told from an external one. Untouched.
- **`userLoggedOutMsg`** — §6 calls it never sent. Ticket 04's `onLoggedOut`
  sends it.
- **The theme ring** (`ThemeChanged`, `SaveThemeSetting`, `Theme.toValue`, and
  `doc.js`'s handler) — ticket 32 restored the picker, so it has a producer.
  Checked before touching anything near it, per this ticket's added scope.
- **`localStore.load`/`isReady`/`set`/`db`, `scrollFullscreen`,
  `updateFillets`** — the functions stay (live internal or external callers);
  only the surplus *exports* of the last two went.
- **`docs/CODE_REVIEW.md`** — left as the catalog as found, matching tickets
  02–14, 20 and 21.

### Translations: nothing left to do

`map.md` gives this ticket "§6 (JS/TS, **translations**)". Ticket 21 took 144
of 200 `TranslationId` constructors; checked mechanically here that the
remainder are all live — each of the 56 survivors (55 plus `NoTr`) has at least
one use outside `Translation.elm`. Zero orphans, so that half of the row was
already discharged.

### Verification

| Gate | Result |
|---|---|
| `bun test` | **236/236** across 23 files (unchanged — no test was lost) |
| `bun run test:elm` | **206/206** (this ticket touches no Elm) |
| `bun run typecheck` | exit 0 (new) |
| `bun run newbuild` | exit 0 from an empty `web/`, 17 outputs |
| `bun run config-check` | exit 0 |
| lockfiles | both regenerated per ADR-0004 |
| CI | green on all seven commits (six code/docs + this tracker one) |

`docs/ARCHITECTURE.md` updated in four places: §2's `container-web.js` row,
§4.3's "render-once surfaces", §7's port tables (now stating both directions
are exhaustive, and why that is load-bearing) and §8's CI step list.

## Comments

- **Three handlers §6 does not list were dead, and finding them needed the
  cross-check rather than the inventory.** `SetField`, `SetFullscreen` and
  `RequestFullscreen` appear in §6 only as *outgoing tags Elm never sends*; the
  review did not say their JS handlers were therefore orphans, because at the
  time the (dead) Elm constructors still existed. Ticket 21 removed those, and
  the handlers became unreachable in the gap between the two tickets. Extracting
  both tag sets and diffing them found all three in one step, which reading down
  the inventory would not have. **Recommendation for whoever wants this to stay
  true:** the check is currently a shell one-liner run by hand, because
  `casesWeb` lives inside `fromElm` in a file no test can import. Making the
  dispatch table importable — the way seam 4 extracted `save.js` and `drag.js` —
  would let the symmetry be a test instead. Worth its own ticket; nothing
  depends on it happening, and it is a refactor, not a purge.

- **`screenfull` survives the removal of both fullscreen request handlers**, and
  the distinction is worth recording: the app can no longer *ask* for browser
  fullscreen (Elm has no tag for it), but `screenfull.on('change')` is a live
  `FullscreenChanged` sender, so it still learns about a fullscreen the user
  entered with F11 or the browser's own chrome. Deleting the require would have
  broken that.

- **`localStore.get`'s removal cost no coverage, which was checked rather than
  assumed.** Three tests in `boot.test.ts` used it as their probe, and it looked
  at first like deleting a tested function. But each of those tests already
  asserted `load()` alongside, and `load` is the accessor the app actually
  depends on and the one whose guard S8 was about — so the assertions were
  rewritten onto `load` and the tests still pin the same three behaviours (empty
  before any write, survives a corrupted store, round-trips). Test count is
  unchanged at 236; three `expect` calls went with the function.

- **The self-review pass was where four comments turned out to be wrong**
  (`cc5e141`), and in a repo this comment-heavy that is the failure mode worth
  reporting: `dom.ts` carried the *identical* "rendered once ... thrown away"
  claim the README rewrite had just corrected — half-fixing a claim that lives
  in two places is worse than not fixing it; `modal.ts` still said it mirrors
  `SharedUI.modalWrapper`, which ticket 21 deleted; `ci.yml`'s new step credited
  the `HTMLElement.prototype.title` shadowing to ticket 24, when ticket 24 ran a
  *clean* ad-hoc `tsc` and ticket 17 is where the bug was found; and the
  tsconfig comment guessed that `node10` was "on its way out", where checking
  against 7.0.2 gave the much stronger fact above. The lesson is narrow and
  repeatable: a purge deletes code, but it also *writes* prose about what was
  deleted, and that prose needs the same verification the deletions get.

- **`context-target` could be wired instead of removed, and the choice is
  recorded in the code, not just here.** Elm has the document id at the moment
  the menu opens; one `attribute "context-target"` in
  `Page.App.viewSidebarElement` plus the two CSS rules back would make the
  row-mark real. Removed because giving a styled-but-unset attribute a producer
  is a UI change, and this ticket is a purge — the same reasoning ticket 17 gave
  for not restoring the theme picker under a two-finding ticket. The note sits
  in `sidebar.ts`'s contract block where the next person to want the highlight
  will read it.

- **`bugs.url` now points at `advaitmb/client/issues`, which is currently a
  404**: GitHub Issues are disabled on this fork (see
  `docs/agents/issue-tracker.md`, and the canonical tracker is `.scratch/`).
  Pointed there anyway, deliberately — it is the conventional field pointing at
  the conventional place, it is what the ticket asked for, and it becomes
  correct the moment issues are enabled, which that doc explicitly contemplates.
  Flagging it so the choice is visible rather than looking like an oversight.

- **The `Container` alias and `container-web.js`'s name are the last trace of
  the Electron/web split**, and both are left alone: with one file behind it the
  alias is pointless indirection, and the module is now only `localStore`, so
  the honest name is something like `local-settings.js`. But the alias is *used*
  rather than dead, and a rename touches `esbuild.mjs`, `doc.js`,
  `boot.test.ts`, ADR-0001 and ARCHITECTURE — churn of a different kind from
  this ticket's. Recorded in the file's own header instead.

- **The typecheck covers `src/ui` only.** That is what the README claimed and
  where the types are; extending it to `tests/*.test.ts` needs the `src/shared`
  JS modules they import to be typed (or `allowJs` plus a checked-JS decision),
  which is a bigger change with its own design question.

- **CI runs, per commit rather than only at the tip**, since a purge is exactly
  the change that compiles at the end having been broken in the middle:
  [33105071749](https://github.com/advaitmb/client/actions/runs/33105071749)
  (`b393fb9`),
  [33105320304](https://github.com/advaitmb/client/actions/runs/33105320304)
  (`869d589`),
  [33105484044](https://github.com/advaitmb/client/actions/runs/33105484044)
  (`218195b`),
  [33105719637](https://github.com/advaitmb/client/actions/runs/33105719637)
  (`32a191e` — the first run carrying the new typecheck step),
  [33106039962](https://github.com/advaitmb/client/actions/runs/33106039962)
  (`0c3648e`) and
  [33106602970](https://github.com/advaitmb/client/actions/runs/33106602970)
  (`cc5e141`) and
  [33106972755](https://github.com/advaitmb/client/actions/runs/33106972755)
  (`37d746e`, this tracker entry). Each was pushed as its own green group.

- **Environment note, correcting ticket 21's.** `bun run test:elm` needed no
  `danfishgold/base64-bytes` 1.1.0 fix on this container: `npm install` plus
  `scripts/install_elm_pkgs.sh` was enough, and elm-test ran 206/206 first try.
  Either the script or the cache now covers it; the next agent should try before
  reaching for the manual clone.
