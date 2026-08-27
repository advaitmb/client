# 34: Header follow-ups — history-close semantics, export radio group, slider name

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 33 (resolved)

**Covers:** ticket 33's three recorded findings (not in CODE_REVIEW.md).

**What to build:**
1. **History close reverts the checkout** (decision taken: closing the
   history view without restoring returns the tree to current — the
   preview-exit convention). Today `CancelHistory` reverts but the icon's
   `HistoryToggled False` only closes the menu, leaving the tree at the
   snapshot. Wire the icon's close (and Esc if it closes history) to the
   reverting path in `Page.App`; a restore still commits. Pin both with
   tests.
2. **Export menu toggles get radio semantics** — the eight toggles are a
   radio group rendered as buttons; give them keyboard radio behavior
   (arrow keys, one tab stop) or justify a simpler-but-correct pattern.
3. **`#history-slider` gets an accessible name** (`aria-label`).

Read ticket 33's `## Answer` (the guard/refocus/reset conventions) and
ticket 24's S12 standard first.

## Acceptance criteria

- [ ] Closing history via icon/Esc reverts to current; restore still works
      (red-first where the seam reaches — the Page.App mapping and mode
      transitions are testable).
- [ ] Export group keyboard-operable per the chosen pattern, justified.
- [ ] Slider named; existing header tests green.
- [ ] Full suite + typecheck + build green; CI green.
