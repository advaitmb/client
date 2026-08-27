# 19: Auth pages cleanup

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01 (resolved) · **Owner decided (2026-08-27):** no
password-reset emails — remove the forgot-password link and its dead plumbing.

**Covers:** CODE_REVIEW.md A1, A2, A3, A4.

**What to build:** The login and signup pages behave like a self-hosted app's:
no dead "Forgot your Password?" link (or a real reset flow, per the owner's
answer); login accepts any password the server accepts (no client-side
7-character minimum, no stacked contradictory errors on blank); signup labels
point at correctly spelled input ids; SaaS-era copy is gone (gingkoapp.com
migration warning, "Username already exists" for an email field, the
mailing-list opt-in and its `subscribed` POST field).

## Acceptance criteria

- [ ] Login submits with a short password and shows exactly one error when
      blank (validation tests).
- [ ] Labels focus their inputs (a11y ids match).
- [ ] Forgot-password resolved per owner's answer; no dead route links remain.
- [ ] Mailing-list plumbing removed.
- [ ] CI green.
