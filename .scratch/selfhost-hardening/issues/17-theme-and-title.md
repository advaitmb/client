# 17: Theme restores on load; title input survives the clock tick

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E10, E12.

**What to build:** Two persistence/render fixes: the per-document theme
setting, which is saved on change, is actually read back and applied when the
document loads (E10); and typing in the header's title input is never
discarded by the 9-second clock tick re-render — today only the `doc-title`
attribute is guarded, but the `save` attribute tick rebuilds the input anyway
(E12).

## Acceptance criteria

- [x] Saved theme round-trips: set → reload path → same theme active (test
      the decode/apply seam).
- [x] With the title input focused and text typed, an unrelated attribute
      change re-render preserves the in-progress value (seam 3 test).
- [x] CI green.

## Answer

Both findings were a value crossing a boundary and being replaced by a
constant on the way back — the theme by `Default`, the title by the last
committed name — and in both cases the fix is that the *reader* stops
inventing an answer.

| finding | commit | what changed |
|---|---|---|
| E10 | `cacae73` | `Page/Doc/Theme.elm` gains `fromLocalStore`; `Page/App.cardDataReceived` applies it |
| E12 | `fc8348c` | `src/ui/header.ts`: the title span is built once and kept, not rebuilt |

**E10 — the theme is read back where `last-actives` is.** A document load
attaches the document's localStore blob to its card rows
(`loadCardBasedDocument`: `loadedCards.localStore = store`), which is the ride
`last-actives` already takes into `Page.App.cardDataReceived`, so the theme
needed no new port message and no new plumbing — only a reader. The decision is
`Theme.fromLocalStore : Theme -> Dec.Value -> Theme`, *the theme a card-data
message names, or the one already in effect*, because `cardDataReceived` itself
needs a `Nav.Key` no test can make (the reason seams 5, 7–10 exist). Carrying
the current theme as the fallback is what makes it total: the message that
carries a setting is the **first** one of a document load, and every liveQuery
echo after it is card rows alone, so "no `localStore` here" has to mean "leave
the theme alone" rather than "reset to `Default`".

