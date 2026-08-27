# 33: Header icons are mouse-only

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 32 (resolved)

**Covers:** new finding from ticket 32's resolution (S12's family; the
pre-existing hole ticket 24 didn't cover).

**What to build:** The three header icons (settings gear, export, history)
are `div`s with `onclick`, so the menus ticket 32's picker lives in are
mouse-only to OPEN. Make them real `type="button"`s (or keyboard-operable
per ticket 24's S12 standard), with the same Enter/Space keydown guard
tickets 24/32 used (Mousetrap's document bindings ignore only form fields —
an escaping Enter opens the active card's editor). Keep ticket 17's
render-preservation rules (title input never rebuilt) and 32's refocus
convention.

## Acceptance criteria

- [ ] Each header icon reachable and operable by keyboard; red-first seam-3
      tests per icon.
- [ ] No Mousetrap leakage (Enter/Space guarded); existing header tests stay
      green.
- [ ] Full suite + build + tsc green; CI green.
