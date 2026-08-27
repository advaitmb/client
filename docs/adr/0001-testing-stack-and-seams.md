# ADR-0001: Testing stack and pre-agreed seams

**Status:** accepted · **Date:** 2026-08-27

## Decision

- **Elm:** `elm-test` (via `elm-test-rs` or npm `elm-test`), tests under
  `tests/`. Primary target: the `Doc.Data` public API and other pure document
  logic (`UpdatedAt`, `TreeStructure`, `Coders` exports).
- **TypeScript/JS:** `bun test` (built into the canonical runtime, ADR-0004),
  with `happy-dom` (or jsdom) registered for custom-element tests. Targets:
  `src/ui/*` elements (attribute-in → DOM/event-out) and pure helpers
  extracted from `src/shared/doc.js`.
- **CI:** one workflow (`.github/workflows/ci.yml`) running on pushes and PRs
  to `selfhost`: install (bun), typecheck/build, `elm-test`, `bun test`,
  `config-check` (which must exit non-zero on mismatch). The upstream
  Electron-era `build.yml` and `master`-only `web-deploy.yml` are deleted —
  they call scripts that no longer exist.

## Pre-agreed seams (the `tdd` skill requires these to be fixed up front)

1. `Doc.Data` public functions — behavior of localSave, tree
   materialization, sync-state classification, delta generation, conflict
   resolution, restore. Test through exported functions only; the
   `*_tests_only` exports may be used where the public surface is too coarse,
   or removed if unused.
2. Pure JS sync helpers — HLC stamp comparison, checkpoint computation,
   backup-version selection. Extract them from `doc.js` into an importable
   module first; do not test through Dexie or the WebSocket.
3. Custom elements — public contract only: set attributes, observe rendered
   DOM and emitted `CustomEvent`s. No reaching into private fields.
4. Session-level sequences extracted from `doc.js` — added by ticket 04 for
   the logout sequence, extended by ticket 13 with adopting the server's
   account on boot (`src/shared/session.js`), by ticket 08 with the local
   half of a save (`src/shared/save.js`), and by ticket 16 with the drag
   lifecycle (`src/shared/drag.js`: which drag is in progress, what Elm is
   told, and drag auto-scroll — observed through dispatched DOM events,
   whether the browser's own drop handling was prevented, and injected
   timers, so an autoscroll is a callback the test runs). These are not pure, so
   seam 2 does not cover them: the rule is the same extraction (nothing in
   `doc.js` itself is importable, it boots the app at module load) but they
   are observed through the boundaries they actually cross — a faked `fetch`,
   the real `localStorage`, and the callbacks the port layer passes in. Still
   never through Dexie or the WebSocket: where a sequence is a database
   writer, the database is **injected** and the test passes an in-memory fake
   of the tables it touches, asserting on the rows it is left holding (never
   on which calls were made in which order). The fake models the Dexie
   behaviors the sequence depends on — `Table.update` on an absent key writes
   nothing, an undefined key is an error — and says so where it does.
5. `Session`'s stored-blob surface (Elm, pure) — `decode` and `encode` of the
   session blob, and `responseDecoder` for what a login answers: the
   preferences this client persists, and that stale or partial stored data
   must not break. Recorded by ticket 13; ticket 03's `tests/SessionTest.elm`
   was already here. Test through `Session`'s exported functions, plus the
   `Page.App` helpers that decide what gets stored (`sidebarIsOpen`) — never
   `Page.App.update` itself, which needs a `Nav.Key` no test can make.
6. Build-time gates — the scripts `newbuild` and CI depend on:
   `config-check.js` (ticket 01, run as a subprocess against fabricated
   `config.js` files in a temp dir) and `elm-postprocess.mjs`'s placeholder
   substitution (ticket 20). Same rule as seam 2: expose the decision as a
   pure function taking its inputs (`substitutePlaceholders(code, conf)`) and
   test that, not the ambient `config.js`. These are in scope because a
   silently-passing gate is indistinguishable from a missing one — exactly
   the B1 and B13 failures.
