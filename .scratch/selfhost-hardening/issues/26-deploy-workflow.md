# 26: Deployment workflow

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01 · **Owner decided (2026-08-27):** test-only CI is enough
for now — resolved as **wontfix**. Reopen when a deploy target exists.

**What to build:** (Pending) A CI job that builds `web/` and delivers it to
the owner's hosting target on push to `selfhost` (or on tag), using whatever
the target is: static host, Docker image alongside gingko/server, rsync to a
VPS, etc.

## Acceptance criteria

- [ ] Specified from the owner's answer (rewrite this section then).
- [ ] Secrets documented by name only; never committed.
