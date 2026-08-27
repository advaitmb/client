# 05: Newest-version-per-id everywhere (subtree delete / merge / conflict tree)

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D1, D2, D10, S9 · Decision: ADR-0005 §1.

**What to build:** Operations that scan version rows respect
newest-version-per-id and deletion visibility, so: deleting a subtree never
deletes a card that was moved out of it (D1); merging cards never re-parents
stale or deleted child rows (D2); the dead/contradictory limb of
`resolveDeleteConflicts` is fixed or removed with its intent documented (D10);
conflict-tree building doesn't depend on JS row order (S9).

## Acceptance criteria

- [ ] Failing tests first (seam 1): move-then-delete-old-parent keeps the
      moved card; merge with a deleted child doesn't resurrect it; merge
      position offsets ignore deleted children.
- [ ] `getDescendants`-family scans dedupe to newest row per id.
- [ ] D10's filter is corrected or the limb removed, with a test pinning the
      chosen behavior.
- [ ] All tests green in CI.