7. Auth forms (Elm, pure) — what the login and signup forms accept, and what
   the client then asks the server to create an account with:
   `Page.Login.credentialsValidator` and `Session.signupBody`. Recorded by
   ticket 19. Tested through those two exports rather than the views, because a
   page `Model` carries a `Nav.Key` no test can make — which is why the
   validator is extensible in its subject.

8. Routing (Elm, pure) — which page a URL names: `Route.loggedInLanding` and
   `Route.guestLanding`, total functions from (session kind, path) to the page
   to initialize plus any correction to the address bar. Recorded by ticket 14.
   Same reason as seams 5 and 7 for not testing the caller: `Main` and every
   page `Model` carry a `Nav.Key` no test can make, so the decision is
   extracted and `Main` is left with only the mechanical part (initialize that
   page, batch its commands with the URL change). `Route.toString` is tested in
   the same file, by round trip: the URLs the app builds must parse back to the
   pages they were built for.

9. Drop placement (Elm, pure) — where a dragged card lands:
   `Doc.TreeStructure.dropPlacement`, a total function from (dragged card, drop
   region, tree) to the `Mov` arguments for the drop, or to nothing when the
   drop names no place the card can go. Recorded by ticket 16. Same reason as
   seams 5, 7 and 8 for not testing the caller: `Page.Doc.Msg` is opaque and
   its `update` answers in `Cmd`s no test can inspect, so the decision is
   extracted and `Page.Doc` is left with only the mechanical part. It lives in
   `Doc.TreeStructure` because the index it computes is an index into the tree
   `Mov` prunes and re-inserts, which is that module's own rule.

10. What the document's chrome says and writes (Elm, pure) — four small
    decisions that only ever showed up on screen or in a saved file, so nothing
    could tell a placeholder from a real answer. Recorded by ticket 15:
    `Page.Doc.Incoming.fromOutside`, the total function from a `{ tag, data }`
    message to a `Msg` or an error (extracted from `subscribe`, whose `Sub msg`
    cannot be run — which is how a tag with no branch at all went unnoticed);
    `Page.Doc.Export.toString` and `toMimeType`, what an export writes and what
    it is saved as; `Doc.UI.documentWordcount` with `Page.Doc`'s
    `getStartingWordcount`, the two halves of the word-count modal's "Session"
    row; and `Translation.tr` for the shortcut tray's key names. Same reason as
    seams 5, 7, 8 and 9 for not testing the callers — a page `Model` needs a
    `Nav.Key`, and `Page.Doc.update` answers in `Cmd`s no test can inspect — but
    here the *state* `Page.Doc` carries is plain data, so the session-start
    count is tested through its own setters and getter.

    Out of reach at this seam, and so verified by inspection: whether a port
    command is sent at all. `preventIfBlocked`'s ordering (E5) and the one-line
    view wiring that hands the modal its starting count are both of that kind.

11. The document's mode machine (Elm) — which mode a document is left in after
    an event: `Page.Doc.getViewMode` after `opaqueIncoming` (or `opaqueUpdate`),
    on a document built from the exported setters (`init`, `setTree`,
    `setBlock`, `setLoading`). Recorded by ticket 31, whose subject is a
    transition that must *not* happen: no editor of any kind, fullscreen
    included, opens on a blocked document. The `Cmd` half stays out of reach as
    at seam 10 — but the mode is plain data, and "the fullscreen editor did not
    open" is the whole of the behavior.

    Where a transition is reachable only from a DOM event whose `Page.Doc.Msg`
    constructor is not exported (the card editor's fullscreen button,
    `gw-edit-fullscreen`), the event is simulated on `Page.Doc.view` with
    `Test.Html.Event` and the `Msg` it yields is handed to `opaqueUpdate`. That
    is the app's own route into the transition, not a side channel: the view
    stays the only thing that names the message.

No test is written at a seam outside this list without updating this ADR.

## Context

The branch shipped with zero tests and CI that cannot fail
(CODE_REVIEW.md B1–B3). Every bug-fix ticket derived from the review is
TDD-shaped and blocked on this ADR's stack existing.
