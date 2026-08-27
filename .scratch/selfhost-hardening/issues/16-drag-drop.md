# 16: Drag-drop correctness (off-by-one, stale flags, id paste, autoscroll throw)

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E7, E8, E9, E15.

**What to build:** Native drag-drop behaves: a same-parent downward drop lands
exactly where indicated (compute the index on the pruned tree, E7); internal
drags are not misreported to Elm as external and both sides' drag flags reset
after every drop (E8 — send `DragDone`, fix the internal-drag detection, make
the reset reachable despite `stopPropagation`); dropping a card onto an open
editing textarea does not paste its raw card id (E9); drag auto-scroll over
non-column areas doesn't throw every 15 ms (E15).

## Acceptance criteria

- [ ] Failing test first for the drop-index math (seam 1 or extracted
      helper): same-parent downward drop by one lands one slot down, not two.
- [ ] Flag lifecycle: after an internal drop, neither JS nor Elm still
      believes a drag is in progress (test at a practical seam).
- [ ] Textarea drop is prevented or inert; no raw id insertion.
- [ ] Autoscroll handles undefined column hover.
- [ ] CI green.
