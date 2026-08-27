# 13: Session preferences persist correctly (sidebar, last doc, tray/sort)

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E1, E2, E3.

**What to build:** Three preference bugs, one seam (Session decode/persist):
closing the sidebar records it closed (both branches currently persist
`True`); "reopen last document" works (`lastDocId` is decoded then discarded,
so `/` never redirects); logging in preserves `shortcutTrayOpen` and `sortBy`
instead of clobbering them with hardcoded defaults.

## Acceptance criteria

- [ ] Failing decoder/persistence tests first for all three.
- [ ] Sidebar closed → persisted closed → re-init renders it closed.
- [ ] With a stored `lastDocId`, landing on `/` opens that document.
- [ ] Login response decoding keeps existing tray/sort preferences.
- [ ] CI green.
