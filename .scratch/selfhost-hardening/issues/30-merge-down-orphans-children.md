# 30: Merging down into a childless card orphans the source's children

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 29 (resolved)

**Covers:** new finding from ticket 29's resolution (not in CODE_REVIEW.md).

**What to build:** In `Doc/Data.elm`, `mergeCards`' `not isUp` branch has the
`isUp` branch's one-sided limbs unswapped: for
`( lastPosOfCurrent, firstPosOfOther )`, the `( Nothing, Just _ )` case —
current card childless, other card HAS children — returns `[]`, so merging
**down** into a childless card gives the source card's children no
re-parenting rows while the same save deletes their parent. The children
become unreachable (parent deleted, never re-parented). Fix the case
analysis so both merge directions re-parent children symmetrically.

Read ticket 29's `## Answer` first — `mergeCards` now takes the visible
cards and works in `Card ()`; build on that shape.

## Acceptance criteria

- [ ] Red first: merge a card with children DOWN into a childless sibling →
      every child gets a re-parenting row targeting the surviving card; the
      materialized tree keeps them.
- [ ] Symmetric test for merge up (already-working direction pinned).
- [ ] Full suite + build green; CI green.
