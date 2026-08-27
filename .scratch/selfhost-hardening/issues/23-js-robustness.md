# 23: JS robustness — timing hacks, leaks, dispatch, boot

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md S5, S6, S7, S8, S13.

**What to build:** The port layer stops relying on luck: the catalogued
`setTimeout`-instead-of-signal hacks are replaced with real readiness signals
(or individually justified in Comments), including the permanent 800 ms
header-geometry poll (S5); the per-navigation scroll-listener leak stops (S6);
port dispatch reports the real error and catches async handler rejections
(S7); boot survives corrupted localStorage and a missing root card instead of
white-screening (S8); the duplicated `CARD_DATA` symbol and other hidden
couplings in S13 are consolidated where cheap.

**Added scope (from ticket 07's resolution):** `doc-helpers.js`'s
`editBlurHandler` is one module-level handler shared by all `gw-textarea`
instances — per-instance state is the S13-style fix.

**Added scope (from ticket 10's resolution):** `doc.js`'s snapshot-id
`Math.max` uses a seedless `reduce`, which throws on an empty card set —
harden alongside S8's boot guards.

**Added scope (from ticket 28's resolution):** `saveBackupToImmortalDB` in
doc.js half-applies ADR-0005 §1 — it dedupes newest-per-id but keeps cards
whose newest row is a deletion, and its `treeHelper` filters only on
`parentId`. Low stakes (write-only backup) but fix while hardening the file:
drop deleted cards after the dedupe.

**Added scope (from ticket 18's resolution):** the swallows ticket 18 left
as yours: `fromElm`'s dispatch catch (S7's site), the `window` error handler,
and the `InitDocument`/`LoadDocument` catches. Also note ticket 18's new
modules (`ws-errors.js`, `clipboard.js`) — extend, don't duplicate.

## Acceptance criteria

- [x] No anonymous-listener accumulation on `ScrollCards` (verifiable by
      inspection or test).
- [x] Async handler rejections in the dispatch table are caught and reported
      with the failing tag's name.
- [x] Corrupted session JSON in localStorage boots to a working (guest)
      state — test at a practical seam.
- [x] Each remaining S5 timing hack has a one-line justification in Comments.
- [x] CI green.

## Answer

**S5 — every catalogued hack now waits for the thing it was guessing at.**

| Was | Is |
|---|---|
| `setTimeout(…, 1000)` before `SocketConnected` | sent when the socket is open **and** Elm has been handed a document's cards — the two states the message needs, both events `doc.js` already sees. Once per open socket; `onclose` re-arms it |
| 500 ms before `pullHistoryMeta` | sent with the `pull` it followed. A websocket delivers in write order and `wsQueue` drains in fill order, so the delay was waiting for nothing — it only meant a document opened and closed inside half a second never asked for its history |
| `0`/`200 ms` render guesses in `HistorySlider` | `whenReady`, a new DOM-readiness helper in `doc-helpers.js`: a MutationObserver until the predicate holds, then one animation frame |
| 20 ms before `InitialActivation` | the same helper, waiting for the root card's own element — which is what Elm's answer (a scroll to it) needs |
| the `renaming` double-blur flag | `renameDocument` in the new `src/shared/documents.js`: idempotent **by value** inside one transaction, so the commit and the blur it causes write once — and a genuinely different second name still lands, which the flag dropped |
| permanent 800 ms `syncUI` poll | a `ResizeObserver` on `#document-header` (its box changing is every way the anchor icon can move: window, sidebar, an open menu) plus a new `gw-header-rendered` event from `<gw-header>` for the one thing an observer cannot report — a *new* header element, or the icon appearing in it. Plus the two moments doc.js already knows: a document loading, and `resize` |

`whenReady` deliberately never runs its callback synchronously: both callers are
reached from inside Elm's update cycle and one of them dispatches an event Elm
listens to, which is what the original `setTimeout(…, 0)` was avoiding.

**S6 — the fillet scroll listener is one module-level function object**, so
`ScrollCards` (one per navigation keystroke) re-registering it on every column
is a no-op the DOM discards. It also takes no arguments now: the old closure
held the column list as it was when the listener was created, which is stale as
soon as the tree changes shape. `params.ticking` went with it.

**S7 — the dispatch table tells the three cases apart.** A tag with no handler
is "Unexpected message from Elm" (which is what that sentence means); a handler
that throws is reported by tag with its real error; and a handler that *rejects*
is reported at all, which is new — most of them are `async`, so every Dexie
write in the table had its failures land nowhere. What the user hears is
`src/shared/port-errors.js`'s decision, in the same shape and direction as
ticket 18's `ws-errors.js`: an allowlist of the benign tags (the DOM ones, the
dialogs, presence, the copy paths that report themselves), everything else
`alert()`ed — a dialog, not a toast, because Elm's toasts are the *sync* error
channel (ticket 18's finding) and a failed local write is not a sync failure.
The `InitDocument`/`LoadDocument` catches are gone: both now `await`
`loadCardBasedDocument`, so the dispatch reports what they were swallowing. The
`window` error handler no longer reads `.message` off an event that may not have
one (`isExtensionInterference` is total), and an `unhandledrejection` listener
puts anything that still escapes in the console.

**S8 — boot survives its own storage.** `readSessionData` (session.js) returns
null for absent, unparseable, *or* not-an-object — that last one matters because
`getFlags` decorates whatever it gets and hands it to Elm, so `42` was a blank
page by a longer route — and clears the unusable value. `writeSessionData` moved
there too, so the blob's key, its read and its write are one module, and a
denied `setItem` no longer fails the message that asked. `localStore`'s three
accessors share one guarded read, so a `get` before any write returns the
fallback instead of null-dereferencing. `InitialActivation` goes through
`rootCardId`, which reads the log per ADR-0005 §1 and answers `null` rather than
throwing when every root row is a deletion. And `save.js` skips the snapshot
when the document's log is empty instead of `undefined.split(':')` — that threw
*inside* the save's own `try`, so a save that had already written its cards
reported "Error saving data!" and skipped the timestamp that sends them
(ticket 10's finding).

**S13 — the couplings named in the finding.** `CARD_DATA` is defined once, in
`doc-helpers.js`, and imported by `doc.js` (two independent
`Symbol.for("cardbased")` calls agreed by luck of the string). `help-modal.ts`
uses `mountModal`, which is also the only place the close icon's path data lives
now. `tree.ts`'s `disconnectedCallback` clears `data`, `editingId`, `dragged`
and the `dragging` attribute as well as the card maps — `dragend` never fires
for a removed element, so a tree taken off the page mid-drag came back believing
a card was in flight and turned the next drop into a move. The sidebar logo is
`/gingko-leaf-logo.svg`.

**Ticket 07's leftover** — `gw-textarea`'s document click handler is per
instance. As one shared function object, every instance that wanted it was
asking for the *same* registration (the DOM keeps one copy of a
`(type, listener, capture)` triple), so the first instance to leave took
click-outside away from any still editing.

**Ticket 28's leftover** — the ImmortalDB backup goes through
`visibleCards`: newest row per id, *then* drop the deleted. The other order
resurrects a deleted card from one of its own older rows, and because
`treeHelper` only descends from cards that are in the snapshot, a deleted card's
subtree now goes with it.

**New modules** (all ADR-0001 seam 4, except the last at seam 12; the ADR
records them): `src/shared/cards.js` (reading the card log — `visibleCards`,
`rootCardId`, `backupSnapshotText`; `save.js` reads through it too),
`src/shared/documents.js` (the rename), `src/shared/port-errors.js` (the
failure policy), plus `readSessionData`/`writeSessionData` in `session.js` and
`whenReady` in `doc-helpers.js`.

**Tests.** 205 bun test (was 143) and 199 elm-test (unchanged — nothing here is
Elm). Red first for everything with a seam: `cards.test.ts` (11),
`boot.test.ts` (10), `port-errors.test.ts` (9), `documents.test.ts` (5),
`dom-timing.test.ts` (7), plus one each in `save.test.ts` (the empty-log
snapshot, red with the real `TypeError`), `tree.test.ts` (the stale drag),
`textarea.test.ts` (the shared click handler), `sidebar.test.ts` (the logo) and
`header.test.ts` (the render event), and four in `help-modal.test.ts` pinning
the chrome before it moved to `mountModal`. Two were checked for
discrimination by reverting the fix under the passing test: the
same-function-object assertion (fails with an anonymous wrapper) and the
rename's by-value guard (2 of 5 fail without it).

**Verified by inspection**, being out of reach at every seam: the
`ResizeObserver`/`gw-header-rendered` wiring (jsdom implements no
ResizeObserver, and the geometry it reacts to is CSS), and `SocketConnected`'s
two-state gate (a live socket plus `doc.js` module state). Both were exercised
end to end another way: the built `web/doc.js` was evaluated in a jsdom page
with a stubbed `Elm`, and with a corrupted session blob in localStorage it
reaches `Elm.Main.init` with working guest flags, clears the bad value, and
mounts the sync button — the same path that used to throw before Elm existed.

## Comments

- **Timing hacks that remain, and why.** None of S5's list survives. What is
  still on a timer is deliberate, and none of it is waiting for a signal:
  - `setInterval(… 'ping', 30000)` — the websocket keepalive, which is what the
    server's `pingTimeout` expects.
  - `setTimeout(…, 0)` around `userSettingsChange` / `userLoggedInMsg` — a
    re-entrancy guard, not a wait: both are reached from inside Elm's own
    update cycle. `whenReady`'s animation frame is the same guard.
  - `setTimeout(removeFlashClass, 200)`, the sync status line's 8 s dwell, the
    image toast's 2.5/7 s — animation and message durations.
  - `_.debounce` on the viewport read, the two scroll helpers and the
    fullscreen autosave — rate limits.
  - `whenReady`'s own 2 s backstop, which exists so that no observer is left
    watching the document for the rest of the session. It is not the mechanism:
    the DOM change is.
- **`scrollTo`/`scrollHorizTo` still retry over three animation frames** when
  the card or column is missing. Left alone: the retry is against a *layout*
  that has not settled rather than an element that does not exist, it is
  bounded, and rewriting the scroll helpers is not this ticket.
- **doc.js still reaches into ui-layer DOM**, which S5 notes alongside the
  timers. Reduced, not removed: `#document-header`/`#history-icon` are read to
  position the GitHub sync button, which is `<body>`-mounted precisely because
  Elm's virtual DOM drops foreign children — the honest fix is to make it a
  custom element, which is a bigger change than this ticket. The header at
  least *tells* doc.js when it has rendered now instead of being polled.
  `#history-slider` is worse and also not ours: Elm sends a delta, doc.js steps
  the real slider and dispatches `input` so that `<gw-header>` can report the
  new index back to Elm. That round trip through the DOM should be an
  Elm-internal message (`Doc/History`), which is Elm-side work.
- **`wordcount-modal.ts` still declares no `observedAttributes`**, the last item
  in S13. Skipped deliberately: the review already calls it harmless (Elm
  recreates the element per open), so adding the callback would be a change with
  no behavior behind it and no test that could tell.
- **`treeToHtml` in doc.js is now provably unreachable** — `treeHelper`, the only
  thing that could build it a tree, moved to `cards.js`. It is already on ticket
  22's dead-code list, so it stays for that ticket rather than being purged here.
- **Why the rename is a transaction and not `Collection.modify`.** One
  `where(...).and(...).modify(...)` would also be atomic, but it cannot be
  faked at a seam without modelling three chained Dexie objects. A `get` and an
  `update` in one `rw` transaction says the same thing to a reader and to a
  test.
- **The port-failure allowlist is of the *benign* tags**, so a tag added to the
  dispatch table later is loud until somebody classifies it — the direction
  ticket 18 argued for, for the same reason. It also means a *renamed* tag
  (S2's `SaveCardBasedTree` → `SaveImportedTree` was one) fails loud rather
  than silent.
- **`unhandledrejection` was not asked for.** It is one listener and the other
  half of S7: the point of catching the dispatch table's rejections is that a
  rejection nobody handles is invisible, and this says so for the ones that
  reach past every handler.
- **Verification.** `bun test` 205/205, `bun run test:elm` 199/199,
  `bun run newbuild` succeeds, `node config-check.js` exits 0, and
  `bunx tsc@4.9 -p src/ui/tsconfig.json` reports only the pre-existing
  `markdown.ts` `allowSyntheticDefaultImports` error (untouched by this
  ticket). CI runs 33093422620 (c523fa2, the extractions), 33094049118
  (7bc1b0a, doc.js), 33095137252 (a2635e9, the review pass) and 33095232701
  (1b9dd9a) all green on `selfhost`.
