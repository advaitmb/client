# 35: Single-letter shortcuts reach the document from focused header controls

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 34 (resolved)

**Covers:** new finding from ticket 34's resolution (not in CODE_REVIEW.md).

**What to build:** Mousetrap binds single-letter shortcuts (`h`/`j`/`k`/`l`,
`w`, `/`, …) on `document`, and it only ignores form fields — so with a
header control focused (icon, menu entry, theme swatch, export toggle),
typing `j` moves the card cursor behind the open menu. Tickets 32–34's
keydown guard is deliberately narrow (Enter/Space, and arrows for the radio
groups), so these still leak.

Decide and implement the scope rule: either the header element swallows
printable-key keydowns while it holds focus / has a menu open, or Mousetrap's
`stopCallback` learns to ignore keys originating inside `<gw-header>` (the
latter is one place instead of many, and generalizes to the sidebar and
modals — prefer it unless there's a reason not to). Keep Escape working, and
keep the deliberate cases: shortcuts SHOULD work when focus is on the body
or a card.

Read tickets 32/33/34's `## Answer` sections for the existing conventions
before choosing.

## Acceptance criteria

- [ ] Red first: with each header control focused, a single-letter shortcut
      does not reach the document handler; Escape still does.
- [ ] Shortcuts still work with focus on body/card (pinned).
- [ ] Full suite + typecheck + build green; CI green.
