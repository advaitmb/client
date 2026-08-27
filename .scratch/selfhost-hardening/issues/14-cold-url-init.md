# 14: Cold-loading any URL runs that page's init commands

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E4.

**What to build:** Pasting any app URL into a fresh tab boots the page it
names. Today `Main.init` discards the initial page's `Cmd`, and unhandled URL
shapes return `Cmd.none` — a cold-loaded two-segment doc URL sits on a spinner
until an unrelated push redirects to the wrong (most-recently-updated)
document.

## Acceptance criteria

- [ ] `Main.init` executes the initial page's commands.
- [ ] Every URL shape either routes somewhere deliberate or lands on a
      not-found/redirect with its commands run — no dead-end spinner.
- [ ] Test the route dispatch at a practical seam (extract the URL→page
      decision if needed to make it testable).
- [ ] CI green.
