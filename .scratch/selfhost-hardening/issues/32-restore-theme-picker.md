# 32: Restore the theme picker

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 17 (resolved) · 24 (touches header.ts concurrently — wait for
it to resolve)

**Covers:** owner decision 2026-08-27: restore a theme picker (the strip-down
removed it in `a203a9c`; ticket 17 rebuilt and tested the save/restore round
trip, which is currently unreachable).

**What to build:** A theme picker in the header's settings menu (beside
"Word count..."), listing the six themes whose CSS already ships. Choosing
one applies it immediately (`applyTheme`) and persists via the existing
`ThemeChanged` → `SaveThemeSetting` ring (currently producer-less — this
ticket is the producer). Reloading the document restores it (ticket 17's
path, already tested). Read ticket 17's `## Answer` first: `Theme.fromLocalStore`,
the `TitleParts` render structure in header.ts, and its render-preservation
rules (don't rebuild the title input).

## Acceptance criteria

- [x] Picker reachable from the header settings menu; all six themes listed;
      current theme indicated.
- [x] Choosing a theme applies it now and survives reload (end-to-end through
      the existing tested ring — red-first test for the picker's event
      emission at seam 3, and the App.elm mapping).
- [x] Keyboard operable (real buttons/menu items — S12's standard) — the
      entries are; the icon that *opens* the menu is not, see Comments.
- [x] Full suite + build green; CI green.

## Answer

One commit on `selfhost` (claim: `a61816e`): `080d064`.

The ring was complete except for its producer, so this ticket is a producer
and one decision: **who names a theme.** The answer is `Page.Doc.Theme`, once —
`name`/`fromName` are now the module's string vocabulary, and `toValue` and
`decoder` are written in terms of them. So the `theme` attribute
`<gw-header>` is given, the `gw-theme` detail its picker reports back, and the
string in `gingko-local-store/<treeId>/settings` are the same spelling *by
construction*, which is what makes "chosen in the menu" and "restored on the
next load" the same theme. `Page.App` needs no translation table for it:
`themeMsg = Theme.fromName >> ThemeChanged`, beside `headerMenuMsg` and the
export pair.

**The picker.** `header.ts`'s settings menu now renders "Word count..." and
then, under the existing `.header-menu h4` heading "Document Theme", the six
themes in the order the removed Elm picker offered them — Default, Dark Mode,
Classic Gingkoapp, Gray, Green, Turquoise (the labels are `Translation`'s old
`en` strings; `a203a9c`'s parent has the order). Each is
`<button type="button" id="theme-<name>">`; the current one carries
`aria-pressed="true"` and `class="selected"`, and the other five
`aria-pressed="false"` — the state is announced, not only coloured.

**The mark is Elm's answer, never the click.** A click only emits `gw-theme`;
Elm sets `model.theme` (which `applyTheme` puts on `#app-root` immediately),
sends `SaveThemeSetting`, and hands the element the new `theme` attribute. A
mark moved locally would be the element showing a theme that is not the one in
effect — the same reason the export toggles read their state from
`export-settings`. Pinned by a test that clicks and asserts the mark has *not*
moved until the attribute arrives.

**Real buttons, and their keydown stops for two keys.** Both kinds of entry go
through one `menuItem` helper, so "Word count..." (a clickable `div` since the
header moved) is a button too. Enter and Space then need no handling of ours —
but they must not travel: Mousetrap binds the app's shortcuts on `document`
and ignores only form fields, so an escaping Enter would open the active
card's editor as well as choosing the theme. That is ticket 24's breadcrumb
finding, and the guard is narrow on purpose — Escape and everything else still
reach the app, so an open menu is not a trap. A test pins both halves.

**`render()` no longer drops the focus.** It throws away everything but the
title span, so the control the user was on is refocused by its id — the only
thing that survives a rebuild. Without it, choosing a theme with the keyboard
lands the user on `<body>` mid-menu, unable to try the next one; the history
slider, rebuilt on every `history` change, gains the same (arrow keys on it
used to work exactly once). Nothing inside the kept title span is ever
refocused: that is E12's select-all loop, and the input keeps its focus
naturally because it is not rebuilt.

**CSS.** `.header-menu > div` becomes `.header-menu > button` (nothing else
uses the class) plus the UA reset — `appearance`, `background`, `border`,
`color`, `font`, `text-align` — and `.header-menu > button.selected` reuses
the export toggles' `#c8ceef`/`#243586`/bold. The global `* { box-sizing:
inherit }` off `html`'s `border-box` and Tailwind's preflight already do most
of it; the reset is explicit anyway so the entry's box is the menu's decision.

### Tests

**16 new** — 9 in `tests/header.test.ts` (seam 3) and 7 in
`tests/ThemeTest.elm` (seam 10). Suites: `bun test` 202 → 211 on the tree this
was written against, 214 across 22 files once ticket 23's review pass rebased
in under it; `bun run test:elm` 199 → 206.

| what it pins | where |
|---|---|
| the six themes are listed, in order, as buttons (with the word count) | header |
| a choice reports its name, exactly once | header |
| all six names are the ones a saved theme is stored under | header |
| the current theme is the marked one, and only it | header |
| the mark moves when Elm says so, not on the click | header |
| a `theme` arriving does not discard in-progress typing (E12's rule, new attribute) | header |
| the entry chosen with the keyboard still has focus after Elm answers | header |
| Enter and Space do not reach the app's shortcuts; Escape does | header |
| the word count entry still opens the word count | header |
| a name no build wrote is `Default` | Theme |
| each theme is offered, chosen and reloaded under one name (`name`, `fromName`, and through `fromLocalStore`) | Theme |

Red first: 7 of the 9 header tests (the two that passed were the word-count
entry, which was already a clickable div, and the typing guard, which had no
attribute to react to yet). The Elm tests were red first as a `NAMING ERROR —
The Theme module does not expose a name variable`, then — since a naming error
is not a behavioural red — against a mutated spelling (`Dark` → `"darkmode"`,
`"gray"` → `Green`), which failed 4 tests including two of ticket 17's.

`ADR-0001` seam 10 and `CONTEXT.md`'s seam list name `name`/`fromName`;
`ARCHITECTURE.md` §4.3 names the picker and stops pointing the translator
block at line numbers that had already drifted.

### Verification

`bun test` 214/214 across 22 files, `bun run test:elm` 206/206,
`bun run newbuild` exit 0, `node config-check.js` exit 0, and
`tsc -p src/ui/tsconfig.json` clean (with `--moduleResolution bundler`: the
committed `node10` setting is a hard error on the tsc in this environment,
which is not this ticket's). The built bundle carries the picker
(`web/ui.js` has the labels, `web/style.css` the button rules).

CI green on `selfhost` for every push:
[33094453594](https://github.com/advaitmb/client/actions/runs/33094453594)
(`a61816e`, the claim),
[33095510389](https://github.com/advaitmb/client/actions/runs/33095510389)
(`080d064`, the picker) and
[33095750465](https://github.com/advaitmb/client/actions/runs/33095750465)
(`2771afc`, the tracker).

## Comments

- **The menu is still mouse-only to *open*, and that is the honest gap.** The
  three header icons (`#history-icon`, `#doc-settings-icon`, `#export-icon`)
  are `div`s with `onclick` — they were `div`s in `UI/Header.elm` before
  `a203a9c` moved them, and ticket 24's S12 pass did not include them. So the
  picker's entries are keyboard-operable (and tested as such) but a
  keyboard-only user cannot reach them, because nothing focusable opens the
  menu. Converting the three is ~4 lines of CSS (`appearance/background/
  border/color`, the same reset the entries got) and `div` → `button` in
  `menuButton` — but it also needs `menuItem`'s keydown guard, or Enter on a
  focused icon would open the active card's editor. Deliberately left out of
  this ticket: it changes three controls the ticket does not mention, in a
  surface no test here can see the pixels of. Worth a ticket of its own.
- **`#history-restore` has no keydown guard either**, for the same reason it
  is unreachable: the history menu opens the same way. If the icons become
  buttons, that button needs the guard too — though its escaping Enter is
  currently harmless-but-noisy rather than destructive, because history view
  sets `Page.Doc.setBlock (Just "Cannot edit while viewing history.")` and
  `preventIfBlocked` answers with an `Alert` instead of an editor.
- **Ticket 22's warning is discharged.** Its added scope says not to remove
  `ThemeChanged`/`SaveThemeSetting`/`Theme.toValue` without checking the
  owner's decision on the picker. The decision was to restore it, so the ring
  is live and reachable from the UI; nothing in it is dead any more.
  (`Theme.toValue` now has two reasons to exist: the port message, and being
  the same spelling as the attribute.)
- **Ticket 17's `isReady()` note is now *barely* reachable, and still not
  fixed here.** `localStore.set` has no `isReady()` guard, so a
  `SaveThemeSetting` with no document open would write to
  `gingko-local-store/undefined/settings`. `localStore.db(treeId)` runs at the
  top of `loadCardBasedDocument`, before Elm is sent any card data, while
  `<gw-header>` renders as soon as `documentState` is `Doc` — so the window is
  the milliseconds between `Page.App.init` and the port layer answering
  `LoadDocument`, and it takes two clicks to exploit. Left to ticket 23's
  territory (`doc.js` was being edited concurrently by it) rather than
  widening this diff.
- **Non-owners get the picker too, on purpose.** The theme is a per-document
  setting in *this browser's* `localStorage` — `SaveThemeSetting` never
  reaches the server — so there is nothing to gate on ownership, unlike the
  title field (S3). The picker is offered whatever `owner` says.
- **`aria-pressed`, not a `role="menu"` radio group.** The ARIA menu pattern
  (`role="menu"` + `menuitemradio` + `aria-checked`) also owes the user arrow
  -key navigation, Home/End and focus management for the whole menu, which
  would be a much larger change to a surface that is a plain column of
  controls. Toggle buttons that say whether they are pressed are the honest
  description of what this is.
- **Not covered by a test, and why.** (1) `Page.App`'s three lines of wiring —
  `attribute "theme"`, `on "gw-theme"`, `themeMsg` — sit in `view`, which
  needs a page `Model` and so a `Nav.Key` no test can make (seams 5, 7–10).
  The vocabulary they carry is tested at seam 10 instead, on both sides of the
  boundary. (2) That `applyTheme` reaches the DOM at all: ticket 17 pins the
  class it produces, and `#app-root` renders it already. (3) The CSS: reasoned
  from the rules it replaces (`.header-menu > div`'s box, the export toggles'
  `.selected` palette) plus Tailwind preflight, not observed in a browser.
  (4) The browser-level round trip — pick a theme, reload, see it — needs a
  running companion server and was not exercised; both halves are pinned at
  the seam and the port handler (`localStore.set("theme", elmData)`) was read.
