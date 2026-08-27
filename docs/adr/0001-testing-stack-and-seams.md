# ADR-0001: Testing stack and pre-agreed seams

**Status:** accepted · **Date:** 2026-08-27

## Decision

- **Elm:** `elm-test` (via `elm-test-rs` or npm `elm-test`), tests under
  `tests/`. Primary target: the `Doc.Data` public API and other pure document
  logic (`UpdatedAt`, `TreeStructure`, `Coders` exports).
- **TypeScript/JS:** `bun test` (built into the canonical runtime, ADR-0004),
  with `happy-dom` (or jsdom) registered for custom-element tests. Targets:
  `src/ui/*` elements (attribute-in → DOM/event-out) and pure helpers
  extracted from `src/shared/doc.js`.
- **CI:** one workflow (`.github/workflows/ci.yml`) running on pushes and PRs
  to `selfhost`: install (bun), typecheck/build, `elm-test`, `bun test`,
  `config-check` (which must exit non-zero on mismatch). The upstream
  Electron-era `build.yml` and `master`-only `web-deploy.yml` are deleted —
  they call scripts that no longer exist.

## Pre-agreed seams (the `tdd` skill requires these to be fixed up front)

1. `Doc.Data` public functions — behavior of localSave, tree
   materialization, sync-state classification, delta generation, conflict
   resolution, restore. Test through exported functions only; the
   `*_tests_only` exports may be used where the public surface is too coarse,
   or removed if unused.
2. Pure JS sync helpers — HLC stamp comparison, checkpoint computation,
   backup-version selection. Extract them from `doc.js` into an importable
   module first; do not test through Dexie or the WebSocket.
3. Custom elements — public contract only: set attributes, observe rendered
   DOM and emitted `CustomEvent`s. No reaching into private fields.
4. Session-level sequences extracted from `doc.js` — added by ticket 04 for
   the logout sequence (`src/shared/session.js`). These are not pure, so
   seam 2 does not cover them: the rule is the same extraction (nothing in
   `doc.js` itself is importable, it boots the app at module load) but they
   are observed through the boundaries they actually cross — a faked `fetch`,
   the real `localStorage`, and the callbacks the port layer passes in. Still
   never through Dexie or the WebSocket.

No test is written at a seam outside this list without updating this ADR.

## Context

The branch shipped with zero tests and CI that cannot fail
(CODE_REVIEW.md B1–B3). Every bug-fix ticket derived from the review is
TDD-shaped and blocked on this ADR's stack existing.
