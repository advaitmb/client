# 07: Editing textarea survives re-parenting (silent edit loss)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D4.

**What to build:** Typing into a card keeps working after the tree re-renders
around it (second tab writes, collaborator edit, checkbox toggle while
editing). Today `gw-textarea` loses its event listeners permanently when the
tree element re-parents it mid-edit, so subsequent keystrokes silently stop
reaching Elm and the next save writes stale content.

## Acceptance criteria

- [x] Failing test first (seam 3): create the element, simulate
      disconnect + reconnect (as re-parenting does), dispatch input — the
      keystroke/cursor events still fire.
- [x] `connectedCallback`/`disconnectedCallback` are symmetric (re-bind on
      reconnect, or bind listeners in a way re-parenting can't break).
- [x] CI green.

## Answer

Landed in commit `f1544ff` on `selfhost`.

**Root cause, confirmed.** `gw-textarea` added its four listeners
(`input`, `keyup`, `click`, `focus`, all on the inner `textarea`) in the
constructor; `disconnectedCallback` removed them and `connectedCallback`
never put them back. `tree.ts:renderTree` rebuilds the column/group
scaffolding on every `tree` attribute change and moves the *reused* editing
card element into it (`cardElement` returns `existing` when the editing flag
is unchanged), so a tree change arriving mid-edit fires
disconnect + connect on the element inside. Verified in happy-dom: both
re-parent shapes (into a detached parent that is then attached, and directly
into an already-attached parent) produce a paired
`disconnectedCallback` → `connectedCallback`.

A second half of the same bug surfaced while testing: `connectedCallback`
also did `textarea_.value = getAttribute('start-value')` unconditionally, so
even with the listeners restored a re-parent reverted the visible text to the
content the edit started from — and the following keystroke then reported
that reverted text to Elm as `FieldChanged`.

**What changed** (`src/shared/doc-helpers.js`, `defineCustomTextarea` only):

- Listener setup/teardown moved into `_bindListeners()` / `_unbindListeners()`,
  called from `connectedCallback` / `disconnectedCallback`. The bound
  references still come from the constructor (`.bind()` returns a new function
  each call, so stable refs are what make removal work at all — the earlier
  leak fix).
- Both are idempotent via `_listenersBound`, so a connect with no intervening
  disconnect cannot register a second copy and report one keystroke twice.
- The document-level `click` → `ClickedOutsideCard` handler moved into the same
  pair, and whether it was added is now recorded per instance
  (`_docListenerBound`) instead of being re-derived from `isFullscreen` at
  teardown. The fullscreen view renders one `gw-textarea` per card
  (`Doc/Fullscreen.elm:156`), so an instance removing a handler it never added
  could strip click-outside from whichever card is actually being edited.
- `connectedCallback` seeds the textarea from `start-value` on the **first**
  connect only (`_startValueApplied`), so a re-parent no longer discards
  in-flight text. Authoritative updates still land: `attributeChangedCallback`
  applies a changed `start-value` when the textarea is not focused, and
  `doc.js`'s `SetField` writes the value by id.

**Tests** — `tests/textarea.test.ts`, 7 tests at ADR-0001 seam 3 (attributes
in, rendered DOM and `toElm` port calls out; nothing reaches into private
fields). The fixtures rebuild the DOM `tree.ts` actually produces
(`div#document > div.column > div.group > div.card.active.editing >
gw-textarea`) and `reparent()` performs the same move `renderTree` does.

Red before the fix (verified by stashing only the source change): keystrokes
after re-parent, cursor moves after re-parent, no-double-report, and
in-flight text not reverted → **4 fail / 3 pass**. Green after → **7 pass**.

Mutation-checked for sensitivity, each reverted afterwards:

| mutation | caught by |
|---|---|
| re-bind with fresh `.bind()` closures and never unbind | no-double-report (3 reports per keystroke) |
| never call `_unbindListeners` | a removed card stops reporting |
| don't re-add the document listener on reconnect | click-outside after re-parent, no-double-report |

**Verification** (local, on the rebased tree that also carries ticket 03):
`bun test` 14/14 (7 pre-existing + 7 new), `bun run test:elm` 7/7,
`bun run newbuild` exit 0, `bun run config-check` exit 0. CI green on the
fix commit: <https://github.com/advaitmb/client/actions/runs/33064085053>.

## Comments

- **Two changes beyond the literal acceptance criteria**, both in service of
  the ticket body's "the next save writes stale content", both disclosed
  rather than folded in silently: `_startValueApplied` (in-flight text is not
  reverted on reconnect) and `_docListenerBound` (per-instance record of the
  document listener). Without the first, the listener fix alone still loses
  the edit — the text reverts and the next keystroke reports the reverted
  value. Nothing else in `doc-helpers.js` was touched.
- `_listenersBound` guards a double-bind that re-parenting cannot actually
  reach, since DOM insertion always pairs a remove with the insert. It is kept
  because it makes the pair idempotent by construction, which is what the
  no-double-report test pins; the mutation table above shows the test earns
  its place against the realistic version of that mistake.
- **Adjacent defects left for their own tickets:**
  - `observedAttributes` returns only `['start-value']`, so
    `attributeChangedCallback`'s `disabled` branch is dead — a `disabled`
    attribute set after creation never reaches the inner textarea. Reachable
    from `Doc/Fullscreen.elm`'s `editingByCollab` path. Fits 15/23.
  - `editBlurHandler` is one module-level function shared by every instance,
    so add/remove is global. Safe only because at most one non-fullscreen
    editor exists at a time; the per-instance flag added here keeps a
    fullscreen instance from interfering, but two simultaneous non-fullscreen
    editors would still fight over it. Fits 23.
  - A re-parent still cancels a pending fullscreen autosave
    (`autoSave.cancel()` in `disconnectedCallback`); the next keystroke
    re-arms it, so no edit is lost. Left alone.
- happy-dom drove the whole contract (custom-element lifecycle on re-parent,
  `focus()`/`document.activeElement`, `setSelectionRange`, event bubbling to
  `document`), so no assertion needed a weaker stand-in.
