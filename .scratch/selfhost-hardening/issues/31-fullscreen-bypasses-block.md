# 31: Fullscreen editing bypasses the document block

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 15 (resolved)

**Covers:** new finding from ticket 15's resolution (not in CODE_REVIEW.md;
E5's family).

**What to build:** `changeMode`'s `FullscreenEditing` target branches have no
`preventIfBlocked` at all, and `"shift+enter"` reaches one directly — so on a
blocked document (history view open, public document) shift+enter really
opens a fullscreen editor and broadcasts `CollabEditing`. Guard all
fullscreen-entering transitions the way ticket 15 ordered the two `Editing`
branches (guard replaces the whole result triple, last in the chain). This is
a behavior change across three-ish branches, not a reordering — read ticket
15's `## Answer` (E5) first, and its note on why elm-test can't inspect the
`Cmd` (verify the guard via the model/mode transition, which IS testable).

## Acceptance criteria

- [ ] Red first: on a blocked document, the fullscreen-entering keyboard
      paths leave the mode unchanged (mode transition testable at seam 1/the
      Page.Doc seam even if the Cmd is not).
- [ ] Unblocked fullscreen entry still works (pinned).
- [ ] Full suite + build green; CI green.
