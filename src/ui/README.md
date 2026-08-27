# The interface layer

Surfaces are moving out of Elm one at a time. Each becomes a **custom element**:

```
Elm                                  TS (this directory)
────────────────────────────────     ──────────────────────────────
node "gw-help-modal"                 class HelpModal extends HTMLElement
  [ attribute "platform" "mac"   ──▶   connectedCallback() { … }
  , on "gw-close" (…ModalClosed) ◀──   emit(this, "gw-close")
  ] []
```

Elm decides **when** a surface is on screen and what state it carries in.
This directory owns **what it looks like** and reports back with a bubbling
`CustomEvent`.

## Why attributes and events, not ports

A port boundary needs an encoder in Elm and a decoder in TS for every message —
about a hundred of them if the whole interface moved. Attributes and events are
the web platform's own boundary and need neither, and a surface can be moved (or
moved back) without touching anything else. There was already one instance of
this pattern in the codebase before the split started: `gw-textarea`, in
`src/shared/doc-helpers.js`.

## What has moved

| Element | Replaced | Lines |
| --- | --- | --- |
| `gw-help-modal` | `Doc/HelpScreen.elm` | 174 |

Still in Elm: the card tree, the header and sidebar, the document list, and the
remaining modals (switcher, word count, template selector).

## Rules

- **Class names must match `src/static/style.css`.** These surfaces reuse the
  existing stylesheet; a renamed class silently loses its styling.
- **Events must bubble.** Elm attaches its listener on the custom element, so a
  non-bubbling event never reaches it. `emit()` in `dom.ts` sets this.
- **Clean up in `disconnectedCallback`.** Elm removes the element from the DOM
  when the modal closes; anything bound to `window` or `document` outlives it
  otherwise.
- **No framework.** These surfaces render once when opened and are discarded
  when closed, so there is nothing for a virtual DOM to diff. `dom.ts` is three
  functions and that is enough.

## Checking it

```sh
../../../server/node_modules/.bin/tsc -p tsconfig.json   # strict, no emit
```

`moduleResolution` is `node` rather than `bundler` because the pinned compiler
is TypeScript 4.9. This matters: an unsupported value is not a hard error, it
silently degrades cross-module imports to `any`. If you change it, verify the
checking is still real by introducing a deliberate type error across a module
boundary and confirming `tsc` catches it.

The typecheck runs as part of the build gate, and `verify/smoke.mjs` asserts on
rendered output rather than implementation, so it verifies a moved surface still
behaves the same.
