# 15: Small functional fixes (collab phantom, fullscreen Esc, wordcount, OPML, tray strings)

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E5, E6, E11, E13, E14.

**What to build:** Five small, independent behavior fixes bundled to fit one
session:

- E5 — a blocked document no longer broadcasts phantom "editing" collab state
  (guard ordering matches the correct `insert` pattern).
- E6 — Esc-from-fullscreen works: add the missing `FullscreenChanged` decoder
  branch so Elm learns the browser left fullscreen.
- E11 — the word-count modal's "Session" row reports words since the session
  started (record a session-start count) instead of always equaling Total.
- E13 — Leaves/Column exports in OPML format produce valid OPML (or the
  format option is removed for those selections — implementer's call, note it);
  the saved file's MIME type is a single valid string.
- E14 — the edit-mode shortcut tray renders real strings instead of literal
  "AltKey ParenNumber SetHeadingLevel" (mirror the TS help-modal fix).

**Added scope (from ticket 07's resolution):** `gw-textarea`'s
`observedAttributes` omits `disabled`, so its `attributeChangedCallback`
branch for it is dead — reachable via fullscreen's `editingByCollab`. Fix
alongside E5/E6.

## Acceptance criteria

- [ ] Each fix has a test where a seam exists (E5/E11/E13 via Elm tests; E6
      decoder test; E14 by translation-table assertion).
- [ ] CI green.
