# 07: Editing textarea survives re-parenting (silent edit loss)

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D4.

**What to build:** Typing into a card keeps working after the tree re-renders
around it (second tab writes, collaborator edit, checkbox toggle while
editing). Today `gw-textarea` loses its event listeners permanently when the
tree element re-parents it mid-edit, so subsequent keystrokes silently stop
reaching Elm and the next save writes stale content.

## Acceptance criteria

- [ ] Failing test first (seam 3): create the element, simulate
      disconnect + reconnect (as re-parenting does), dispatch input — the
      keystroke/cursor events still fire.
- [ ] `connectedCallback`/`disconnectedCallback` are symmetric (re-bind on
      reconnect, or bind listeners in a way re-parenting can't break).
- [ ] CI green.
