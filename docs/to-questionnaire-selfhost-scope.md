# Selfhost scope decisions

**Purpose:** four tickets in the fix pipeline are blocked on facts about your
deployment and on scope choices only you can make. Everything else is already
running autonomously.

**From:** Claude (pipeline session), **To:** advaitmb, **How your answers will
be used:** they flip the blocked tickets from `needs-info` to
`ready-for-agent` and fix their acceptance criteria.

## Context

The `selfhost` branch review (docs/CODE_REVIEW.md) produced ~70 findings, now
filed as tickets under `.scratch/selfhost-hardening/` (GitHub Issues are
disabled on this repo — enable them and say so if you'd rather track there).
Technical decisions are recorded in `docs/adr/`. The questions below are the
only ones that need you.

## How to answer

Answer inline in chat or edit this file — either works. "I don't know" is a
useful answer: the affected ticket then takes the recommended default.

## Auth

### Does your gingko/server deployment send password-reset emails?

_Why this matters: decides whether "Forgot your Password?" gets a real flow or
gets removed (the link currently points at a route that doesn't exist)._

> Recommended default if unsure: remove the link (and the dead
> `requestForgotPassword`/`requestResetPassword` plumbing); it can come back
> when the server supports it.

**Answered 2026-08-27:** No / not sure — remove the link.

## Deployment / CI

### How do you deploy the built `web/` directory (static host, Docker, rsync to a VPS, something else) — and do you want a deploy workflow in CI?

_Why this matters: a test-only CI workflow is being built regardless; a deploy
workflow needs your target's details._

> Recommended default: test-only CI now; add deployment later when you can
> describe the target.

**Answered 2026-08-27:** Test-only CI for now (ticket 26 → wontfix).

## Scope

### Dead-code purge: full or conservative?

_Why this matters: the review verified ~40 zero-caller modules/functions/ports
plus 138 dead translation keys (~700+ lines). Full purge makes every future
change cheaper but touches many files; conservative removes only what blocks
other fixes._

> Recommended: full purge — every item was verified zero-caller against this
> branch, and CI will exist before the purge lands.

**Answered 2026-08-27:** Full purge.

### Performance refactor: in scope or deferred?

_Why this matters: the data layer has O(n²) hot paths on every save
(CODE_REVIEW.md P1/P2). The fix is a Dict-keyed rewrite of `Doc.Data`
internals — meaningful work that only pays off for multi-thousand-card
documents._

> Recommended: keep the ticket, schedule it last, after all correctness fixes
> are green under tests.

**Answered 2026-08-27:** In scope, scheduled last.

## Anything else?

Anything about how you run this instance (single user? collaborators? reverse
proxy?) that the tickets should respect?

>
