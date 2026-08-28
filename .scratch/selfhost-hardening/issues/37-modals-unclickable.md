# 37: Every modal but the help modal is unclickable

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** none — found by running the app (2026-08-28)

**Covers:** new finding, NOT in CODE_REVIEW.md and not caught by any of the
485 tests. Pre-existing: `src/static/style.css` is byte-identical to the
review commit here, and no commit in tickets 01–36 touched `pointer-events`.

**What was wrong:** `mountModal` (`src/ui/modal.ts`) builds every modal as
`.modal-overlay` + `.max-width-grid > .modal`. `.max-width-grid` carries
`pointer-events: none` so the app behind it stays clickable — and
`pointer-events` **inherits**, so `.modal` and everything in it became
pointer-transparent. Clicks aimed at a modal's own controls fell through to
`.modal-overlay`, whose only handler closes the modal. `.help-modal` was the
one surface that opted back in (`pointer-events: all`), which is why the help
modal worked and nothing else did.

Confirmed in a real browser, not by reading: with the New Document modal open,
`document.elementFromPoint()` at the centre of the "Blank Tree" link returned
`DIV.modal-overlay`, and the computed `pointer-events` on `#template-new` was
`none`. So a mouse user could not create a document from the empty state at
all — the most basic path in the app.

**Why no test caught it:** the jsdom tests assert rendered DOM and emitted
events, and the elements and handlers were all correct. This is a cascade
bug: only a real layout engine resolves inherited `pointer-events` and
hit-tests a point.

## Acceptance criteria

- [x] `.modal` opts back into pointer events, so every `mountModal` surface is
      clickable (one rule, not one per modal).
- [x] Verified in a real browser: the hit test at a modal control returns that
      control, and clicking "Blank Tree" creates a document.
- [x] A regression guard that does not need a layout engine: the invariant
      read off the shipped stylesheet, not the rendered DOM.
- [x] Full suite + build green.

## Answer

One rule in `src/static/style.css`: `.modal { pointer-events: auto; }`, with a
comment saying why it is needed (the wrapper's `pointer-events: none`).
`.help-modal`'s own `pointer-events: all` is now redundant but harmless and
left alone.

`tests/modal-css.test.ts` pins it: the wrapper is `pointer-events: none`,
`.modal` re-enables it, and the overlay still receives clicks. It parses
`style.css` because jsdom resolves no cascade — comments stripped first, since
the explanatory comment on the rule quotes both `none` and `all` and a naive
read of the block returns those instead of the declaration. Mutation-checked:
deleting the one line turns the middle test red (`Received: null`).

Verified in headless Chromium against the real `gingko/server`:
`elementFromPoint` at the "Blank Tree" link returns the link, the click
creates a document, and the header/theme/export/history surfaces it gates
became reachable.

## Comments

- This is the one finding of the whole effort that came from **running** the
  app rather than reading it. Worth a `run`-style project skill so the next
  agent can launch the client against the server without rediscovering the
  setup (see the session's notes: the server needs redis, a newer
  `better-sqlite3` for Node 22, `../client/web` and `../data/` relative to its
  CWD, and it has no `GET /me`).
- CI green on `selfhost`: `010d078` — <https://github.com/advaitmb/client/actions/runs/33155127723>
