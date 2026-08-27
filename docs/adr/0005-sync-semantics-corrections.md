# ADR-0005: Sync semantics — newest-version-per-id, and what resolving a conflict means

**Status:** accepted · **Date:** 2026-08-27

## Decision

1. **Newest-version-per-id is the only legal view of the version log.** Any
   computation over `cards` rows (descendant collection, merge child
   gathering, conflict tree building) must first reduce to the newest row per
   card id and drop deleted cards where the operation implies visibility.
   Scanning raw rows caused subtree deletion to delete moved-away cards and
   merges to resurrect stale children (CODE_REVIEW.md D1/D2/S9).
2. **Resolving a conflict discards the whole local unsynced line.** When the
   user picks `Theirs` or `Original`, ALL unsynced rows for that card id are
   removed — not just the newest. Picking `Ours` keeps only the newest
   unsynced row as the winning version. Anything else re-pushes edits the
   user explicitly discarded (CODE_REVIEW.md D3).
3. **Stamps are compared numerically everywhere.** JS code must parse
   `"ts:counter:hash"` and compare (numeric ts, numeric counter, hash) — never
   lexicographic string order (CODE_REVIEW.md D7). One comparison helper,
   exported and tested (ADR-0001 seam 2).

## Context

These are correctness invariants of the card-version data model, not
per-ticket implementation details; every sync-family ticket assumes them.