It is applied in both limbs of `cardDataReceived`, including the one where
`Doc.Data` reports nothing changed: whether the *rows* moved is a separate
question from what the document's settings say. Per-document semantics come
free — every URL change re-runs `Page.App.init` (ticket 14's `routeUrl`), so
each document starts at `Default` and then applies its own stored theme rather
than inheriting the previous document's.

`decoder` is no longer exposed. `fromLocalStore` is the module's read surface,
and it uses the decoder unchanged (an unknown theme name is still `Default`) —
an exported decoder with no importers is exactly how E10 stayed invisible.

**E12 — the input is not rebuilt at all any more.** The `doc-title` guard could
not be extended attribute by attribute: `save` ticks every 9 seconds, and
`menu`, `export-settings` and `history` rebuilt the field too (a test pins the
`menu` one). So `render()` now keeps the `#title` span and replaces only what
comes after it, and `renderTitle()` writes the field's value **only while it
does not have focus** — one rule, independent of which attribute changed. The
save indicator, which lives inside that span, is swapped in place, so the rest
of the header still updates around a title being typed (also pinned).

Keeping the node rather than re-seeding a new one is what makes the rule
complete. `replaceChildren()` detaches even a node that goes straight back, and
a detached input loses its focus, its caret, its selection, the browser's undo
stack and any IME composition — the old code hand-restored two of those six.
It also ends the tick's self-inflicted `gw-title-focus`: `render()` used to
`focus()` the rebuilt input, and Elm answers a title focus with
`SelectAll "title-rename"`, so a field that was focused but not yet typed into
had its text selected every nine seconds, and the next keystroke replaced the
whole title. That was the same bug's tail, and it is gone because nothing
re-focuses anything.

The four nullable fields the reused nodes would have needed are one
`TitleParts` record. Naming that field `title` was a trap worth recording: it
shadows `HTMLElement.prototype.title`, so under assignment class-field
semantics (esbuild's default below ES2022, and this repo pins no
`tsconfig.json`) `this.title = null` would have written the *tooltip attribute*
and read back the string `"null"`. An ad-hoc `tsc --strict` run is what caught
it; the tests could not.

**Tests: 25 new** — 15 in `tests/ThemeTest.elm` (seam 10: the round trip
through the exact value `SaveThemeSetting` stores, for all six themes; the
three messages that must change nothing; and the class `applyTheme` puts on the
document root, checked positively and against the other five) and 10 in
`tests/header.test.ts` (seam 3). Suites: `bun run test:elm` 154, `bun test` 108
(13 files). Red first: 6 of the Elm tests against a reader pointed at the wrong
key, and 6 of the 10 header tests against today's code. ADR-0001 seam 10 and
CONTEXT.md's seam list name `fromLocalStore`.

## Comments

- **Red-before-green transcript.** E10: `NAMING ERROR — The Theme module does
  not expose a fromLocalStore variable`, then (with the reader pointed at
  `localStoreXX`, i.e. exactly "nothing reads it back") 6 failures —
  `Classic`/`Gray`/`Green`/`Turquoise`/`Dark` each `Default` instead of
  themselves, plus the unknown-name case. `Default` and the three
  leave-it-alone cases pass under the mutation, which is the point of having
  them. E12: `Expected: "My new title" / Received: "Untitled"` on the `save`
  tick, on the `menu` change, on the sizing shadow and beside the save
  indicator, plus `Received: ["gw-title-focus"]` where nothing should have been
  reported.
- **E10's write half has no producer, and that is not this ticket's to fix.**
  `ThemeChanged` is constructed nowhere: the theme picker was removed one day
  before this ticket, in `a203a9c` ("Move the document header to the interface
  layer" — *"Self-host: theme picker removed; the default theme still applies
  via Page.App's applyTheme"*). So the value this now restores can only come
  from a store an **older build** wrote, and `SaveThemeSetting` /
  `Theme.toValue` / `ThemeChanged` are unreachable until a picker returns. All
  six themes' CSS is still in `style.css`. The round trip is therefore correct
  and tested end to end at the seam, but not user-reachable today, and the
  choice — restore a picker (the header's settings menu is the natural home,
  beside "Word count...") or remove the write ring — is an owner call that
  belongs with tickets 21/22's dead-code purge. Adding a picker here would have
  reversed a deliberate UI removal under a two-finding ticket.
- **Not covered by a test, and why.** (1) `Page.App.cardDataReceived`'s three
  lines of wiring — `Nav.Key`, per seam 10. (2) That `doc.js` attaches the
  blob at all: `loadCardBasedDocument` is `doc.js` proper, which boots the app
  at module load and is not importable (the reason seam 4 exists as
  extractions); nothing was extracted here because nothing changed on the JS
  side. Verified by reading, and by the fact that `last-actives` — the same
  ride, the same message — demonstrably works. (3) The browser-level flow for
  both findings needs a running companion server and was not exercised.
- **One JS detail confirmed rather than assumed.** The card-data message is a
  JS *array* of rows with a `localStore` property hung off it, which Elm's
  `Json.Decode.field` reads fine (`typeof [] === "object"` and `field in
  value`; kernel `_Json_runHelp`'s `__1_FIELD` branch). `ThemeTest` builds a
  plain object stand-in and says so.
- **What jsdom does and does not show.** Removing a focused input fires no
  `blur` in jsdom, so the old code's rebuild did not commit the title in the
  tests. Browsers differ here, and a `blur` on removal would have meant
  `gw-title-commit` → `TitleEdited` renaming the document from half-typed text
  every nine seconds. The fix removes the dependence on that behaviour rather
  than relying on it.
- **Adjacent, left alone.** (1) `src/ui/README.md` still says these surfaces
  "render once when opened and are discarded when closed" and points its
  typecheck at `../../../server/node_modules/.bin/tsc -p tsconfig.json` — there
  is no `tsconfig.json` in this repo and no typecheck in `ci.yml`, and the
  `HTMLElement.prototype.title` shadowing above is exactly the class of bug
  that gate would catch. Worth a ticket. (2) `localStore.set` has no
  `isReady()` guard, unlike `doc-helpers`' `last-actives` write, so a
  `SaveThemeSetting` with no document open would write to the key
  `"gingko-local-store/undefined/settings"` (unreachable today, see above).
  (3) `localStore.get(key, fallback)` throws on a store that was never written
  (`JSON.parse(null)[key]`) and has no callers — ticket 22/23 territory.
  (4) `TitleEditCanceled` blurs the field, and the blur handler reports
  `gw-title-commit`, so Escape reaches Elm as cancel *and then* commit; it is
  harmless because cancel resets `titleField` to the committed name first, and
  it predates this ticket.
- **Verified:** `bun run test:elm` 154/154, `bun test` 108/108,
  `bun run newbuild` clean, `bun run config-check` exit 0, and CI run
  33089037362 green on `selfhost` for `fc8348c` (the head carrying both fixes).
