# 24: Elm-side consistency and correctness smells

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md S1, S2, S3, S4, S10, S12.

**What to build:** The catalogued Elm-side smells are fixed: the duplicated
save-indicator logic is either unified or the TS copy brought to parity
(missing "Database Error…" branch, S1); the `SaveImportedTree` /
`SaveCardBasedTree` cross-boundary name mismatch is reconciled so grep finds
both sides (S2 — coordinate with ticket 08, which touches the same path);
`isOwner`'s loading-time default stops flapping owner-only UI (S3);
`copyNaming` escapes/anchors the document name (S4); the
encoder/decoder asymmetries in Metadata/UpdatedAt round-trip (S10); the
`<img src="" onerror>` message hack and non-keyboard-operable clickable divs
get honest interactive elements (S12).

## Acceptance criteria

- [ ] Copy-naming tests: regex metacharacters in names, substring names,
      sparse numbering.
- [ ] `Metadata.encode |> decoder` round-trips collaborators; `UpdatedAt`
      zero round-trips.
- [ ] Remaining items done or justified in Comments.
- [ ] CI green.
