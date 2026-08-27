# 19: Auth pages cleanup

Part of `../map.md`. **Type:** task · **Status:** resolved

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

- [x] Login submits with a short password and shows exactly one error when
      blank (validation tests).
- [x] Labels focus their inputs (a11y ids match).
- [x] Forgot-password resolved per owner's answer; no dead route links remain.
- [x] Mailing-list plumbing removed.
- [x] CI green.

## Answer

Four findings, one theme: **the auth pages were still speaking for a hosted
service** — turning users away with rules it did not own, pointing at a route
and an inbox that do not exist here, and naming a domain this fork is not.

**A1 — the forgot-password link is gone, not implemented.** Per the owner's
decision there are no password-reset emails, so `Page.Login`'s
`a [ class "forgot-password", href "/forgot-password" ]` is removed along with
everything that existed to serve it: `Session.requestForgotPassword` and
`Session.requestResetPassword` (zero callers — `Main.handleUrlChange` never had
a branch for either route, so the link fell through the guest no-op), and the
`a.forgot-password` rule in `src/static/style.css`, whose only element just
left. **This can come back** when the deployment can send email: the two
request functions were four lines each over `/forgot-password` and
`/reset-password`, and `responseDecoder` — which they shared with login — is
untouched and still exposed. The server side is the hard half, not this.

**A2 — login stopped enforcing a password policy it does not own.** The login
form dropped `ifTrue (String.length password < 7)`. Whether a password is
acceptable is the server's answer: any account whose password predates the
current rules — or a self-hoster's own seeded account — could never log in
through this form, and no wording on the login page can fix that. The rule
stays on signup, which is where a password is *chosen* (and where the field
label already says "7+ characters").

That also ended the stacking: because `Validate.all` ran a length rule *and*
`ifBlank` over the same field, a blank password answered with two messages
("Please enter a password." **and** "Password should be 7 characters or
more.") — two problems where the user has one. Blankness is now the only
password rule, and the two email rules stay under `firstError`, so each field
answers at most once.

The validator became this ticket's seam. It is now
`Page.Login.credentialsValidator`, extensible in its subject
(`{ a | email : String, password : String }`) so that a test can validate a
bare record: a page `Model` carries a `Nav.Key` no test can make, and testing
through the view would have pinned the markup instead of the rule. `update`
runs the very same value, so there is no second code path to drift.

**A3 — the signup labels point at their inputs.** `for "singup-email"` /
`for "singup-password"` → `signup-email` / `signup-password`, matching the ids
the inputs have always had. Clicking either label now focuses its field
(previously the label was associated with nothing, which also cost screen
readers the accessible name).

**A4 — the copy is true for a self-hosted server.**

- The 401 said "Email or Password was incorrect.\n\nNOTE: that this is
  separate from existing gingkoapp.com accounts." → just the first sentence.
- Signup's 409 said "Username already exists." on a form whose only account
  name is an email address → "An account with that email already exists.
  Login?" (`FieldError.UsernameExists` renamed `EmailTaken` to match).
- The mailing-list opt-in is gone end to end: the checkbox and its label,
  `Model.didOptIn`, `Msg.ToggledOptIn` and its handler, `requestSignup`'s
  `didOptIn` parameter, and the `subscribed` field in the POST body.
- The "arrived from the old site" notice (shown when `Session.fromLegacy`) no
  longer names gingkoapp.com: "This server keeps its own accounts, **separate**
  from the site you came from." See Comments for why the `fromLegacy` ring
  itself stayed.

**Tests — 6 new, at a new seam.** `tests/AuthTest.elm`: four for
`credentialsValidator` (a 6-character password submits; a blank password
answers exactly once; a blank form asks for each field once; a non-email is
still refused) and two for `Session.signupBody` (the body carries `email` and
`password` **and nothing else**, and carries what the user typed). Red first,
against the extracted-but-unfixed seams: 4 failures, each for the right reason
— `Err [(Password,"Password should be 7 characters or more.")]` where `Ok ()`
was expected, the two-message blank case, and
`Ok ["email","password","subscribed"]`. ADR-0001 gains **seam 7** (auth forms,
Elm, pure) — 6 was taken by ticket 20's build-time gates during the rebase —
mirrored in `CONTEXT.md`'s seam list, which needed ticket 20's seam 6 added
alongside it to stay a faithful summary of the ADR. The label fix has no seam —
it is a view attribute, verified by inspection (every `for` on both pages now
matches an `id` in the same form) and in the built bundle.

Local: `bun run test:elm` 35/35 before the rebase (was 29), 42/42 after it
picked up tickets 11 and 20; `bun test` 51/51, unchanged by this ticket;
`bun run newbuild` exit 0, `node config-check.js` exit 0. All re-run after the
rebase. CI green on `selfhost`: run 33070676955 (`6ba6ad1`, both commits). Grep-zero over
`src/`: `forgot-password`, `requestForgotPassword`, `requestResetPassword`,
`singup`, `subscribed`, `gingkoapp.com` — no matches; same six over the built
`web/elm.js` and `web/style.css` — no matches.

## Comments

- **The server never used `subscribed`.** Checked before removing it:
  `gingko/server`'s `src/index.ts` signup handler does
  `let didSubscribe = req.body.subscribed;` and that variable has no second
  occurrence in the repo (the handler's own comment says welcome emails and
  newsletters are not implemented). So an absent field changes nothing
  server-side — it was write-only on both ends.
- **`Session.fromLegacy` stayed alive on purpose.** Only its wording was
  SaaS-era. The mechanism (`doc.js` sets it from
  `document.referrer.startsWith(config.LEGACY_URL)`) is exactly the "you came
  here from the old install" hint a self-hoster migrating a deployment wants,
  and it is still read by `Page.Login`, so nothing here is dead. Removing the
  ring would also have meant dropping `LEGACY_URL` from `config-example.js` and
  editing ticket 01's `tests/config-check.test.ts`, which is ticket 20's file,
  not this one's.
- **Judgement call left standing:** `requestLogin` still builds its body
  inline while `requestSignup` goes through `signupBody`. The two bodies are
  identical today, so a shared `credentialsBody` was tempting — but this
  ticket's finding is about what *signup* sends, and a login-shaped body is not
  something any test here pins. Merging them would make the seam's name stop
  saying "signup" for no requirement.
- Login's short-password errors used to save a round trip. They no longer do:
  a one-character password now reaches the server and comes back 401. That is
  the intended trade — the server is the only thing that knows.
- `docs/CODE_REVIEW.md` is left as the historical record (no ticket edits it);
  A1–A4 are answered here.
