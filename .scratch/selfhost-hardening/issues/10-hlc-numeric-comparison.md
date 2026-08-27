# 10: Numeric HLC stamp comparison in JS

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D7 · Decision: ADR-0005 §3.

**What to build:** JS-side code that orders or maxes HLC stamps
(`"ts:counter:hash"`) agrees with Elm's numeric ordering even when a
multi-card save mints many stamps in one millisecond (unpadded counter:
`…:10:x` currently sorts before `…:9:y` as a string). Fixes too-low pull
checkpoints (redundant re-pulls) and stale backup selection.

## Acceptance criteria

- [ ] One exported stamp-comparison helper (extracted per ADR-0001 seam 2),
      unit-tested including the `9` vs `10` counter case and equal-timestamp
      ties.
- [ ] Checkpoint computation, delta max, and backup selection all use it —
      no `.sort()` default-order or lodash `_.max` on stamp strings remains.
- [ ] CI green.
