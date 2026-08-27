# 34: Header follow-ups — history-close semantics, export radio group, slider name

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 33 (resolved)

**Covers:** ticket 33's three recorded findings (not in CODE_REVIEW.md).

**What to build:**
1. **History close reverts the checkout** (decision taken: closing the
   history view without restoring returns the tree to current — the
   preview-exit convention). Today `CancelHistory` reverts but the icon's
   `HistoryToggled False` only closes the menu, leaving the tree at the
   snapshot. Wire the icon's close (and Esc if it closes history) to the
   reverting path in `Page.App`; a restore still commits. Pin both with
   tests.
2. **Export menu toggles get radio semantics** — the eight toggles are a
   radio group rendered as buttons; give them keyboard radio behavior
   (arrow keys, one tab stop) or justify a simpler-but-correct pattern.
3. **`#history-slider` gets an accessible name** (`aria-label`).

Read ticket 33's `## Answer` (the guard/refocus/reset conventions) and
ticket 24's S12 standard first.

## Acceptance criteria

- [x] Closing history via icon/Esc reverts to current; restore still works
      (red-first where the seam reaches — the Page.App mapping and mode
      transitions are testable).
- [x] Export group keyboard-operable per the chosen pattern, justified.
- [x] Slider named; existing header tests green.
- [x] Full suite + typecheck + build green; CI green.

## Answer

Three commits on `selfhost` (claim: `c72a52b`): `82db8bb` (item 1), `c22a608`
(items 2 and 3), `01cc716` (self-review pass).

Three findings, and the thread through them is one question asked twice or not
at all: **which control the user reached for, and what it is allowed to mean.**
Two closes disagreed about the history checkout. Eight options said nothing
about being exclusive, or reachable. One slider said nothing at all.

### 1. Leaving the history view puts the tree back — whichever control does it

`HistoryToggled False`, what the header's history icon sends, set
`headerMenu = NoHeaderMenu` and stopped: the checked-out version stayed in the
working tree with editing unblocked, one keystroke from being saved over the
document. `CancelHistory`, the menu's ✕, reverted. The decision lived at the
two call sites, so nothing could see that they disagreed — and ticket 33 made
the icon the obvious exit for a keyboard user, i.e. the wrong one.

The decision moves into **`Page.App.closeHistoryView`**, a total function from
(which control closed the view, the history, the document) to the document the
exit leaves. It takes the exit as a value naming the control —
`HistoryIcon | CancelButton | RestoreButton` — rather than a `Bool` about the
tree, so *which of the three keeps the version on screen* is answered inside
one tested function instead of at the call sites. Moving the slider is a
**checkout**; leaving without committing anything is a preview exit and puts
the tree back; a **restore** keeps what is on screen, because that is the
version being committed. Either way the editing block goes with the view.

It is a function of the history and the document because both are plain data,
where `Page.App.Model` carries a `Nav.Key` no test can make (ADR-0001 seam 5).
`toggleHistory` split into `openHistory` / `closeHistory` accordingly, and
`update` is left with putting the answer back and dropping the menu. ADR-0001
seam 11, `CONTEXT.md` and `ARCHITECTURE.md` record it.

`CancelHistory`'s two-branch body (revert / nothing to revert) collapsed into
the one function, and `RestoreVersion` stopped branching on whether it had
out-messages to send: `Cmd.batch []` is `Cmd.none`.

### 2. The export toggles are a radio group, and now behave like one

Eight `div`s with `onclick` in two segmented controls — mouse-only to operate,
for the reason ticket 33's icons were mouse-only to open. Each row is now
`role="radiogroup"` with an `aria-label` (neither row has a heading on screen
to borrow) holding four `<button type="button" role="radio">` with
`aria-checked`, and it supplies the keyboard behaviour the platform gives a
real radio and not a button:

- **One tab stop per group** — the option in effect, `tabindex="-1"` on the
  other three; the first if the attribute names none of them, which is where
  ARIA says focus enters.
