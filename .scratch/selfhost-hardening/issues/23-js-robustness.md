# 23: JS robustness — timing hacks, leaks, dispatch, boot

Part of `../map.md`. **Type:** task · **Status:** claimed

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

**Added scope (from ticket 07's resolution):** `doc-helpers.js`'s
`editBlurHandler` is one module-level handler shared by all `gw-textarea`
instances — per-instance state is the S13-style fix.

**Added scope (from ticket 10's resolution):** `doc.js`'s snapshot-id
`Math.max` uses a seedless `reduce`, which throws on an empty card set —
harden alongside S8's boot guards.

**Added scope (from ticket 28's resolution):** `saveBackupToImmortalDB` in
doc.js half-applies ADR-0005 §1 — it dedupes newest-per-id but keeps cards
whose newest row is a deletion, and its `treeHelper` filters only on
`parentId`. Low stakes (write-only backup) but fix while hardening the file:
drop deleted cards after the dedupe.

**Added scope (from ticket 18's resolution):** the swallows ticket 18 left
as yours: `fromElm`'s dispatch catch (S7's site), the `window` error handler,
and the `InitDocument`/`LoadDocument` catches. Also note ticket 18's new
modules (`ws-errors.js`, `clipboard.js`) — extend, don't duplicate.

## Acceptance criteria

- [ ] No anonymous-listener accumulation on `ScrollCards` (verifiable by
      inspection or test).
- [ ] Async handler rejections in the dispatch table are caught and reported
      with the failing tag's name.
- [ ] Corrupted session JSON in localStorage boots to a working (guest)
      state — test at a practical seam.
- [ ] Each remaining S5 timing hack has a one-line justification in Comments.
- [ ] CI green.
