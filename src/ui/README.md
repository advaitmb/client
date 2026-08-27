# The interface layer

Surfaces move out of Elm one at a time. Each becomes a **custom element**:

```
Elm                                  TS (this directory)
────────────────────────────────     ──────────────────────────────
node "gw-help-modal"                 class HelpModal extends HTMLElement
  [ attribute "platform" "mac"   ──▶   connectedCallback() { … }
  , on "gw-close" (…ModalClosed) ◀──   emit(this, "gw-close")
  ] []
```

Elm decides **when** a surface is on screen and what state it carries in. This
directory owns **what it looks like** and reports back with a bubbling
`CustomEvent`.

**`index.ts`'s header is the list of what has moved**, kept beside the imports
that register the elements so it cannot drift far from them. This file is the
boundary and the rules; it deliberately does not keep a second copy of that
list, because the copy that used to be here named one element out of nine for
months (CODE_REVIEW.md S11).

Still in Elm, and rendering their own DOM: the fullscreen editor
(`Doc/Fullscreen.elm`), the shortcut tray, breadcrumbs, search field and
loading spinners (`Doc/UI.elm`), the modals and banners `Page/App.elm` renders
directly (the sidebar context menu, the delete and confirm-email prompts,
toasts), the export dialog (`Page/Doc/Export.elm`) and the auth pages.

`gw-textarea` — the editing textarea — is the pattern's precedent: it was
already a custom element before this directory existed, and it stays in
`src/shared/doc-helpers.js` beside the port layer's drag, paste and
click-outside handling.

## Why attributes and events, not ports

A port boundary needs an encoder in Elm and a decoder in TS for every message —
about a hundred of them if the whole interface moved. Attributes and events are
the web platform's own boundary and need neither, and a surface can be moved (or
moved back) without touching anything else.

## Two kinds of surface

The difference decides what a rule below means, so it is worth naming.

**Built once** — `gw-help-modal`, `gw-wordcount-modal`, `gw-template-modal`.
They declare no `observedAttributes`: Elm makes the element when the surface
opens and drops it when it closes, so `connectedCallback` builds everything and
nothing reconciles.

**Updated in place** — `gw-tree`, `gw-header`, `gw-sidebar`,
`gw-save-indicator`, `gw-markdown`, `gw-switcher-modal`. Elm keeps handing these
new attributes for as long as they are on screen, so what a re-render
*preserves* is part of their contract: `gw-tree` reconciles its columns and
cards against the incoming tree rather than replacing them, `gw-header` keeps
the title span and refocuses the control the user was on by id, and `gw-sidebar`
re-renders only the document rows unless the whole rail changed.

`dom.ts` is three functions for both kinds. That is enough because the state
lives in Elm: an element is handed the answer, not the inputs to compute one.

## Rules

- **Class names and ids must match `src/static/style.css`.** These surfaces
  reuse the existing stylesheet; a renamed class silently loses its styling.
- **Events must bubble.** Elm attaches its listener on the custom element, so a
  non-bubbling event never reaches it. `emit()` in `dom.ts` sets this.
- **`attributeChangedCallback` must check that the element was built.** It
  fires while the element is being upgraded, before `connectedCallback` has run:
  `if (!this.isConnected) return`, or a null check on whatever the build
  produced (`gw-switcher-modal` guards on its list).
- **Clean up in `disconnectedCallback`.** Anything bound to `window` or
  `document` outlives the element otherwise — and so does in-element state: a
  `<gw-tree>` taken off the page mid-drag used to come back believing a card was
  still in flight (S13).
- **Text inputs are uncontrolled.** The title, the sidebar filter and the
  switcher search all report what was typed and are never written back to while
  they have focus. Elm re-renders on every save-status tick, so a controlled
  input loses the caret — or the word.
- **Anything that reports a click is a real control** — S12's standard, on this
  side of the boundary. A `div` with `onclick` cannot be tabbed to and does not
  activate on Enter, so the surface is mouse-only however it looks: the header's
  three menu icons were `div`s, which put the theme picker *inside* them out of
  a keyboard user's reach entirely (ticket 33). Use `<button type="button">`,
  give an icon-only one an `aria-label` (there is no text to fall back on), and
  take the UA chrome off in `style.css` — `appearance`, `background`, `border`,
  `color`, `font`, `text-align`. `color` is the one that shows: `dom.ts` strokes
  its icons with `currentColor`, so a button's own colour repaints the glyph.
  Leave the focus ring: it is how a keyboard user knows where they are.
- **A set of mutually exclusive options is a radio group, and owes the arrow
  keys.** `role="radiogroup"` with a name, `role="radio"` and `aria-checked` on
  each option, **one** tab stop — the option in effect, `tabindex="-1"` on the
  rest — and the four arrow keys moving through them with the choice following
  the focus. The export menu's two rows are the case (ticket 34); `aria-pressed`
  buttons, as in the theme picker, describe *independent* toggles and give one
  tab stop each. Not `<input type="radio">`, which brings all of that for free
  but owns its own checked state, and every mark on this side of the boundary is
  Elm's answer rather than the click's.
- **A `keydown` an element handles must not also reach the app.** Mousetrap
  binds the shortcuts on `document` and ignores only form fields, so Enter on a
  menu button opens the active card's editor as well as choosing the entry — and
  an arrow key in a radio group moves the card cursor behind the open menu.
  `stopPropagation` on the keys you handle, and only those — Escape has to get
  through.
- **Loading states render but wire nothing.** The `static` attribute is the
  convention (`gw-sidebar`): draw the surface, attach no handlers.
- **DOM tests share one document.** `bunfig.toml` preloads `tests/dom.ts`, and
  bun shares that jsdom — and its `customElements` registry — across test
  files. A fixture must not name its nodes after real elements; `<gw-tree>`'s
  `connectedCallback` will replace their children with its own scaffolding, and
  the failure looks environmental. `tests/dom.ts` records this.

## Checking it

```sh
bun run typecheck   # tsc -p src/ui/tsconfig.json: strict, no emit
bun test            # the whole TS suite; these elements run against jsdom
bun run newbuild    # esbuild bundles this directory into web/ui.js
```

The typecheck is a step in `.github/workflows/ci.yml`, and it is the only thing
in the pipeline that reads a type annotation: `bun test` and esbuild both strip
types without checking them. It caught nothing for a long time because it did
not exist — this file claimed it, pointing at a `tsc` in a sibling checkout,
while `typescript` was not even a dependency (S11). Ticket 22 made it real;
ticket 17 found what it costs to go without, a field shadowing
`HTMLElement.prototype.title` that no test could see.

`moduleResolution` is `bundler`, because esbuild is what builds this directory.
If you change it, verify the checking is still real the way that change was
verified: introduce a deliberate type error **across a module boundary** and
confirm `tsc` catches it. An unsupported or mismatched value is not an error —
it silently degrades cross-module imports to `any`, and a gate that checks
nothing is worse than no gate, because the README says there is one.
