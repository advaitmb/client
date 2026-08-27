# 03: Remove the 14-day trial lockout and payments machinery

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C2 · Decision: ADR-0002.

**What to build:** A self-hosted user is never blocked from editing by account
age. The whole payments/trial ring is removed, not bypassed: trial block
derivation, `PaymentStatus`/`daysLeft`, the upgrade modal message ring,
`Route.Upgrade`, the checkout/`FlashPrice` port tags and JS handlers, and the
`elm-money` dependency.

## Acceptance criteria

- [x] Editing works regardless of signup date or stored trial expiry; stale
      persisted expiry values in localStorage are ignored or migrated away.
- [x] Test: a session decoded with no payment status is never blocked.
- [x] `setBlock`'s only remaining uses are functional (history view).
- [x] Elm compiles with the payments ring gone; `elm.json` no longer pins
      `Chadtech/elm-money`; CI green.

## Answer

The ring is gone, not bypassed (ADR-0002). Removed:

- **`Page/App.elm`** — the trial derivation inside `setBlock` (which is now a
  plain "set or clear the block" on the doc model), `ModalState.UpgradeModal`,
  the `ToggledUpgradeModal` / `UpgradeModalMsg` (incl. `CheckoutClicked`,
  `PlanChanged`→`FlashPrice`) handlers, the `UpgradeModal` view branch, and
  the `import Upgrade` / `PaymentStatus(..)` imports. `setBlock`'s four
  remaining call sites are all history-view (open, close, cancel-history ×2);
  the three non-functional `setBlock Nothing` calls (doc init ×2 — a fresh
  `Page.Doc.init` already has `block = Nothing` — and `SettingsChanged`) are
  gone. Keeping the `SettingsChanged` one would have been a new bug: with the
  trial gone it would *clear* the history block whenever a settings sync
  arrived mid-history-view.
- **`Session.elm`** — `PaymentStatus`, `Trial`/`Customer`, `daysLeft`,
  `add14days`, `paymentStatus`, `upgradeModel`, `updateUpgrade`,
  `decodePaymentStatus`, `encodePaymentStatus`, the `upgradeModel`/
  `paymentStatus` fields of `UserData`, and every `optional "paymentStatus"`
  in the three decoders (`decoderLoggedIn`, `sync`, `responseDecoder`).
  `sync` lost its now-unused `currentTime` parameter (it existed only to seed
  the 14-day default).
- **`Upgrade.elm`** — deleted (81 lines); nothing else imported it.
- **`Route.elm`** — `Upgrade Bool` and its `/upgrade/success|cancelled`
  `toString` branch. Nothing constructed or parsed it.
- **`Outgoing.elm`** — the `FlashPrice` and `CheckoutButtonClicked` tags and
  their `dataToSend` branches; **`doc.js`** — the `FlashPrice` handler (it
  null-dereffed `#price-amount`, an element this fork no longer renders).
  There was no `CheckoutButtonClicked` JS handler to remove.
- **`Translation.elm`** — the `Upgrade`, `DaysLeft`, `TrialExpired`,
  `ManageSubscription` ids and their strings (`WordOfMouthCTA1/2` kept: a
  testimonial CTA, not payments — ticket 21's call).
- **`elm.json`** — the `Chadtech/elm-money` direct pin (zero imports).
- **`docs/ARCHITECTURE.md`** — §4.2's `UserData` field list no longer claims
  a `paymentStatus`.

**Stale localStorage is inert both ways.** Ignored: no decoder reads
`paymentStatus` any more, so a leftover value — including an unparseable one —
cannot affect the decode. Migrated away: `encodeUserData` no longer writes the
field, and `doc.js`'s `StoreUser` *replaces* the whole
`localStorage["gingko-session-storage"]` object, so the stale key disappears
on the next store (login, settings change).

**TDD (seam 1, `Session.decode`).** `tests/SessionTest.elm`, red first against
the old behavior:

```
✗ a session with no payment status has no trial clock      Just 14  ≠ Nothing
✗ a stale persisted trial expiry leaves no trial clock  Just -19676 ≠ Nothing
✗ an unparseable stale payment status is ignored, not fatal
      expected a logged-in session, got a guest session
```

The first two used `Session.daysLeft`, which the removal deletes, so they were
re-pinned as decode-tolerance tests (as the ticket allows) once the concept
was gone. The third red is a bug this removal also fixes: `optional` fails the
*whole* pipeline when a present field's inner decoder fails, so a
`paymentStatus` string that `decodePaymentStatus` couldn't parse (e.g. written
by a build with a different encoding) made `decoderLoggedIn` fail and silently
demoted the user to a guest session — i.e. logged them out. Final suite: 4
tests, all green.

**Verification** (all local, this worktree):

| check | result |
|---|---|
| `bun run test:elm` | 7 passed / 0 failed (3 DataTest + 4 SessionTest) |
| `bun test` | 7 passed / 0 failed, 2 files |
| `bun run newbuild` | Build succeeded; `elm make --optimize` clean |
| `node config-check.js` | exit 0 |
| grep `PaymentStatus|paymentStatus|daysLeft|Upgrade|upgradeModel|updateUpgrade|FlashPrice|CheckoutButtonClicked|CheckoutClicked|elm-money|TrialExpired` over `src/` + `elm.json` | 0 hits (only hits repo-wide are the deliberate stale-field fixtures in `tests/SessionTest.elm`) |
| grep `-i trial\|stripe` over built `web/elm.js`, `web/doc.js` | 0 hits |
| CI on `selfhost` | run [33064042736](https://github.com/advaitmb/client/actions/runs/33064042736) green at `c72d409` |

## Comments

- **Left behind on purpose (scope):** `src/static/style.css` still carries the
  payments modal's dead selectors — `#upgrade-cta`, `#upgrade-button`,
  `#upgrade-trial-info`, `#upgrade-modal`, `#upgrade-copy`,
  `#upgrade-checkout`, `#pwyw*`, `#price-display`, `#price-amount`,
  `.payment-button`, and the `flash-2` keyframes the deleted `FlashPrice`
  handler used. They style markup this fork never renders. Neither 21 (Elm)
  nor 22 (JS/TS) covers CSS, so this needs a home — suggest folding dead CSS
  into 20 or 22.
- **Contract change worth knowing:** `decoderLoggedIn` no longer `required`s
  `currentTime` (it was decoded only to seed the trial expiry). `GlobalData`
  still requires it from the same flags object, so the app's clock is
  unchanged; the effect is that stored session data missing `currentTime` no
  longer demotes the user to a guest session.
- `Session.sync`'s signature changed to `Dec.Value -> LoggedIn -> LoggedIn`
  (one call site, `App.elm`'s `SettingsChanged`).
- Not touched: `docs/CODE_REVIEW.md` (shared catalog — C2 is now fixed in
  code; whoever does the final docs pass should mark it).
