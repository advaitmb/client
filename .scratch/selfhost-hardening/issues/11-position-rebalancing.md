# 11: Rebalance fractional card positions

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D8.

**What to build:** Card order stays stable no matter how many times cards are
inserted at the same spot. Midpoint insertion halves the gap each time (~50
inserts exhaust Float precision, after which siblings tie and order becomes
row-order-dependent). Strategy: when the computed gap between neighbors falls
below a safe epsilon, emit rebalanced positions for the affected siblings
(fresh version rows through the normal save path) instead of a degenerate
midpoint. Also address the rapid-insert case where two inserts mint identical
positions before the Dexie round-trip refreshes.

## Acceptance criteria

- [ ] Failing test first (seam 1): repeated same-spot inserts (>60) keep
      strict ordering; positions after rebalance are well-spaced.
- [ ] Rapid consecutive inserts can't mint identical positions.
- [ ] Rebalance rows sync like any other move (delta `mov` ops).
- [ ] CI green.
