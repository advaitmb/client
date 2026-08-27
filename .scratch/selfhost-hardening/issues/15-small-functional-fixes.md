# 15: Small functional fixes (collab phantom, fullscreen Esc, wordcount, OPML, tray strings)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E5, E6, E11, E13, E14.

**What to build:** Five small, independent behavior fixes bundled to fit one
session:

- E5 — a blocked document no longer broadcasts phantom "editing" collab state
  (guard ordering matches the correct `insert` pattern).
- E6 — Esc-from-fullscreen works: add the missing `FullscreenChanged` decoder
  branch so Elm learns the browser left fullscreen.
- E11 — the word-count modal's "Session" row reports words since the session
  started (record a session-start count) instead of always equaling Total.
- E13 — Leaves/Column exports in OPML format produce valid OPML (or the
  format option is removed for those selections — implementer's call, note it);
  the saved file's MIME type is a single valid string.
- E14 — the edit-mode shortcut tray renders real strings instead of literal
  "AltKey ParenNumber SetHeadingLevel" (mirror the TS help-modal fix).

**Added scope (from ticket 07's resolution):** `gw-textarea`'s
`observedAttributes` omits `disabled`, so its `attributeChangedCallback`
branch for it is dead — reachable via fullscreen's `editingByCollab`. Fix
alongside E5/E6.

## Acceptance criteria

- [x] Each fix has a test where a seam exists (E11/E13 via Elm tests; E6
      decoder test; E14 by translation-table assertion; the `observedAttributes`
      fix at seam 3). **E5 has none** — the only difference a blocked document
      makes there is a `Cmd`, and elm-test cannot inspect one; see the Answer.
- [x] CI green.

## Answer

Six fixes, one commit each, all on `selfhost`:

| finding | commit | what changed |
|---|---|---|
| E14 | `02e8a21` | `Translation.elm`: `AltKey` → "Alt", `ParenNumber` → "(1-6)", `SetHeadingLevel` → "to Set Title Level" |
| E13 | `068056d` | `Page/Doc/Export.elm`: leaves/column exports go through `stringFn`; `toMimeType` replaces the MIME literals |
| E6 | `5b4825e` | `Page/Doc/Incoming.elm`: `fromOutside` extracted + `FullscreenChanged` branch; `Page/Doc.elm` exits fullscreen editing on it |
| E11 | `2b771c8` | `Page/Doc.elm` records a session-start wordcount; `Doc/UI.elm` gains `documentWordcount`; `Page/App.elm` passes it to the modal |
| E5 | `f458f32` | `Page/Doc.elm`: `preventIfBlocked` moved last in `changeMode`'s two guarded branches |
| added (07) | `dce2eb7` | `doc-helpers.js`: `observedAttributes` watches `disabled` |

**E5** — `changeMode`'s `(Normal, Editing)` and `(Editing, Editing)` branches
ran the guard and *then* appended the broadcast with `andThen`, so a blocked
document (history view, public document) reverted the model, alerted, and still
sent `SendCollabState (CollabEditing …)`. Collaborators saw an editor on a card
nobody was editing — and the fullscreen view disables its textarea on exactly
that signal, so the phantom took the card away from whoever *was* holding it.
The guard now comes last in both, the order `insert` already used:
`preventIfBlocked` replaces the whole triple, so nothing after it can leak a
command past it.

*No test.* The blocked and unblocked paths differ only in the `Cmd` they answer
with — `preventIfBlocked` reverts the model either way — and elm-test cannot
inspect a `Cmd` (the reason ADR-0001 seams 8 and 9 exist). The two ways to earn
one were both worse than the fix: exporting a test-only predicate that restates
the branch, or hoisting all nine branches' collab decision into a pure function
— a rewrite of `changeMode` for a one-line ordering fix, and one that could not
preserve today's behavior without encoding "these two branches only" anyway
(see Comments). Verified by inspection, and ADR-0001 seam 10 now records
"whether a port command is sent at all" as out of reach.

**E6** — `doc.js:407` sends `FullscreenChanged` on every `screenfull` change;
`Incoming.elm` had no branch, so it reached `onError` and was logged. Elm never
learned the browser had left fullscreen, and the fullscreen editor stayed on
screen over a window that was no longer fullscreen. `FullscreenChanged False`
now lands where the exit button lands (`ExitFullscreenRequested`): `changeMode`
to `Editing` on the same card, `instant = True`, `save = True`, so the
fullscreen field is saved and the normal editor is focused. Entering fullscreen
stays a no-op — the app's own fullscreen editing is what puts the browser
there, and a user's F11 is not a request to open an editor.

To test the *tag mapping* (the half that was actually missing) the mapping had
to leave `subscribe`, whose `Sub msg` cannot be run:
`fromOutside : OutsideData -> Result String Msg` is now the whole decision, and
`subscribe` only applies `tagger`/`onError` to its answer. The 19-branch move
was verified mechanically — the tag list and the produced constructors are
identical before and after, plus the one new tag.

**E11** — the modal's "Session" row is `documentWords - startingWordcount` and
`Page.App` passed the literal `0`, so it was a second copy of "Total". A session
now starts where a document's content first arrives, which is what `Page.Doc`
learns first: `setWorkingTree`, `setTree` and `publicTreeLoaded` fill
`startingWordcount : Maybe Int` through `recordSessionStart`, which only ever
fills a count that is missing — every later tree (a sync push, the user's own
edits, a restored version, a selected conflict side) leaves it alone. A document
being created starts at `Just 0` from `init`: every word in it is this session's,
and its first tree only reaches the model after the first save. `Page.App.init`
builds a fresh `Page.Doc` per opened document, so each document gets its own
session start. The count itself is `Doc.UI.documentWordcount`, beside the
`getStats` that reports it as the modal's total; a test pins the two to the same
number, since they are separate implementations (`countWords` vs `count`).

**E13 — the call: keep the option, make it produce real OPML.** Removing OPML
for two of four selections would have meant a format menu whose entries come and
go with the selection, for a format that had no reason to fail: a flat selection
of cards *is* a tree of depth one, which is all `treeToOPML` needs. So both
selections now build that tree and go through the same `stringFn` as
"everything" and "subtree". JSON and Markdown are unchanged by construction —
JSON already built exactly this tree, and a childless card renders as its own
content, so `treeToMarkdownString False` reproduces the old join (pinned by
tests). Only OPML changes: it gets the XML declaration, `<opml version="2.0">`,
a head with the document name, and one `<outline>` per card, wrapped in the
same empty-text root outline an "everything" OPML export has always had.

The MIME string `"application/xml, text/xml, text/x-opml"` was a list of types
a client might *accept*, not a type a file can *have*. `toMimeType` answers it
once, beside `toExtension`: **`text/x-opml`** for OPML — the OPML-specific type
of the three, and the file is named `.opml` regardless, so nothing depends on
the choice beyond being a single valid `type/subtype`. `Page.App`'s DOCX
download reads its type from there too, rather than repeating the literal.

**E14** — three placeholder entries rendered their own constructor names, so the
edit-mode tray's Formatting row read "AltKey ParenNumber SetHeadingLevel".
Wording follows the tray's own conventions rather than the TS help modal's
sentence: keys are bare labels ("Enter", "(arrows)") and actions start with a
preposition ("to Move", "for Bold"), so the row now reads
`Alt` `(1-6)` `to Set Title Level`. Two deliberate divergences from
`help-modal.ts`, both cosmetic: it renders Alt as `⌥` on macOS (the tray has no
platform-aware `TranslationId`, and Apple keyboards are labelled "alt"), and its
description carries "(# to #####)" — five hashes for six levels, which is not
worth copying into a second place, especially with the `FormattingTitle`
example ("# Title / ## Subtitle") rendered directly below the row.

**Added scope (07)** — `observedAttributes` returned only `['start-value']`, so
`attributeChangedCallback`'s `disabled` branch was dead: `disabled` set *after*
the element was created never reached the inner textarea. The fullscreen view
sets it while the element is on screen (a collaborator opens the card) and
clears it when they leave, so both directions were lost; only a card already
taken when it was first drawn came up disabled, from `connectedCallback`.

**Tests** — 34 new Elm tests + 3 TS: `tests/IncomingTest.elm` (7),
`tests/ExportTest.elm` (14), `tests/WordcountTest.elm` (9),
`tests/TranslationTest.elm` (4), `tests/textarea.test.ts` (+3). All red first:
E14's four failed on the constructor names; E13's four on OPML-of-leaves being
Markdown ("no XML declaration: Aardvark\n\nBeetle's first\n\nCricket") and two
on the comma'd MIME; E6's two on `Err "Unexpected info from outside:
FullscreenChanged"`; E11's five with Session equal to Total (12, not 4); the
`disabled` one on a textarea that stayed enabled.

Mutation-checked, each reverted after:

| mutation | caught by |
|---|---|
| `recordSessionStart` always overwrites | session start moves when more is written; a new document's start stops being 0 (3 tests) |
| `disabled` branch drops its `removeAttribute` half | "a collaborator leaving a card gives its textarea back" |

ADR-0001 gains **seam 10** (what the document's chrome says and writes, Elm,
pure), covering `Incoming.fromOutside`, `Export.toString`/`toMimeType`,
`documentWordcount` + `getStartingWordcount`, and `Translation.tr` — and
recording that whether a port command is sent at all is out of reach there.

**Verification** — `bun run test:elm` 133/133, `bun test` 88/88,
`bun run newbuild` exit 0, `bun run config-check` exit 0, all on the rebased
tree carrying tickets 16, 28 and 30 (which is where those totals come from:
this ticket's own share is the 37 above).

## Comments

- **`changeMode`'s `FullscreenEditing` targets ignore `block` entirely** — an
  adjacent hole E5 does not cover and this ticket did not widen scope to close.
  `( Normal _, FullscreenEditing _ )` has no `preventIfBlocked` at all, and
  `"shift+enter"` reaches it directly, so on a blocked document (history view,
  a public document) shift+enter *does* open a fullscreen editor — and
  broadcasts `CollabEditing` while it does. Closing it is a behavior change
  (three more branches guarded), not a reordering, so it belongs with 24
  (`Page.Doc` consistency). Note that E5's phantom-broadcast bug is still fully
  fixed for the two branches the finding names.
- **Two changes past the literal scope, both in service of a required test**,
  disclosed rather than folded in: `fromOutside` (E6's tag mapping had no
  testable seam inside `subscribe`) and `toMimeType` (E13's "single valid MIME
  string" had none inside `command`, which answers in a `Cmd`; making it total
  also let `Page.App`'s duplicate DOCX literal go). `Doc.UI.documentWordcount`
  is E11's own seam, not an extra.
- **The alternative E5 fix, and why not.** Hoisting the collab decision out of
  all nine `changeMode` branches into a pure
  `(block, instant, from, to) -> Maybe CollabStateMode` would have made E5
  testable, but it could not preserve today's behavior without encoding "only
  the two branches that carry the guard": `( FullscreenEditing _, Editing _ )`
  broadcasts *and* transitions while blocked today, because it has no guard, so
  a uniform "blocked ⇒ no editing broadcast" rule would have changed a third
  branch's behavior under the banner of a one-line fix. The bug above is the
  honest way to record that, and the ordering fix stands on its own.
- **`Outgoing.RequestFullscreen` is dead** and `doc.js`'s handler for it with
  it: nothing in Elm ever sends the tag, so the browser is only ever put into
  fullscreen by the user. E6's fix is what makes the *return* trip work
  regardless of who started it, but the app's "fullscreen editing" is its own
  layout, not the Fullscreen API. Dead-code sweep, ticket 21/22.
- **Local harness note, no repo change:** in this sandbox `elm-test`
  re-solves its generated `elm.json` and picks `danfishgold/base64-bytes` 1.1.0
  where `elm.json` pins 1.0.3, and GitHub zipball fetches are blocked for
  un-attached repos, so the local run needed the cached solve in
  `elm-stuff/generated-code/…/dependencies.<hash>.json` pinned back to 1.0.3
  (that path is gitignored). CI has network and is unaffected — its
  `elm-home/elm-stuff` cache key is `hashFiles('elm.json')`, which this ticket
  does not touch.
