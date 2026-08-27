# 08: JSON import must not race the open document's state

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D5.

**What to build:** Importing a JSON tree never writes another document's
snapshot or timestamps, and works on a fresh session. Today the import batches
two port commands whose order is unspecified, and the card-save handler keys
off a JS-global current-tree id that only the *other* command sets.

## Acceptance criteria

- [ ] The save path used by import carries its tree id explicitly (or the two
      commands are strictly sequenced) — no dependence on `Cmd.batch` order or
      a global set elsewhere.
- [ ] Fresh-session import (no document ever opened) succeeds.
- [ ] Importing while a different document is open leaves that document's
      snapshots/timestamps untouched (test at whichever seam is practical).
- [ ] CI green.
