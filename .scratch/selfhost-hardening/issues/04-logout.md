# 04: A working logout path

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C3.

**What to build:** A visible control (decision: in the sidebar's settings/
account area, since the old account menu was removed) lets the user log out:
server session ended (POST /logout on gingko/server), local session blob
cleared, redirect to login. Switching accounts becomes possible.

## Acceptance criteria

- [ ] A rendered UI control produces the logout flow (the Elm message chain
      or a TS-side event — whichever is cleaner given the sidebar is a custom
      element).
- [ ] The JS dispatch table handles the logout tag (today `LogoutUser` throws
      "Unexpected message from Elm"): clears
      `gingko-session-storage`, calls the server, and completes the redirect.
- [ ] Local Dexie data handling on logout is deliberate and documented in the
      ticket (kept for offline safety vs cleared — implementer's call, noted
      in Comments).
- [ ] Test at the seam that's practical (e.g. dispatch handler unit test).
- [ ] CI green.
