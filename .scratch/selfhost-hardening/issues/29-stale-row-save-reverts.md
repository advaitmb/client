# 29: Saves built from stale rows can revert a concurrent move/edit

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 11 (resolved — its `StagedRows` memory is the foundation)

**Covers:** new finding from ticket 11's resolution (not in CODE_REVIEW.md).
Same class as D8's second half, but for content/parentage instead of
positions.

**What to build:** `CTUpd`/`CTMov`/`CTRmv`/`CTMrg` in `Doc/Data.elm` build
their new row from `data`'s newest row for the card, which lags a save
already handed to the port layer. Move-then-edit within one Dexie round trip
writes an update row carrying the OLD position/parent — silently reverting
the move (and symmetrically for the other op pairs). Ticket 11 added
`StagedRows` (cleared on `cardDataReceived`) and `visibleWithStaged` for
placement; extend the same memory to the four op limbs (a
`newestRowOf id` lookup that consults staged rows first). Read ticket 11's
`## Answer` and `## Comments` first — including its noted limitation that
staging is cleared by ANY rows echo (improve if cheap, else keep and
document).

## Acceptance criteria

- [ ] Red first: move card then edit it before the rows echo → the edit row
      keeps the new parent/position; symmetric tests for the other limbs
      where meaningful.
- [ ] `StagedRows`' docstring updated (no longer "placement only").
- [ ] Full suite + build green; CI green.
