# Selfhost hardening — wayfinder map

## Destination

Every finding in [docs/CODE_REVIEW.md](../../docs/CODE_REVIEW.md) resolved:
the selfhost fork is safe (no XSS, no trial lockout, working logout), sync is
correct under tests, CI is real and green, and the strip-down residue is gone.

## Decisions so far

- ADR-0001 — testing stack (elm-test + bun test) and the three pre-agreed
  TDD seams; CI shape.
- ADR-0002 — trial/payments machinery is removed, not bypassed.
- ADR-0003 — all markdown-derived HTML goes through one DOMPurify allowlist.
- ADR-0004 — Bun is canonical; package-lock.json kept in sync, CI-checked.
- ADR-0005 — sync invariants: newest-version-per-id, conflict resolution
  discards the whole unsynced line, numeric stamp comparison.
- Tracker: local markdown under `.scratch/` (GitHub Issues disabled on repo).
- Ticket 01 resolved — test infra + CI live: `bun run test` (elm-test 3,
  bun test 7), config-check is a real gate, `.github/workflows/ci.yml` green
  on `selfhost`; `build.yml`/`web-deploy.yml` deleted. Details in
  `issues/01-test-infrastructure.md`.
- Ticket 02 resolved — C1 closed: `renderMarkdown()` in `src/ui/markdown.ts`
  (marked → DOMPurify with one explicit allowlist) is the only path to
  `innerHTML`, and both Elm call sites render through `<gw-markdown>`. The
  bun-test DOM moved happy-dom → jsdom because happy-dom cannot run DOMPurify
  (`Node.prototype.nodeName` is `''`; `NodeIterator` dies on removal), so the
  harness could not tell a working sanitizer from a missing one. Details in
  `issues/02-sanitize-markdown.md`.
- Ticket 03 resolved — payments/trial ring removed per ADR-0002 (trial block
  derivation, `PaymentStatus`/`daysLeft`, upgrade modal ring, `Route.Upgrade`,
  `Upgrade.elm`, `FlashPrice`/`CheckoutButtonClicked` + JS handler,
  `Chadtech/elm-money`); stale stored `paymentStatus` is ignored and dropped on
  next store; `setBlock` is history-view only. Unblocks 21 and 22. Details in
  `issues/03-remove-trial-lockout.md`.
- Ticket 07 resolved — `gw-textarea`'s listener lifecycle is symmetric and
  idempotent (`_bindListeners`/`_unbindListeners` driven by
  connected/disconnected), the document click handler is tracked per instance,
  and `start-value` seeds the textarea on first connect only, so a mid-edit
  re-parent by `tree.ts` no longer drops keystrokes or reverts in-flight text.
  7 tests at seam 3 in `tests/textarea.test.ts`. Details in
  `issues/07-editor-reconnect.md`.
- Ticket 05 resolved — every version-row scan in `Doc/Data.elm` goes through
  `newestPerId`/`newestVisible` per ADR-0005 §1, so subtree delete keeps
  moved-away cards (D1), merges neither re-parent stale children nor offset by
  deleted ones (D2), and the conflict tree is order-independent (S9).
  `resolveDeleteConflicts`' dead `toAdd` limb is **removed**, not repaired:
  inverting its filter would have pushed pre-deletion content over the local
  edit that delete-vs-edit resolution exists to keep — the surviving
  `toRemove` already yields `UndelOp` + our edit. 5 new tests at seam 1.
  Details in `issues/05-newest-version-dedupe.md`.

## Owner decisions (answered 2026-08-27)

All four questionnaire answers in
(`docs/to-questionnaire-selfhost-scope.md`): no password-reset emails —
remove the dead link (19); test-only CI — 26 resolved wontfix; full
dead-code purge (21, 22); perf refactor in scope, scheduled last (25). No
ticket carries `needs-info` any more.

## Notes

- Conventions: `docs/agents/issue-tracker.md`. Claim before work
  (`Status: claimed`, commit). A ticket is unblocked when every ticket in its
  `Blocked by:` line is `resolved`.
- Every ticket follows `/implement`: TDD at the ADR-0001 seams, `/code-review`
  before commit, work lands on `selfhost`.
- **Ticket-implementing agents run on Opus 5** (`model: "opus"` when spawning
  them). Orchestration/chat may run on a faster model, but implementation,
  TDD and code-review work does not.

## Tickets

| NN | Ticket | Covers | Blocked by |
|----|--------|--------|------------|
| 01 | test-infrastructure | B1 B2 B3 B6 | — |
| 02 | sanitize-markdown | C1 | 01 |
| 03 | remove-trial-lockout | C2 | 01 |
| 04 | logout | C3 | 01 |
| 05 | newest-version-dedupe | D1 D2 D10 S9 | 01 |
| 06 | conflict-resolution-discard | D3 | 01 |
| 07 | editor-reconnect | D4 | 01 |
| 08 | import-race | D5 | 01 |
| 09 | offline-metadata-resend | D6 | 01 |
| 10 | hlc-numeric-comparison | D7 | 01 |
| 11 | position-rebalancing | D8 | 01 |
| 12 | history-restore-deltas | D9 | 01 |
| 13 | session-prefs | E1 E2 E3 | 01 |
| 14 | cold-url-init | E4 | 01 |
| 15 | small-functional-fixes | E5 E6 E11 E13 E14 | 01 |
| 16 | drag-drop | E7 E8 E9 E15 | 01 |
| 17 | theme-and-title | E10 E12 | 01 |
| 18 | error-surfacing | E16 | 01 |
| 19 | auth-pages | A1 A2 A3 A4 | 01 |
| 20 | build-and-docs-cleanup | B4 B5 B7–B13 | 01 |
| 21 | deadcode-elm | §6 (Elm) | 03 |
| 22 | deadcode-js-ts | §6 (JS/TS, translations) | 03 |
| 23 | js-robustness | S5 S6 S7 S8 S13 | 01 |
| 24 | elm-consistency | S1 S2 S3 S4 S10 S12 | 01 |
| 25 | perf-data-layer | P1–P5 | 05 06 12 |
| 26 | deploy-workflow | (new) | resolved: wontfix |

## Not yet specified

- Nothing — all fog cleared by the 2026-08-27 questionnaire answers.
