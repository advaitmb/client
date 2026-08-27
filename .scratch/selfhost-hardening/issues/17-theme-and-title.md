# 17: Theme restores on load; title input survives the clock tick

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E10, E12.

**What to build:** Two persistence/render fixes: the per-document theme
setting, which is saved on change, is actually read back and applied when the
document loads (E10); and typing in the header's title input is never
discarded by the 9-second clock tick re-render — today only the `doc-title`
attribute is guarded while focused, but the `save` attribute tick rebuilds the
input anyway (E12).

## Acceptance criteria

- [ ] Saved theme round-trips: set → reload path → same theme active (test
      the decode/apply seam).
- [ ] With the title input focused and text typed, an unrelated attribute
      change re-render preserves the in-progress value (seam 3 test).
- [ ] CI green.
