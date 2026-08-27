# 32: Restore the theme picker

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 17 (resolved) · 24 (touches header.ts concurrently — wait for
it to resolve)

**Covers:** owner decision 2026-08-27: restore a theme picker (the strip-down
removed it in `a203a9c`; ticket 17 rebuilt and tested the save/restore round
trip, which is currently unreachable).

**What to build:** A theme picker in the header's settings menu (beside
"Word count..."), listing the six themes whose CSS already ships. Choosing
one applies it immediately (`applyTheme`) and persists via the existing
`ThemeChanged` → `SaveThemeSetting` ring (currently producer-less — this
ticket is the producer). Reloading the document restores it (ticket 17's
path, already tested). Read ticket 17's `## Answer` first: `Theme.fromLocalStore`,
the `TitleParts` render structure in header.ts, and its render-preservation
rules (don't rebuild the title input).

## Acceptance criteria

- [ ] Picker reachable from the header settings menu; all six themes listed;
      current theme indicated.
- [ ] Choosing a theme applies it now and survives reload (end-to-end through
      the existing tested ring — red-first test for the picker's event
      emission at seam 3, and the App.elm mapping).
- [ ] Keyboard operable (real buttons/menu items — S12's standard).
- [ ] Full suite + build green; CI green.
