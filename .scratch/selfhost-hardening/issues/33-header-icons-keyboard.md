# 33: Header icons are mouse-only

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 32 (resolved)

**Covers:** new finding from ticket 32's resolution (S12's family; the
pre-existing hole ticket 24 didn't cover).

**What to build:** The three header icons (settings gear, export, history)
are `div`s with `onclick`, so the menus ticket 32's picker lives in are
mouse-only to OPEN. Make them real `type="button"`s (or keyboard-operable
per ticket 24's S12 standard), with the same Enter/Space keydown guard
tickets 24/32 used (Mousetrap's document bindings ignore only form fields —
an escaping Enter opens the active card's editor). Keep ticket 17's
render-preservation rules (title input never rebuilt) and 32's refocus
convention.

## Acceptance criteria

- [x] Each header icon reachable and operable by keyboard; red-first seam-3
      tests per icon.
- [x] No Mousetrap leakage (Enter/Space guarded); existing header tests stay
      green.
- [x] Full suite + build + tsc green; CI green.

## Answer

Two commits on `selfhost` (claim: `bc21e8b`): `a02e737`, `7599f93`.

Nothing here is a new mechanism. Ticket 32 built all three pieces — a real
`<button>`, the two-key keydown guard, and `render()`'s refocus-by-id — and
applied them to the menu *entries*; this ticket applies them to the five
controls that were left, and the ticket is small because that is all it is.

**The three icons.** `menuButton` renders `<button type="button">` instead of
`div`, so the platform gives Enter, Space, the tab stop and the focus ring, and
the guard (now `stopActivationKeys`, shared with `menuItem` rather than a
second copy) keeps those two keys off `document`. `label` was already the
tooltip and is now the accessible name too (`aria-label`): the icon is a bare
glyph, so there is nothing for a screen reader to fall back on — and `title` is
only a *fallback* name, which not every AT reports. `aria-expanded` says
whether the menu is open, because `.open` only colours it; like the theme mark
it is **Elm's answer, never the click** — the attribute arrives, the icon
follows.

No `aria-haspopup`. It promises the ARIA menu pattern (arrow keys, Home/End,
focus management for the whole menu), which is exactly what ticket 32 declined
for `aria-pressed`; a disclosure that reports whether it is expanded is the
honest description of a column of plain controls. Focus stays on the icon
across the rebuild Elm's answer causes — that is 32's refocus, and this ticket
is the first thing that makes it matter for the icons, since a `div` had no
focus to keep.

**The history menu came with them**, as ticket 32's Comments said it would have
to. `#history-restore` was already a `<button>` and gains the guard;
`#history-close-button` was another `div` with `onclick` and is now a button.
The close button is not a duplicate of toggling the icon shut: `CancelHistory`
**reverts** the checked-out version, while the icon's `HistoryToggled False`
only closes the menu — so it has to be operable in its own right, or the
keyboard path this ticket opens leads into a menu whose only correct exit is
the mouse. The slider needs nothing: an `<input>` is keyboard-operable and
Mousetrap ignores form fields.

**CSS, and a correction.** `.header-button` and `#history-close-button` get the
reset the menu entries got — `appearance`, `background`, `border`, `color`,
`font`, `text-align`. Ticket 32 credited "Tailwind's preflight" with most of
that: **preflight is off in this repo** (`tailwind.config.js`, and
`ARCHITECTURE.md` §3 step 4 says so), so the reset is the whole of it, not
belt-and-braces. `color` is the one that shows: `dom.ts` strokes its icons with
`currentColor`, so a button's own `color` would repaint every glyph in the
header. `font: inherit` matters next — a UA button's 13px font changes the line
box the 20px glyph sits in. The focus ring is deliberately left alone; it is
how a keyboard user knows which icon they are on. The rule is written out three
times now (entries, icons, close button) rather than grouped: locality, and
32's reason — each control's box is its own decision.

`src/ui/README.md`'s rules gain the standard this applied, beside the keydown
rule that is its consequence: anything that reports a click is a real control,
an icon-only one needs an `aria-label`, and here is the reset list.

### Tests

**9 new**, all in `tests/header.test.ts` (seam 3). Suites: `bun test` 236 → 245
across 23 files; `bun run test:elm` 206, untouched — nothing Elm changed.

| what it pins | which control |
|---|---|
| a real `type="button"`, in the tab order, focusable, named | the three icons |
| Enter asks for the menu that icon owns | the three icons |
| Space on an open icon asks to close it (a toggle, not a second open) | settings |
| the icon says whether its menu is open, and moves when Elm says so | settings, export |
| Enter and Space do not reach the app's shortcuts; Escape does | the three icons |
| the icon still has focus after Elm opens *and* closes the menu | settings |
| the menu an icon opens is the next thing in the tab order | settings |
| real buttons, focusable, and a keyboard press reports restore / cancel | history menu |
| Enter and Space do not reach the app's shortcuts | history menu |

jsdom implements no activation behaviour, so a keyboard press is one `press()`
helper that writes the platform's rule out: the keydown, then — only for a
control the browser itself activates, and only if nothing cancelled it — the
click. A `<div onclick>` gets the keydown and nothing else, which is exactly
what a keyboard user gets from one, and is why these tests could be red at all.

Red first: all 9, against today's code — `Received: "DIV"`, `asked: []` where a
menu should have been requested, `["Enter", " ", …]` escaping to `document`,
and `document.activeElement` on `<body>` after the menu opened. Mutation-checked
after: divs again fails 5 of the 9, `stopActivationKeys` narrowed to Enter fails
all three leak tests (ticket 32's included), and dropping `aria-expanded` fails
the one that reads it.

### Verification

`bun test` 245/245 across 23 files, `bun run test:elm` 206/206,
`bun run typecheck` exit 0, `bun run newbuild` exit 0, `node config-check.js`
exit 0. The bundle carries them (`web/ui.js` has `aria-expanded` and the
button, `web/style.css` the two resets).

CI green on `selfhost`:
[33107579605](https://github.com/advaitmb/client/actions/runs/33107579605)
(`bc21e8b`, the claim),
[33108089594](https://github.com/advaitmb/client/actions/runs/33108089594)
(`a02e737`, the icons) and
[33108424724](https://github.com/advaitmb/client/actions/runs/33108424724)
(`7599f93`, the review pass) and
[33108663593](https://github.com/advaitmb/client/actions/runs/33108663593)
(`83c4ee8`, the tracker).

## Comments

- **Closing the history menu from the icon does not revert the checkout, and
  that is a bug this ticket only makes easier to hit.** `CancelHistory` reverts
  the tree; `HistoryToggled False` — what the icon sends — just sets
  `headerMenu = NoHeaderMenu`, leaving the checked-out version in the working
  tree with editing unblocked. It was reachable by mouse already (click the
  icon instead of the ✕), but a keyboard user now has the icon as the obvious
  exit, and it is the wrong one. Not fixed here: the fix is in `Page.App`'s
  message handling, not in a control, and "which of the two closes is right"
  is a decision about history semantics (ticket 12's territory) rather than
  about keyboard access. Worth a ticket.
- **What is still not keyboard-reachable in the header.** The export menu's
  eight toggles (`#export-selection` / `#export-format`) are `div`s with
  `onclick` inside a `.toggle-button` group — same defect, same fix, but they
  are a *radio group*, so they also want `role="radio"`/`aria-checked` or
  `aria-pressed` and arrow-key semantics to be honest, and the stylesheet
  styles them as a segmented control (`.toggle-button div`, with `:first-child`
  / `:last-child` rounding), which is more CSS than the two resets here. Deliberately out: the ticket names the three
  icons, and the export menu is a coherent unit of its own. `#history-slider`
  has no accessible name either (a bare range input announces "slider"); one
  `aria-label` would fix it, but it was already keyboard-operable, so it is a
  naming gap, not this ticket's.
- **Ticket 32's CSS reasoning had preflight in it, and preflight is off.** Its
  Answer says "the global `* { box-sizing: inherit }` off `html`'s border-box
  and Tailwind's preflight already do most of it". The box-sizing half is
  right; the preflight half is not — `tailwind.config.js` sets
  `corePlugins: { preflight: false }` and only the three `@import`s of
  base/components/utilities reach `style.css`, so no `button` reset ships
  except the ones written by hand. The conclusion both tickets reached is
  unaffected (write the reset out), but the *reason* is stronger than 32
  thought: without those six lines the entries and icons would have rendered
  as native grey buttons. Recorded here rather than edited into 32.
- **Not covered by a test, and why.** (1) That Enter and Space activate a
  `<button>` at all: that is the platform, and jsdom does not implement it —
  `press()` names the rule instead of pretending to observe it, and what the
  tests then check is that the control *is* one the platform activates. (2) The
  CSS: reasoned from the rules it replaces plus the UA button styles, not
  observed in a browser (no browser in this environment) — same standing as
  32's. The built `web/style.css` was read to confirm the properties survive
  autoprefixing (`appearance` gains `-webkit-`/`-moz-` twins). (3) The screen
  reader's actual announcement of `aria-label`/`aria-expanded`; what is pinned
  is the attributes, which is what AT reads.
