# 36: Shortcuts still act while a header menu is open with focus on body

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 35 (resolved)

**Covers:** finding recorded by ticket 35 (not in CODE_REVIEW.md).

**What to build:** Ticket 35 scopes shortcuts by the focused element's region,
which cannot help when a header menu is open but focus sits on `<body>` —
Safari does not focus a clicked button, so clicking the gear leaves the menu
open and every single-letter shortcut still driving the document behind it.

The fix belongs in Elm, not the port layer: `Page.App` already gates
shortcuts on `modalState` and simply never consults `headerMenu`. One `case`
addition. Pairs naturally with ticket 34's open question about Escape closing
the header menus.

Read ticket 35's `## Answer` (why the port-layer rule cannot cover this) and
ticket 34's `## Comments` first.

## Acceptance criteria

- [ ] Red first: with a header menu open and focus on body, document
      shortcuts do not act; Escape closes the menu.
- [ ] Shortcuts still act with no menu open (pinned).
- [ ] Full suite + typecheck + build green; CI green.
