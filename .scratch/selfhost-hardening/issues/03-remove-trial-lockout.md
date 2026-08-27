# 03: Remove the 14-day trial lockout and payments machinery

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C2 · Decision: ADR-0002.

**What to build:** A self-hosted user is never blocked from editing by account
age. The whole payments/trial ring is removed, not bypassed: trial block
derivation, `PaymentStatus`/`daysLeft`, the upgrade modal message ring,
`Route.Upgrade`, the checkout/`FlashPrice` port tags and JS handlers, and the
`elm-money` dependency.

## Acceptance criteria

- [ ] Editing works regardless of signup date or stored trial expiry; stale
      persisted expiry values in localStorage are ignored or migrated away.
- [ ] Test: a session decoded with no payment status is never blocked.
- [ ] `setBlock`'s only remaining uses are functional (history view).
- [ ] Elm compiles with the payments ring gone; `elm.json` no longer pins
      `Chadtech/elm-money`; CI green.
