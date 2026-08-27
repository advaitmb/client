# 21: Dead code purge — Elm

Part of `../map.md`. **Type:** task · **Status:** needs-info

**Blocked by:** 03 · **Owner decision:** questionnaire Q "dead-code purge
scope". Default if unanswered: full purge (every item was verified
zero-caller).

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

## Acceptance criteria

- [ ] All §6 Elm items removed (or individually justified in Comments).
- [ ] `elm.json` drops now-unused packages (`elm-money` went with 03;
      `jinjor/elm-diff`, `elm-explorations/markdown` go here).
- [ ] `elm make` clean; full test suite green; bundle still builds.
