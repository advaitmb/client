# ADR-0002: Remove the trial/payments machinery entirely

**Status:** accepted · **Date:** 2026-08-27

## Decision

This is a self-hosted fork with no billing. Remove, rather than bypass, the
entire trial/payments ring: the 14-day trial block derivation in
`Page.App.setBlock`, `PaymentStatus`/`daysLeft` in `Session`, the
`UpgradeModal`/`ToggledUpgradeModal`/`CheckoutClicked` message ring,
`Route.Upgrade`, the `CheckoutButtonClicked`/`FlashPrice` outgoing tags and
their JS handlers, and the `Chadtech/elm-money` dependency.

A logged-in user is never blocked from editing by account age. The only
legitimate uses of `setBlock` that remain are functional ones (history view).

## Context

Nothing on this branch supplies a `paymentStatus`, so decoders default every
user to a 14-day trial whose expiry is persisted; the upgrade modal that
would unblock it is unreachable dead code. Every self-hosted user is
permanently locked out of editing two weeks after signup (CODE_REVIEW.md C2).
Bypassing (e.g. defaulting to `Customer`) would keep dead machinery alive;
removal is the decision.
