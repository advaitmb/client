# 24: Elm-side consistency and correctness smells

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md S1, S2, S3, S4, S10, S12.

**What to build:** The catalogued Elm-side smells are fixed: the duplicated
save-indicator logic is either unified or the TS copy brought to parity
(missing "Database Error…" branch, S1); the `SaveImportedTree` /
`SaveCardBasedTree` cross-boundary name mismatch is reconciled so grep finds
both sides (S2 — coordinate with ticket 08, which touches the same path);
`isOwner`'s loading-time default stops flapping owner-only UI (S3);
`copyNaming` escapes/anchors the document name (S4); the
encoder/decoder asymmetries in Metadata/UpdatedAt round-trip (S10); the
`<img src="" onerror>` message hack and non-keyboard-operable clickable divs
get honest interactive elements (S12).

**Added scope (from ticket 31's resolution):** `mod+j`/`mod+k`/`mod+l`
truncate the open card's field and run `saveCardIfEditing` BEFORE calling
`insert`, so `insert`'s guard treats the already-mutated model as "original"
— on a blocked document the keypress inserts nothing but leaves the card
truncated in the working tree. Unreachable after ticket 31's guards, but the
shape is wrong; fix while collapsing the triplicated save-card logic (S/P4).
Same shape in the `Editing` limbs.

## Acceptance criteria

- [x] Copy-naming tests: regex metacharacters in names, substring names,
      sparse numbering.
- [x] `Metadata.encode |> decoder` round-trips collaborators; `UpdatedAt`
      zero round-trips.
- [x] Remaining items done or justified in Comments.
- [x] CI green.

## Answer

Six commits on `selfhost` (claim: `4df9da1`):

| # | commit | what |
|---|---|---|
| 1 | `9d85bd1` | S4 + S3 — `copyNaming` compares names; `ownership` gains `Unknown` |
| 2 | `cc076d9` | S10 — the metadata and stamp codecs round-trip |
| 3 | `6a2103c` | S1 — one `<gw-save-indicator>`, rendered by both surfaces |
| 4 | `2186eaf` | seam renumber (ticket 18 took 12 mid-flight) |
| 5 | `63843dc` | S2 — one spelling per port tag |
| 6 | `3ef333b` | S12 — the img hack, the buttons, the toast wrapper |
| 7 | `5efafb1` | P4 + the added scope — one `splitCard`, guard over the unmutated model |
| 8 | `3047616` | self-review pass |

**The thread through all seven items: a decision that existed twice, or a
question asked of the wrong thing.** Two save indicators. Two spellings of one
port tag. A "is this name taken?" asked of a regex built from the name. A "who
owns this?" answered `False` when the answer had not arrived. An encoder and its
own decoder disagreeing. A message fired from a broken image. A guard asked
about a model something else had already changed. Each fix removes the second
copy or moves the question to what can answer it.

### S1 — unified, not brought to parity

The ticket allowed either, and asked how a future fix avoids being made twice.
Parity would have left two implementations, so: `src/ui/save-indicator.ts`
defines `<gw-save-indicator>`, and **both** surfaces render it — `header.ts`
inside the title span, `Doc/Fullscreen.elm` via `Doc.UI.viewSaveIndicator`. The
header *forwards* its `save` attribute rather than interpreting it, and Elm
encodes the state in one place, `Doc.UI.encodeSaveState`, which `Page.App` uses
for `<gw-header>` too. So the branch table exists once in TS and the payload
once in Elm, and there is no second copy for a fix to miss.
`Page.App.encodeMaybePosix` went with the inline object it existed for.

The element takes its `#save-indicator` id from its caller (as `<gw-header>`
takes `#document-header`) and owns its class list, so every existing
`#save-indicator.<state>` rule and the `#fullscreen-buttons` overrides still
apply. Both parity gaps are now branches with tests: the "Database Error…" case
(`lastRemoteSave` but no `lastLocalSave` — the server has the document and this
browser's database has no record of saving it) and the initial-load case (a
`lastLocalSave` of epoch 0 with nothing synced is "Loading…", not "Saved
Offline").

One deliberate visual change: the state colours now set `stroke` beside `fill`.
The shared glyphs are the app's own stroked icons (`dom.ts`), where the Elm view
used filled Ant icons — so the CSS's green check and orange warning had been
dead in the header since it moved, and are back in both places.

### S3 — a tri-state, and both callers withhold rather than guess

`Session.isOwner` is now `Session.ownership : LoggedIn -> String -> Ownership`
with `Owner | NotOwner | Unknown`. `Unknown` is "the document list has not
answered", which is the state S3 is about; a list that *has* answered and does
not hold the document is `NotOwner` (someone else's public document, or one just
deleted).

A load-gated default of `True` was rejected: **rename has no other gate.**
`Page.App.TitleEdited` sends `RenameDocument` with no ownership check — the
disabled title field is the only thing stopping it — so guessing "owner" during
the window would hand a non-owner a real rename. So the answer is withheld
instead, and the flap is closed at the two callers:

- `<gw-header>` takes `owner="unknown"` as *inert but not forbidden*: the field
  is disabled (no rename window) while the `not-allowed` cursor is reserved for
  a known `NotOwner`. That cursor is the whole of what the user can see —
  `.title-grow-wrap > input` sets its own colour, background and a transparent
  border, so a disabled field is pixel-identical to an enabled one — and
  showing it and taking it back a moment later *is* the flap.
- The sidebar's Delete is offered only for a known `Owner`. Withholding costs
  nothing there: a context menu opens long after the list has arrived.

The double negative is unavoidable — `treeDocToMetadata` in `doc.js` drops the
`trees` row's `owner` column, so the client only ever learns who the
*collaborators* are — but it is now spelled in steps, with a docstring saying
why it has to be one, instead of `not << List.member` under two `Maybe.map`s.

### S4 — no regex at all

The regex was an approximation of "is this name taken?", and it got the question
wrong three ways at once. `copyNaming` now compares names (`Set` of the names in
the list) and takes the first free `name (n)` from 2. That answers all three
sub-cases by construction: metacharacters are just characters, `"Doc"` is not
`"My Doc"`, and a gap in the numbering is filled rather than collided with.

### S10 — round trips, plus the failure the ticket did not name

`Metadata.encode` now writes `collaborators`, and `decoder` is one decoder with
`collaborators` and `_rev` optional rather than a `oneOf` of two whole decoders.
That `oneOf` was *how* the bug hid: both branches required `_rev` to be present
and the encoder omitted it when there was none, so metadata with no revision
(which is what the port layer sends: `_rev: null`) **did not decode back at
all** — not just without its collaborators. Optional fields degrade one at a
time and say which; the `oneOf` would have swallowed the next field added too.

For `UpdatedAt`, the parser is the half that gave: `"0"` is the wire format,
shared with `src/shared/stamps.js`'s `ZERO_STAMP` and sent as the pull
checkpoint for a document with nothing synced, so changing `toString` would have
broken the JS side. The spelling now lives in one `zeroString` that both
`toString` and `stringParser` read. Side effect worth having: a `"0"` in a
`pushOk` no longer fails `Result.Extra.combine` and drop the whole ack.

### S12 — three controls, three different right answers

- The **`<img src="" onerror>`** and everything it fired are gone: `EmptyMessage`,
  `Outgoing.EmptyMessageShown`, and the `doc.js` handler whose body was `() =>
  {}`. The honest mechanism for a message nobody listens to is not to send it.
  ARCHITECTURE §7's live-tag list loses the tag.
- The **empty-state control** and the **show/hide-password controls** are real
  `<button type="button">`s. The password ones also move *out* of their
  `<label>`, into a `.label-row` that carries the flex box the label was: a
  `<label>` may not contain a labelable element that is not its own control.
- A **breadcrumb** stays a `div`, made keyboard-operable by `Utils.asButton`
  (`role="button"`, `tabindex="0"`, Enter and Space). It is the one that cannot
  be a `<button>`: its label is the card's title *rendered as markdown*, which
  may contain a link. Its keydown `stopPropagation`s — see Comments.
- Also from S12: `viewToastFrame`, whose whole body was `div [] [ viewToast … ]`.

### P4 and the added scope — one fix

The truncate-before-guard shape was a symptom of the logic living in six places.
One `splitCard` now takes all six limbs (which insert to use, which side of the
cursor the new card gets), and the guard runs **last, over `model` as the
keystroke found it** — so a refused split leaves the card whole. Nesting is
harmless: the inner `insert` guard's alert is discarded with the triple it
replaces, so a blocked split still alerts exactly once.

That also removes the two idioms for one operation: `mod+j` passed the kept half
to `saveCard`, while `mod+k`/`mod+l` wrote it into the **view mode** first so
`saveCardIfEditing` would find it there — mutating state to pass an argument.
Underneath, `stageCardText` is the single place a card's text is written into the
working tree and staged; `saveCard` and both editing limbs of
`saveCardIfEditing` were three copies of it.

### Tests

**45 new** — 34 elm-test and 11 `bun test`. Suites: `bun run test:elm` 154 → 199
(this ticket's own 34, no other Elm tests landed alongside); `bun test` 108 → 154
on the tree this ticket was written against, and 201 across 22 files once
tickets 18 and 23 rebased in under it.

| file | n | seam | red first |
|---|---|---|---|
| `tests/SessionTest.elm` (`copyNaming`, `ownership`) | 14 | 13 (new) | 4 |
| `tests/CodecTest.elm` (new) | 11 | 13 (new) | 5 |
| `tests/save-indicator.test.ts` (new) | 9 | 3 | n/a — new element |
| `tests/header.test.ts` | 2 | 3 | 1 |
| `tests/ChromeTest.elm` (new) | 8 | 10 | 6 |
| `tests/ViewModeTest.elm` (`splittingACard…`) | 8 | 11 | 4 |

**ADR-0001 gains seam 13** (what the session says about a document, and the
codecs behind it) and extends **seam 10** (the two chrome views that need no page
`Model`, driven with `Test.Html.Event`) and **seam 11** (the cards an event
leaves, not only the mode). `CONTEXT.md`'s list follows, and also gains the
one-line entry for ticket 18's seam 12, which the ADR had and it did not.

### Verification

Rebased on `selfhost` three times (over ticket 18, ticket 23's claim, and
ticket 23's own commit). On the final rebased tree: `bun run test:elm` 199/199,
`bun test` 201/201 across 22 files, `bun run newbuild` exit 0,
`node config-check.js` exit 0, and an ad-hoc `tsc --noEmit --strict` over
`src/ui/*.ts` clean.

CI green on `selfhost` for every push:
[33089756188](https://github.com/advaitmb/client/actions/runs/33089756188)
(`4df9da1`, the claim),
[33092133528](https://github.com/advaitmb/client/actions/runs/33092133528)
(`2186eaf`, S1/S3/S4/S10),
[33092886443](https://github.com/advaitmb/client/actions/runs/33092886443)
(`3ef333b`, S2 + S12) and
[33093397621](https://github.com/advaitmb/client/actions/runs/33093397621)
(`3047616`, P4 + the self-review pass).

## Comments

- **Red-before-green transcript.** S4: `Ok "Notes (draft"` vs
  `Ok "Notes (draft (2)"`, `Ok "My.Doc (2)"` vs `Ok "My.Doc"`, and `Ok "Doc (3)"`
  vs `Ok "Doc (2)"` twice (the substring and the sparse-numbering cases) — got by
  transcribing the old regex back in over the new implementation, so the reds are
  against the real defect and not a stub. S3: the unknown-owner cursor came back
  `"not-allowed"` under the two-valued attribute. S10: four metadata failures —
  collaborators lost on three, and the no-revision and unnamed cases failing to
  decode *at all* (`Expecting an OBJECT with a field named _rev`) — plus the zero
  stamp as `Err "Invalid UpdatedAt string"`. S12: 6 failures against the previous
  views (no crumb announced as a button, so the four crumb cases could not find
  one; `#new-button` not a `button`; the `<img>` still in the tree). P4: all four
  blocked splits really left the card truncated — `"First"` for `mod+j` and
  `mod+l`, `" card"` for `mod+k`, in both editors — with no card inserted.
- **The breadcrumb's keydown must stop propagating, and that is not tidiness.**
  Mousetrap binds the app's shortcuts on `document` and only ignores keystrokes
  whose target is a form field (`doc.js`'s `enter` case checks
  `activeElement.nodeName === "TEXTAREA"`). A focused `div` is neither, so
  without `stopPropagation` making the crumbs focusable would have *introduced* a
  bug: Enter would navigate **and** fire the global `enter`, opening the active
  card's editor. Space is `preventDefault`ed or it scrolls the page as well. A
  real `<button>` would not need either (Enter and Space are its own activation),
  which is one more reason the other two controls are buttons.
- **Guard ordering is test-visible here, unlike ticket 31.** Ticket 31 recorded
  that moving a guard to the front of its pipeline kept every test green, because
  what leaks past it is a `Cmd`. This guard undoes a **model** change, so moving
  it to the front fails all four blocked tests (checked). ADR-0001 seam 11 and
  CONTEXT.md now draw that line: ordering over a model change is visible,
  ordering over a `Cmd` is not.
- **Fullscreen's save-indicator glyphs change appearance.** Unifying means the
  fullscreen indicator draws the TS stroked icons instead of Ant's filled ones.
  That is the cost of one implementation, and it is the direction the app is
  already going (the header has drawn these glyphs since it moved). Net gain: the
  stylesheet's state colours, written for filled icons, work in both places for
  the first time, and `.database-error` has a colour at all (red) where it
  previously took the surrounding text colour.
- **`Metadata.encode`'s only caller is on ticket 21's removal list.**
  `Import.Single.encode` (which contains `( "data", Enc.null ) --TODO`) is
  catalogued as dead in CODE_REVIEW §6. The round trip is fixed and pinned
  because the ticket asks for it and because the encoder is exported, but if 21
  removes that caller the encoder goes with it — the tests then pin a codec with
  no producer, and should go too rather than be preserved.
- **S10's third item is out of scope and stays out.** `Conflict.opToValue` /
  `opDecoder` "could never round-trip" — they are part of the legacy conflict
  machinery (`Doc/Data/Conflict.elm`) that ticket 21 removes wholesale, along
  with `Diff3` and `jinjor/elm-diff`. Fixing a codec on a module scheduled for
  deletion would be work thrown away, and pinning it with tests would make the
  deletion harder.
- **Zero-caller declarations this ticket created, for 21.**
  `Translation.timeDistInWords` (its last caller was the Elm save indicator) and
  with it the `gingko/time-distance` package in `elm.json`; the six save-state
  `TranslationId` constructors (`Loading`, `UnsavedChanges`, `SavedInternally`,
  `ChangesSynced`, `DatabaseError`, `LastSaved`/`LastSynced`/`LastEdit`), which
  are inside 21's "138 dead constructors" count. Removed from `Doc.UI`'s import
  list; the declarations themselves are 21's.
- **P4 is done, and it is on ticket 25's list (P1–P5).** The added scope brought
  it here because the truncate-before-guard shape and the triplication were one
  fix. Ticket 25 should find `saveCard`/`saveCardIfEditing` already collapsed
  (`stageCardText`) and the split shortcuts' "two different idioms for the same
  operation" gone (`splitCard`); P1, P2, P3 and P5 are untouched. Nothing in this
  ticket was done for performance — the shared code paths are the same work per
  keystroke as the copies were.
- **`src/ui/README.md` still does not mention any of this** — S11's staleness,
  which is not this ticket's. `src/ui/index.ts`'s "moved so far" list and
  ARCHITECTURE §2/§6.5/§7 all name `<gw-save-indicator>`.
- **Not covered by a test, and why.** (1) The show/hide-password buttons: those
  views take a page `Model`, which carries a `Nav.Key` no test can make (the
  reason seams 5, 7–10 exist). (2) `Doc/Fullscreen.elm` rendering the shared
  element, and `Page.App` passing `ownershipName`/`encodeSaveState` — one-line
  view wiring at the same `Nav.Key` boundary. (3) The CSS: `.label-row`'s flex
  row and the `stroke` colours are reasoned from the rules they replace
  (`#form-page label` was the flex box; the state rules already targeted `fill`
  for icons that no longer have one), not observed.
