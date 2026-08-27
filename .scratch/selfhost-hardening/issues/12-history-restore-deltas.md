# 12: History restore stops re-deleting already-deleted cards

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D9.

**What to build:** Restoring a snapshot produces deltas only for cards whose
state actually changes. Today every card ever deleted gets a fresh unsynced
deletion row on each restore (snapshots exclude deleted cards, and the merge
marks every absent card deleted), and empty deltas are pushed anyway.

## Acceptance criteria

- [ ] Failing test first (seam 1): restore over a doc with previously deleted
      cards emits no new rows for cards already `deleted = True`.
- [ ] Empty per-card deltas are not pushed.
- [ ] Restore still deletes cards that exist now but are absent from the
      snapshot, and restores content/positions per snapshot.
- [ ] CI green.
