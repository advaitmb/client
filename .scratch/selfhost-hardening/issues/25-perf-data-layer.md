# 25: Data-layer performance (Dict-keyed hot paths)

Part of `../map.md`. **Type:** task · **Status:** needs-info

**Blocked by:** 05, 06, 12 · **Owner decision:** questionnaire Q "perf scope".
Default if unanswered: do it last, after all correctness tickets are green.

**Covers:** CODE_REVIEW.md P1, P2, P3, P4, P5.

**What to build:** Multi-thousand-card documents stay responsive: the
per-save O(n²) hot paths (tree materialization, sync-state grouping, delta
generation, descendant scans) move to Dict-keyed structures (by id /
children-by-parentId); sort-to-take-max becomes single-pass max; the
duplicated per-card-recompiled search regex is unified and hoisted; the
triplicated save-card logic collapses; the misleading lazy-view key is fixed.
Behavior must not change — the correctness tickets' tests (05, 06, 12) are the
safety net, which is why they block this.

## Acceptance criteria

- [ ] All existing `Doc.Data` tests pass unchanged.
- [ ] Demonstrated complexity win (benchmark or op-count reasoning in
      Comments) on a synthetic multi-thousand-card document.
- [ ] P3/P4/P5 duplications removed.
- [ ] CI green.
