# 06: Conflict resolution discards the whole local unsynced line

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D3 · Decision: ADR-0005 §2.

**What to build:** When the user resolves a conflict by picking **Theirs** or
**Original**, none of their discarded local edits ever reach the server: ALL
unsynced rows for that card id are removed, not just the newest. Picking
**Ours** keeps exactly the winning newest unsynced row.

**Note from ticket 05's resolution:** `cardDataReceived`'s auto-resolve
condition still tests `toAdd`/`toMarkSynced`, both of which
`resolveDeleteConflicts` now always leaves empty (the dead D10 limb was
removed). Check that condition still gates correctly while you're in there.

## Acceptance criteria

- [ ] Failing test first (seam 1): offline-edit a card three times (three
      unsynced rows), receive a conflicting synced row, resolve as Theirs →
      the card classifies as Synced and the next delta push contains nothing
      for it.
- [ ] Same for Original; Ours keeps one unsynced row.
- [ ] CI green.
