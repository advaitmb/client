# 21: Dead code purge — Elm

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 03 · **Owner decided (2026-08-27):** full purge.

**Covers:** CODE_REVIEW.md §6 (Elm side): dead outgoing tags, dead Msgs,
dead modules (`UI.Collaborators`, `Feature`, the whole legacy conflict
machinery — `Doc.Data.Conflict`, `Diff3`, `setTreeWithConflicts`,
`jinjor/elm-diff`), dead functions across Session/Coders/Doc.*, dead
types/fields, 138 dead `TranslationId` constructors (~700 lines), degenerate
one-armed cases, and unused imports.

**What to build:** The Elm side compiles with the strip-down residue gone,
so every remaining declaration has a caller and future readers see only live
machinery. Follow the review's inventory; where removal would change behavior
(it shouldn't — everything listed is zero-caller), stop and note it in
Comments instead.

**Added scope (from ticket 04's resolution):** `ToggledAccountMenu` and
`SidebarMenuState.Account` are confirmed zero-producer after the logout
control landed — remove with the rest.

**Added scope (from ticket 24's resolution):** now zero-caller after its
refactors: `Translation.timeDistInWords` + the `gingko/time-distance`
package + six save-state `TranslationId`s; `Metadata.encode`'s only caller
was already on this ticket's list; `Conflict.opToValue`/`opDecoder` were
deliberately left for this ticket's deletion of that module.

## Acceptance criteria

- [x] All §6 Elm items removed (or individually justified in Comments).
- [x] `elm.json` drops now-unused packages (`elm-money` went with 03;
      `jinjor/elm-diff`, `elm-explorations/markdown` go here).
- [x] `elm make` clean; full test suite green; bundle still builds.

## Answer

**85 lines added, 2,289 removed across eleven commits — net −2,204.** Five
Elm modules deleted, four `elm.json` pins dropped and one demoted to indirect.
Every removal was re-verified against the current tree (`src/` *and* `tests/`)
rather than trusted from the review's snapshot, and that mattered: five of the
review's entries had grown a caller in the thirty tickets since it was written,
and one had lost one it never had.

### What went

*Whole modules* (5): `Diff3.elm`, `Doc/Data/Conflict.elm`, `Feature.elm`,
`Features.elm`, `UI/Collaborators.elm`.

*The legacy conflict machinery* (`fc7f519`) — the two modules above plus
`TreeStructure.setTreeWithConflicts`/`conflictToMsg`/`opToMsg`,
`Data.conflictList` (always `[]`), `Data.resolve` (identity), and eight
`*_tests_only` wrappers in `Doc.Data`. `diff3Merge` was a stub returning `[]`
and `conflictToMsg` fed it into `String.join "\n"`, so resolving a conflict by
hand would have blanked the card. The card-based machinery that replaced it is
untouched.

*The write-only rings* (`49b3ad3`) — the feature flags (`Session.features`,
`UserData.features`, both `optional "features"` lines), `Session.isFirstRun`/
`endFirstRun`/`SessionData.firstRun`/`UserSource` (`decoderLoggedIn` set it to
`False` unconditionally, so a signup's `True` never survived a reload), and
`Session.public`.

*The dead port tags and Msgs* (`38828c0`, `1d5e8d1`) — nine outgoing tags with
no Elm sender plus `ScrollFullscreenCards` (which the review missed);
`Main.SettingsChanged` (never produced, absorbed by the catch-all — a settings
sync reaching `Main` would have been silently dropped rather than failing to
compile); `ClickedShowVideos`; `CopyEmailClicked`, whose branches copied the
unsubstituted literals `{%SUPPORT_EMAIL%}`/`{%SUPPORT_URGENT_EMAIL%}`;
`ToggledAccountMenu` and `SidebarMenuState.Account` (ticket 04's added scope);
and the `SavedRemotely` incoming message, whose only `toElm` call sits in
`doc.js`'s never-called `pushSuccessHandler`.

*The zero-caller declarations* (`3d2ece6`, `aafbf54`) — `Doc.List.current`/
`isLoading`/`viewSwitcher`, `Doc.Metadata.decoderImport`,
`Import.Single.encode` (which wrote `( "data", Enc.null ) --TODO`) and
`Metadata.renameAndEncode`, `Doc.UI.fillet`/`viewWordcountProgress`,
`Page.Doc.dropRegions`/`viewContent`/`onWithOptions`,
`Data.parseUpdatedAt`/`prefixIds`/`getCardById`, `UpdatedAt.uniqueBy` and the
`UpdatedAt.Data` alias, `Page.Doc.Export.toExtension`,
`RandomId.fromObjectId`, `Types.dropIdToValue`/`VisibleViewMode`/
`VisibleViewState`, `Main.WebSessionData`, `Translation.timeDistInWords`,
`Utils.gravatar` and `Utils.onClickStop` (`59e958f`), plus the write-only
fields `ViewState.copiedTree`/`clipboardTree` and
`Page.Doc.ModelData.fileSearchField`.

*The elm-dnd drag path* (`ad85898`) — one chain end to end: `dropRegions` →
`DragDropMsg` → `Outgoing.DragStart` → `Incoming.DragStarted` →
`ViewState.draggedTree`, read only inside the branch that produced it, plus
`TreeUtils.getTreeWithPosition`. `ViewState.dragModel` stops being a pair, so
its five readers no longer ask a one-field record for its field via
`Tuple.second`. The native `<gw-tree>` path and the external-text drag are
untouched.

*The `<gingko-card>` import parser* (`84d4356`) — a closed island of ten
private declarations in `Coders.elm`: a writer that wrapped cards in
`<gingko-card id="...">`, a normaliser that rewrote those tags into `%!#<...>`
sentinels, and the `elm/parser` grammar that chomped them. Nothing outside the
island named any of it; export writes plain Markdown and import comes through
`Import.Single`/`Import.Template`.

*144 of 200 `TranslationId` constructors* (`bf4c795`, −733 lines) with their
`tr` arms and `numberPlural`. The review said 138 of 203; the true figure is
higher because tickets 24 and 32 moved the save indicator and theme labels to
TS in the meantime. Whole sections went: template/import modal, document list
and sort order, the six save-state strings plus `LastSaved`/`LastSynced`/
`LastEdit`, the entire help-modal shortcut list, word- and character-counts,
theme names, export settings, fonts, and the account/support links. The 56
survivors are what Elm views still render: `Doc.UI`'s shortcut tray,
`Page.Doc.Export`'s download labels, `Page.App`'s confirm-email banner and
delete prompt, `Doc.List.Loading`, `Page.Doc`'s cancel confirmation.

*Degenerate leftovers and unused imports* (`38828c0`, `849735e`) — the
one-armed `case model.modalState of _ ->`, the two consecutive
`case … of _ -> Sub.none` subscriptions, `viewModal`'s unused `ctrlOrCmd`,
`SharedUI.modalWrapper` (mirrored by `modal.ts`), the empty `-- FONT SETTINGS`
and `-- === TESTING ===` markers, the mislabelled `-- Debugging` section over
`Utils.text`, and unused imports in fourteen modules. `Doc/History.elm` and
`Doc/List.elm` are the two the review called view-era imports on logic-only
modules, and both really are logic-only: between them they shed `AntIcons`,
`Html`, `Html.Attributes`, `Html.Events`, `Svg.Attributes`, `Route`,
`Page.Doc.ContextMenu`, `Utils` and `Translation`.

### elm.json

Dropped: `jinjor/elm-diff`, `gingko/time-distance`,
`norpan/elm-html5-drag-drop`, `elm-explorations/markdown` (the live renderer,
`dillonkearns/elm-markdown`, names it only in its *test* dependencies, which an
application's solution does not carry). Demoted direct → indirect: `elm/parser`
— nothing imports it now that Coders' grammar is gone, but seven installed
packages still need it. `Chadtech/elm-money` went with ticket 03.

### Kept, against the review

- `GlobalData.public` and `Page.Doc.publicTreeLoaded` — `tests/WordcountTest.elm`
  and `tests/ViewModeTest.elm` build their models through them.
- `Doc.Metadata.encode` — ticket 24's `tests/CodecTest.elm` round-trips the
  live `decoder` through it.
- `Session.requestForgotPassword`/`requestResetPassword` — already gone; ticket
  19 took them with the auth pages, not this ticket.
- `userLoggedOutMsg` — the review calls it never sent. It has a sender now:
  ticket 04 rebuilt the logout chain, and `doc.js`'s `onLoggedOut` fires it.
- `Toast.elm`'s unused exports (`expireOnBlur`, `addUniqueBy`, `addUniqueWith`,
  `Phase(..)`) — a vendored third-party module whose header says do not trim,
  and `--optimize` strips what is not called.
- The theme ring (`Page.Doc.Theme`, `Outgoing.SetTheme`/`SaveThemeSetting`) —
  ticket 32 gave it a producer. Only the six theme *labels* in `Translation`
  went; every module and port in the ring stays.

### Two things the review's shape could not catch

Both found by checking declarations rather than following the inventory:

1. **Private zero-caller declarations** have no exposing-list entry to look
   wrong. Four existed, and two of them — `Page.Doc.Export.toExtension` and
   `RandomId.fromObjectId` — were *half*-removed by `3d2ece6` in this same
   ticket: it took each out of its module's exposing list and left the body
   behind. Removing a name from an exposing list is not removing the code.
2. **A dead branch is not always a hole.** `SavedRemotely`'s removal is safe
   only because `lastRemoteSave` has a better producer —
   `Data.lastSyncedTime newData`, read off the synced rows themselves rather
   than from a report about them. Checked before deleting; had there been no
   such producer this would have been a bug report, not a deletion.

### Verification

206 elm-test, 236 bun test, `config-check` exit 0, `bun run newbuild` green at
every one of the eleven commits. Two mechanical cross-checks now hold that did
not before: every one of `Outgoing.Msg`'s 28 constructors has a producer in
`src/elm`, and every incoming tag `Page.App`/`Page.Doc.Incoming` decodes has a
reachable JS sender. `docs/ARCHITECTURE.md` §4.5, §5.4 and §7 updated to match.

## Comments

**elm-format is not a gate, and this ticket did not become one.** CI does not
run elm-format, and 19 of the modules in `src/elm` did not validate clean at
`1929f3b` — verified by checking the pre-ticket tree out and validating it.
Reformatting them wholesale would have buried a −2,204-line diff in whitespace,
so nothing was reformatted for its own sake. The count is 18 now, and the
delta is entirely accounted for: `Coders.elm`, `Outgoing.elm` and
`Page/Doc/Incoming.elm` became clean as a side effect of the removals, and
`Types.elm` and `Import/Single.elm` were pushed *out* of clean by `3d2ece6`
(one missing blank line before a section marker in each, where a removal left
two where elm-format wants three) — this ticket's own regression, so both are
fixed here. No other file's status changes.

**Fourteen more direct `elm.json` pins have no importer** — deliberately left,
not missed: `CoderDennis/elm-time-format`, `Gizra/elm-debouncer`,
`elm-community/json-extra`, `f0i/debug-to-json`, `folkertdev/elm-sha2`,
`hecrj/html-parser`, `justinmimbs/date`, `justinmimbs/time-extra`,
`miniBill/elm-codec`, `rtfeldman/elm-css`,
`rtfeldman/elm-iso8601-date-strings`, `thaterikperson/elm-strftime`,
`truqu/elm-md5`, `ymtszw/elm-xml-decode`. Two reasons to leave them. They are
not strip-down residue — they predate this fork and were never named by §6,
which listed the pins it had verified. And dropping them is not a line edit
but a re-solve: three are load-bearing as *indirect* deps of packages still in
use (`justinmimbs/date`, `rtfeldman/elm-iso8601-date-strings`, and
`elm/parser`, which is why that one was demoted rather than deleted), and
removing `elm-community/json-extra` would cascade into the indirect set. Elm's
solver validates the whole solution, so this is verifiable work — just not
this ticket's. `f0i/debug-to-json` is a special case worth keeping: its only
mention is the commented-out `{--import DebugToJson exposing (pp)--}` at the
top of `Utils.elm`, which reads as a debugging aid someone toggles. Worth a
ticket of its own; nothing depends on it happening.

**`doc.js` still holds the other half of four pairs** — the `DragStart`,
`ScrollFullscreenCards` and `SaveCardBasedMigration` handlers, the
`pushSuccessHandler` that would send `SavedRemotely`, and the `DragStarted`
send inside `DragStart`. All are ticket 22's, and none can fire: each is keyed
on an outgoing tag Elm can no longer construct, or is a function nothing calls.
This is load-bearing rather than cosmetic, because an unknown incoming tag is
*not* ignored — `Page.Doc.Incoming`'s catch-all returns
`Err "Unexpected info from outside: <tag>"`, which reaches `onError` and
surfaces as a toast (ticket 18). Recorded in `ARCHITECTURE.md` §7.