- **The arrow keys** move through the options, both axes, wrapping, and the
  choice follows the focus as it does in a native radio group.

**Why not `<input type="radio">`,** which brings all of that for free: a real
radio owns its own checked state. The browser moves the dot on the click,
ahead of Elm — and every mark in this element is *Elm's answer, never the
click* (ticket 32's rule, and the reason is that Elm is what builds the file).
Taking a platform radio's own state back is the controlled-input fight
`src/ui/README.md` keeps text fields out of. Second, the segmented look needs
the input hidden behind a `<label>`, which takes the platform focus ring with
it, and ticket 33 kept that ring on purpose. The cost of `role="radio"` is
about fifteen lines of keyboard behaviour, which is what this ticket is for.

**Why not four `aria-pressed` buttons,** ticket 32's pattern for the theme
entries and the smaller change: `aria-pressed` describes *independent* toggles.
Exactly one of each four is in effect, and eight tab stops would put seven of
them between the export icon and the rest of the page — which is the thing the
ARIA pattern exists to avoid. (The theme picker keeps `aria-pressed` for a
reason of its own; see Comments.)

**The four arrows `stopPropagation`,** which is new for this repo's guard and
not optional: Mousetrap binds `left`/`down`/`up`/`right` on `document` to move
between cards, so arrowing through the export options would have moved the card
cursor behind the open menu as well. They `preventDefault` too, or the page
scrolls instead. Enter and Space keep going through the shared
`stopActivationKeys`; Escape still reaches the app, as everywhere in the header.

**CSS.** `.toggle-button div` becomes `.toggle-button button` (plus the two
width rules) with the reset the entries and icons got — `appearance`,
`background`, `color`, `font` added; `border` and `text-align` were already
declared, carrying this group's own values rather than being reset to nothing.
Preflight is off in this repo, so those are the whole reset (ticket 33's
correction). `color: inherit` keeps `.toggle-button`'s gray, which buttontext
would replace; `font: inherit` keeps the label out of a UA button's 13px inside
a 30px row. The focus ring is left alone.

### 3. The slider has a name

`aria-label="Document version"` on `#history-slider`. A bare range input
announces itself as "slider, 3 of 6" and nothing about what the 3 counts. It
was already keyboard-operable (an `<input>`, which Mousetrap leaves alone), so
this was the whole of it.

### Tests

**15 new** — 6 in `tests/HistoryExitTest.elm` (seam 11) and 9 in
`tests/header.test.ts` (seam 3). Suites: `bun run test:elm` 206 → 212,
`bun test` 245 → 254 across 23 files.

| what it pins | where |
|---|---|
| the history icon's close puts the document back where the view opened | HistoryExit |
| the ✕ does too | HistoryExit |
| a restore keeps the version on screen | HistoryExit |
| after each of the three, the document can be edited again — on the version that exit chose | HistoryExit (3) |
| each row is a named radio group of real `type="button"` radios | header |
| the option in effect is the checked one, and the group's only tab stop | header |
| the checked option is Elm's answer, not the click | header |
| a click still reports the choice | header |
| Enter and Space choose, and do not reach the app's shortcuts | header |
| the arrows move through the row, both axes, wrapping, choosing each | header |
| the arrows do not reach the app's shortcuts, and are cancelled; Escape still does | header |
| the option chosen with an arrow key still has focus, and the tab stop moved with it | header |
| the slider says what it moves through | header |

Red first: 2 of the 6 Elm tests (the icon's close left `"Yesterday's card"` in
the working tree, editable — the other four pin the ✕ and the restore, which
were already right), and 8 of the 9 header tests. The ninth — a click still
reports the choice — passed against the `div`s, which is what it is for.
Mutation-checked after: dropping `role` fails 1, eight tab stops fails 1,
dropping the arrows' `stopPropagation`/`preventDefault` fails 1, dropping the
arrow handling entirely fails 3, an unnamed group fails 1, an unnamed slider
fails 1, and moving the mark on the click fails 1.

`src/ui/README.md` gains the radio-group standard beside S12's rule, and the
keydown rule names the arrow keys as a case of itself.

### Verification

`bun test` 254/254 across 23 files, `bun run test:elm` 212/212,
`bun run typecheck` exit 0, `bun run newbuild` exit 0, `node config-check.js`
exit 0. The bundle carries them: `web/ui.js` has `radiogroup`, `aria-checked`
and `"Document version"`, `web/style.css` the `.toggle-button button` reset
with its autoprefixed `appearance` twins.

CI green on `selfhost` for every push:
[33108953282](https://github.com/advaitmb/client/actions/runs/33108953282)
(`c72a52b`, the claim),
[33110060125](https://github.com/advaitmb/client/actions/runs/33110060125)
(`82db8bb`, the history exit),
[33113816293](https://github.com/advaitmb/client/actions/runs/33113816293)
(`c22a608`, the radio groups and the slider) and
[33114139671](https://github.com/advaitmb/client/actions/runs/33114139671)
(`01cc716`, the review pass).

## Comments

- **Esc turned out not to be one of the exits.** The ticket asked for "the
  icon's close (and Esc if it closes history)". It does not: the history view is
  `headerMenu`, `esc` is dispatched on `modalState`, and with `NoModal` it falls
  through `Page.App`'s limb to `Page.Doc` — no keystroke anywhere sets
  `headerMenu = NoHeaderMenu`. So the exits are the icon, the ✕ and Restore,
  which is why `HistoryExit` has exactly three names. Whether Esc *should* close
  the view is a question about the header menus as a set, not about this
  finding, and is left alone.
- **The theme picker keeps `aria-pressed`, and should.** It is six marked
  entries in a column that also holds "Word count…", a plain command. A radio
  group cannot contain a command, and a column that mixes them is the ARIA
  *menu* pattern (`menuitemradio`, full focus management) that ticket 33
  declined for the icons. A row of four exclusive options with nothing else in
  it is a clean radiogroup; a mixed menu column is not. Left alone deliberately,
  not overlooked.
- **`.selected` and `aria-checked` are the same fact twice.** `role="radio"`
  requires `aria-checked`, and the stylesheet's segmented-control rules key off
  `.selected` — the pair ticket 32 established for the theme entries. Styling
  off `[aria-checked="true"]` and deleting the class would remove the
  duplication, and was not done: it changes the visual rules with no browser
  here to check them, for no behavioural gain. Worth doing to both surfaces at
  once if either is touched again.
- **No Home/End in the radio groups.** The ARIA radio group pattern does not
  ask for them (they belong to listbox/menu), and four options are two arrow
  presses from either end. Not an omission to fix.
- **What is not covered by a test, and why.** (1) That Enter and Space activate
  a `<button>` at all, and that an unhandled arrow key scrolls the page: jsdom
  implements no default actions, so `press()` writes the platform's rule out and
  the arrow tests read `preventDefault` rather than the scroll it prevents —
  ticket 33's standing. (2) The CSS, reasoned from the rules it
  replaces plus the UA button styles; the built `web/style.css` was read to
  confirm the properties survive autoprefixing, but nothing was seen in a
  browser (there is none in this environment). (3) The screen reader's actual
  announcement of a radio group's position ("2 of 4"); what is pinned is the
  roles and states it reads. (4) Which control sends which `HistoryExit` — one
  line each in `update`, out of reach at seam 11 as the `Cmd` is; verified by
  inspection.
- **Ticket 33's three findings are all closed now**, so nothing from it carries
  forward. What the header still does not have: `h`/`j`/`k`/`l` and the
  other single-letter shortcuts still reach `document` from a focused header
  control, because the guard is deliberately narrow (only the keys a control
  handles). Typing `j` while the export icon has focus moves the card cursor
  behind the menu. Pre-existing, unchanged by any of these three tickets, and
  arguably correct — a focused control is not a trap — but it is the next thing
  someone will notice.
