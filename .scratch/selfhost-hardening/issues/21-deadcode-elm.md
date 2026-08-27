# 21: Dead code purge — Elm

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

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

- [ ] All §6 Elm items removed (or individually justified in Comments).
- [ ] `elm.json` drops now-unused packages (`elm-money` went with 03;
      `jinjor/elm-diff`, `elm-explorations/markdown` go here).
- [ ] `elm make` clean; full test suite green; bundle still builds.
