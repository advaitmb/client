# ADR-0004: Bun is the canonical runtime; npm lockfile kept in sync

**Status:** accepted · **Date:** 2026-08-27

## Decision

- **Bun** is the canonical package manager, script runner, and test runner:
  `bun.lockb` is the lockfile of record; build scripts may use Bun APIs but
  should prefer runtime-agnostic forms (`import.meta.dirname` /
  `fileURLToPath`) where the cost is trivial, so failures under Node are not
  opaque.
- `package-lock.json` is retained **only** because Claude Code cloud sessions
  install with npm via the SessionStart hook. CI verifies it stays in sync
  with `package.json` (`npm install --package-lock-only` produces no diff, or
  equivalent check) so it can never drift silently again.

## Context

The build is Bun-only today (`esbuild.mjs` uses `import.meta.dir`) and the
committed npm lockfile had drifted so far it still resolved Sentry, Electron
and PouchDB (CODE_REVIEW.md B5/B6). Two lockfiles with no consistency check
is how that happened.
