# 35: Single-letter shortcuts reach the document from focused header controls

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 34 (resolved)

**Covers:** new finding from ticket 34's resolution (not in CODE_REVIEW.md).

**What to build:** Mousetrap binds single-letter shortcuts (`h`/`j`/`k`/`l`,
`w`, `/`, …) on `document`, and it only ignores form fields — so with a
header control focused (icon, menu entry, theme swatch, export toggle),
typing `j` moves the card cursor behind the open menu. Tickets 32–34's
keydown guard is deliberately narrow (Enter/Space, and arrows for the radio
groups), so these still leak.

Decide and implement the scope rule: either the header element swallows
printable-key keydowns while it holds focus / has a menu open, or Mousetrap's
`stopCallback` learns to ignore keys originating inside `<gw-header>` (the
latter is one place instead of many, and generalizes to the sidebar and
modals — prefer it unless there's a reason not to). Keep Escape working, and
keep the deliberate cases: shortcuts SHOULD work when focus is on the body
or a card.

Read tickets 32/33/34's `## Answer` sections for the existing conventions
before choosing.

## Acceptance criteria

- [x] Red first: with each header control focused, a single-letter shortcut
      does not reach the document handler; Escape still does.
- [x] Shortcuts still work with focus on body/card (pinned).
- [x] Full suite + typecheck + build green; CI green.

## Answer

Two commits on `selfhost` (claim: `4a60dc5`): `6621501`, `0cf8392`.

The leak is not a bug in a control. It is a **missing statement about regions**:
Mousetrap binds every shortcut on `document` and its own `stopCallback` ignores
form fields, which was the whole truth while every control outside a field was a
`div` with `onclick`. Tickets 32–34 turned the header into real buttons, and
nothing anywhere said that a keystroke aimed at one of them is not also aimed at
the document behind it. So the ticket's preferred approach is the one taken, and
almost all of the work was deciding *what the rule is*, not where to put it.

`src/shared/shortcut-scope.js` — `shortcutReachesApp(element, combo)`, installed
as `Mousetrap.prototype.stopCallback` in `doc.js` (ADR-0001 seam 14). Four
clauses, in the order the questions have to be asked:

1. **`.mousetrap` wins** — Mousetrap's own opt-in, which this app means: the card
   editor's textarea (`edit mousetrap`) and `input#switcher-input.mousetrap`.
   First, so a marked field *inside* the chrome keeps the shortcuts — the
   switcher is a modal, and the arrows, Enter and `mod+o` are how it works.
2. **A form field is the field's** — Mousetrap's default rule, kept whole,
   Escape and the chords included.
3. **Inside the chrome, an unmodified keystroke is the control's**, with two
   exceptions going the other way (below).
4. **Otherwise the keystroke is the document's** — the deliberate case.

### The scope rule is a region, not a control

`element.closest()` against a list of chrome elements — `gw-header`,
`gw-sidebar`, and the four modals — rather than a `data-` attribute each element
sets or a test for "is the focused thing a control".

**Not a data attribute** (the ticket's other suggestion): it spreads one
decision over six files, where the decision is "which regions of this app are
chrome" and reads best as one list. The failure modes are not symmetrical
either — a new element that forgets the attribute leaks, and so does a new
element missing from the list, but the list is somewhere a reader can see what
is *not* on it.

**Not "a focused control"**, which needs no list at all and would generalize
itself, because the app has focusable controls in the *document* surface, where
the shortcuts must keep working:

- **A link in a card.** `gw-markdown` renders card content, and a link in a card
  opened in a new tab leaves the focus on itself in this one. Under a
  control-shaped rule, clicking a link in a card would silently turn `h`/`j`/
  `k`/`l` off until the user clicked elsewhere.
- **The shortcut tray's formatting-guide link** (`Doc.UI.viewShortcuts`,
  `target="_blank"`), and the same for the breadcrumbs and mobile buttons if
  they are ever made real controls: they are furniture *around* the document, and
  the next keystroke after touching one belongs to the document.
- A GFM task checkbox in card content is an `<input>`, so the form-field rule
  already covers the one control in a card that reads keys.

That is the whole argument for the region: chrome-ness is a judgement about
whether a surface's own controls own the keyboard, and it cannot be read off an
element's tag. The test file pins it as a pair — the same `<a>`, inside a card
and inside a modal, with opposite answers.

The Elm-rendered chrome (the export dialog, the sidebar context menu, the toasts,
the conflict banner) is deliberately not on the list: every one of its controls
is still a `div` with `onclick`, so no keystroke can be aimed at one. `gw-sidebar`
*is* on it although its controls are also still `div`s — the rail is chrome
whether or not S12 has reached it yet, and this is one line rather than a second
visit.

### The two exceptions, and why the second one exists

**Escape reaches the app**, as the ticket requires: it is the way out of the
chrome, and Elm owns which menu or modal is open — no control in the header
closes itself.

**A modifier chord reaches the app.** This was not in the plan and came from
reading `doc-helpers.js`'s `needOverride`: `mod+s`, `mod+o`, `mod+b`, `mod+i` and
`alt+0`–`alt+6` are cancelled by the shortcut handler *returning false*, i.e.
from inside the callback. A blanket "everything but Escape stops" rule would
therefore not have made those keys do nothing — it would have handed them back to
the **browser**, so `mod+s` on a focused header icon (which is where the focus is
after any click in Chrome or Firefox) would open Save-page, and `mod+o`
Open-file. Replacing "the app acts behind the chrome" with "the browser acts" is
worse than either.

And it is principled rather than a hedge: a button, a link or a radio is operated
with Enter, Space, the arrows and Tab, and everything else unmodified is typing;
none of them interprets a chord. The controls that *do* read chords are the
fields — `mod+v` in the title field is a paste into the title — and clause 2 has
already answered for them. Shift is not a modifier here: `shift+enter` and `?`
are what typing looks like.

So the first commit's blanket rule was replaced by this one mid-implementation,
and the test that asserted the blanket version was rewritten in the opposite
direction rather than deleted.

### Two things that follow from it

**Tab works in the header now.** `Mousetrap.bind(["tab"])` inserts two spaces and
returns false, which *cancels* the keystroke — so outside a `.mousetrap` field
Tab moved the focus nowhere at all, and the tab stops tickets 33 and 34 built
into the header (`tabindex`, one stop per radio group) were unreachable by the
Tab key. A keystroke that is now the chrome's never reaches that binding, so the
platform moves the focus. Pinned.

**The header's own guards stay.** `stopActivationKeys` and the radio groups'
arrow handling are not made redundant: they answer "this control handled this
key" (and for the arrows, `preventDefault` so the page does not scroll), which a
`stopCallback` cannot do — it only decides whether the *app* acts. They are also
what keeps the existing seam-3 tests meaningful. `src/ui/README.md` now says
which layer answers which question, so the next control does not get a guard
listing every letter.

### Tests

**14 new**, all in `tests/shortcut-scope.test.ts` (the new seam 14). Suites:
`bun test` 254 → 268 across 24 files; `bun run test:elm` 217, untouched —
nothing Elm changed.

| what it pins | how |
|---|---|
| no kind of header control lets a letter through | the 9 buttons + the 2 fields, each focused first |
| nor any other unmodified shortcut, the arrows included | `w`, `/`, `[`, `]`, `?`, the four arrows, `shift+enter` |
| Escape still reaches the app from every header control | the 9 buttons |
| a chord still reaches the app from a header control | `mod+s`, `mod+o`, `mod+z`, `mod+shift+z`, `alt+j`, `alt+3` |
| a field in the chrome consumes Escape and the chords too | the title field and the history slider |
| with nothing focused the shortcuts are the document's | `document.body`, header on the page |
| a keystroke with no element behind it is the app's | `document`, and nothing at all |
| a card and its content are not chrome, link and all | a real `<gw-tree>` card holding a `<gw-markdown>` link |
| the same link inside a modal is the modal's | `<gw-template-modal>`'s `#template-new` |
| the sidebar gets the rule without being named at the call site | `<gw-sidebar>` |
| the switcher's search box keeps the shortcuts it is marked for | `#switcher-input.mousetrap`, inside a modal |
| the card editor keeps them, Tab included | `textarea.edit.mousetrap` |
| the search field is left exactly as Mousetrap had it | `input#search-input` |
| Tab is the chrome's, so the focus moves | `reachesFrom(…, "tab")` |

Red first: the first test was written against the module in its
**extraction-only** form — the same file, reproducing Mousetrap's own rule and
nothing more, wired up and with the full suite still at 254 — and failed
`Expected: false, Received: true`: `j` reached the app from the focused export
icon. Run against that same extraction, 5 of the final 14 fail.

Mutation-checked after: dropping the chrome clause fails 5, the Escape exemption
3, the chord exemption 1, counting shift as a modifier 1, asking the chrome
before `.mousetrap` 2, narrowing the chrome list to the header alone 2, and
dropping the form-field rule 2.

Recorded: ADR-0001 seam 14 and `CONTEXT.md`'s seam list; `CONTEXT.md` also gains
**chrome / document surface** as vocabulary under Application layers, since that
distinction is now load-bearing; `ARCHITECTURE.md` §4.4 states the rule beside
the Mousetrap paragraph; `src/ui/README.md` gains the rule about which layer
covers which keys.

### Verification

`bun test` 268/268 across 24 files, `bun run test:elm` 217/217,
`bun run typecheck` exit 0, `bun run newbuild` exit 0, `node config-check.js`
exit 0. The bundle carries it: `web/doc.js` has
`cl.prototype.stopCallback=function(t,r,s){return!cp(r,s)}` immediately above
`cl.bind(ti.shortcuts, …)`, and the chrome list as its six literals.

CI green on `selfhost` for every push:
[33117828584](https://github.com/advaitmb/client/actions/runs/33117828584)
(`4a60dc5`, the claim),
[33118906371](https://github.com/advaitmb/client/actions/runs/33118906371)
(`6621501`, the rule) and
[33119152736](https://github.com/advaitmb/client/actions/runs/33119152736)
(`0cf8392`, the review pass).

## Comments

- **A header menu can still be open with nothing focused, and then the letters
  reach the document.** Safari does not focus a button on click, so a Safari user
  who opens the export menu with the mouse leaves the focus on `<body>`, and this
  rule — which is about where the keystroke was *aimed* — has nothing to catch.
  The ticket's alternative approach (the header swallows printable keys while a
  menu is open) would cover it, at the price of a rule that no longer generalizes
  to the sidebar or the modals. The right home for the remaining case is not the
  port layer at all: **`Page.App` already gates the shortcuts on `modalState`**
  (with any modal open, only `esc`/`mod+o`/`w`/`?` do anything and the rest are
  dropped), and `headerMenu` is simply not consulted there. Adding it to that
  `case` is one Elm change in the place that owns the state, and it belongs with
  the question ticket 34 left open — whether Esc should close the header menus at
  all. Worth a ticket; deliberately not smuggled into this one.
- **`mod+backspace` and the other destructive chords still act from a focused
  chrome control**, by the clause above. That is the cost of not handing the
  browser its own dialogs back, and it is the same standing as today: the user
  who presses `mod+backspace` means it, and a button consumes no part of it.
- **The chrome list will drift if a surface is added without reading
  `src/ui/README.md`.** The mitigation is that the failure is the status quo (a
  leak) rather than dead shortcuts, and both the README and the module say so.
  A `data-` attribute set by each element, or a `gw-*`-minus-an-exclusion-list
  selector, would trade this for a worse failure mode: a document surface
  accidentally counted as chrome kills the shortcut map outright.
- **The inner textarea's `mousetrap` class is unpinned by any test.**
  `gw-textarea` copies its own `class` attribute onto the `<textarea>` it builds
  (`defineCustomTextarea`'s `connectedCallback`), and that copy is what makes
  clause 1 apply to the node a keystroke actually lands on. `tests/textarea.test.ts`
  sets the class on the wrapper but never asserts the copy, and this ticket's test
  builds the resulting textarea as a fixture rather than defining `gw-textarea` a
  second time (the registry is shared across test files, so a second `define`
  throws). Worth one assertion in `textarea.test.ts` next time it is opened.
- **Not covered by a test, and why.** (1) The one line that installs the rule
  (`Mousetrap.prototype.stopCallback` in `doc.js`): nothing in `doc.js` is
  importable — it boots the app at module load — so it is verified by inspection
  and by reading it back out of the built bundle. Mousetrap's global instance is
  `Mousetrap(document)` created in `Mousetrap.init()`, which has no own
  `stopCallback`, so the prototype is the documented hook and the only instance
  this app makes resolves to it. (2) What the browser does with a keystroke the
  app declined: that Tab then moves the focus, that an unhandled arrow scrolls,
  that a chord's `return false` is what cancels the browser's own shortcut.
  jsdom implements no default actions — tickets 33 and 34's standing — so the
  tests read the decision and the platform's rule is written out beside it.
  (3) `isContentEditable`, kept from Mousetrap's default: jsdom does not
  implement the property, and nothing in this app is contenteditable, so it is
  fidelity rather than behaviour. (4) Shadow-root retargeting is deliberately
  *not* reproduced (nothing here attaches one) and so has nothing to test.
