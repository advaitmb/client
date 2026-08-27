# 23: JS robustness — timing hacks, leaks, dispatch, boot

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md S5, S6, S7, S8, S13.

**What to build:** The port layer stops relying on luck: the catalogued
`setTimeout`-instead-of-signal hacks are replaced with real readiness signals
(or individually justified in Comments), including the permanent 800 ms
header-geometry poll (S5); the per-navigation scroll-listener leak stops (S6);
port dispatch reports the real error and catches async handler rejections
(S7); boot survives corrupted localStorage and a missing root card instead of
white-screening (S8); the duplicated `CARD_DATA` symbol and other hidden
couplings in S13 are consolidated where cheap.

## Acceptance criteria

- [ ] No anonymous-listener accumulation on `ScrollCards` (verifiable by
      inspection or test).
- [ ] Async handler rejections in the dispatch table are caught and reported
      with the failing tag's name.
- [ ] Corrupted session JSON in localStorage boots to a working (guest)
      state — test at a practical seam.
- [ ] Each remaining S5 timing hack has a one-line justification in Comments.
- [ ] CI green.
