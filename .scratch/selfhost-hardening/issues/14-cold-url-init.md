# 14: Cold-loading any URL runs that page's init commands

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E4.

**What to build:** Pasting any app URL into a fresh tab boots the page it
names. Today `Main.init` discards the initial page's `Cmd`, and unhandled URL
shapes return `Cmd.none` — a cold-loaded two-segment doc URL sits on a spinner
until an unrelated push redirects to the wrong (most-recently-updated)
document.

## Acceptance criteria

- [x] `Main.init` executes the initial page's commands.
- [x] Every URL shape either routes somewhere deliberate or lands on a
      not-found/redirect with its commands run — no dead-end spinner.
- [x] Test the route dispatch at a practical seam (extract the URL→page
      decision if needed to make it testable).
- [x] CI green.

## Answer

**E4 was two halves of one hole: a decision that could answer "nothing", and a
boot path that threw the answer away.** `Main.init` built a page from the
session alone, discarded its `Cmd` (`( initModel, _ ) = …`), and handed the
model to `handleUrlChange` — which then re-initialized a page for most URL
shapes, so the discard was invisible *except* where `handleUrlChange` returned
`( model, Cmd.none )`. There the app kept the page `init` had built, with none
of its commands: `Page.App` with `loading = True`, no `LoadDocument`, no
`GetDocumentList`. A spinner with nothing on the way. It ended only when an
unrelated `documentListChanged` push arrived and `ReceivedDocuments` — seeing
`Empty` + a non-empty list — redirected to the *most recently updated*
document, not the one in the URL.

**The decision is now a total function, in `Route`.** `Route.loggedInLanding`
and `Route.guestLanding` map (session kind, path) to a **landing**: the page to
initialize, plus an optional `Route` to correct the address bar to. They are
pure, so they are testable — which is the whole reason the decision moved out
of `Main`, where every page `Model` carries a `Nav.Key` no test can make
(ADR-0001 **seam 8**, recorded). `Main` keeps only the mechanical half:
`routeUrl` initializes the page a landing names and batches its commands with
the correction, and **both `init` and `handleUrlChange` go through it**. There
is no longer a code path that produces a page without its commands, and none
that answers "stay where you are" — the type has no such case.

The `Route` module now owns both directions of the URL mapping (it only built
URLs before). That is deliberate: `toString` and the patterns are two halves of
one mapping, and `tests/RouteTest.elm` round-trips every `Route` the app builds
back to the page it names — which is what keeps the `404-not-found` segment and
the template names from drifting apart.

**Every URL shape, before → after** (logged in, unless said otherwise):

| URL | Before | After |
|---|---|---|
| `/` | App home | unchanged |
| `/new` | `Page.DocNew` | unchanged |
| `/import/<known>` | `Page.Import` | unchanged |
| `/import/<unknown>` | App home | unchanged |
| `/<dbName>` | App with that doc | unchanged |
| `/<dbName>/404-not-found` | not-found screen, `Cmd.none` | not-found screen **+ `GetDocumentList`** |
| `/<dbName>/<title>` | **`Cmd.none` — dead spinner** | App with `<dbName>`, loaded (never created) |
| 3+ segments | **`Cmd.none` — dead spinner** | not-found screen + `GetDocumentList` |
| `/login`, `/signup` | page kept, `pushUrl /` | App home, URL **replaced** with `/` |
| guest `/` | Signup, URL replaced `/signup` | unchanged |
| guest `/login`, `/signup` | Login / Signup form | unchanged |
| guest, mid-login `/` and `/import/<t>` | App home / Import with the new session | unchanged |
| guest, anything else (`/new`, `/<dbName>`, `/<dbName>/<title>`, `/import/<t>` with no login in progress, deeper paths) | **`Cmd.none`** — login form sitting at a document's URL | Login form, URL corrected to `/login` |

Three of those need saying out loud:

- **`Page.App.notFound` now sends `GetDocumentList`.** It is the screen that
  says "check your list of documents in the sidebar", and on a cold load it is
  the *first* page the app initializes — nothing else had asked for the list,
  so the sidebar it points at was empty. Same defect, same fix.
- **`/login` while logged in redirects by `Replace`, not `Push`.** A pushed
  redirect leaves `/login` in the history, so Back lands on it and is pushed
  forward again. Corrections are `Replace` by construction now — the landing
  type has no way to express a pushed one. (`Route.pushUrl` stays, for the real
  navigations in `Page.App`/`Page.Login`/`Doc.List`.)
- **A completed login routes as the user it signed in.** The auth pages keep a
  `transition : Maybe LoggedIn` while their own session is still a guest one;
  `handleUrlChange` promotes it before routing. That is what the old guest
  branch did for exactly two paths (`/` and `/import/<t>`); doing it once, for
  all paths, is what let the guest fallthrough become "the login form" without
  stranding a mid-login redirect there. The old `[]`-with-a-transition guard on
  the logged-in side (`if loginInProgress model == Nothing`) was unreachable —
  both auth pages' `toSession` is always `GuestSession` — and is gone.

**Pattern order preserved**, as the review noted it had to be: `/new` and
`/import/<t>` before `/<dbName>`, and `/<dbName>/404-not-found` before
`/<dbName>/<title>`.

**Tests:** 23 new in `tests/RouteTest.elm` at seam 8 (elm-test 52 → 75; `bun
test` 58, untouched). Full run: `bun run test:elm` 75 pass, `bun test` 58 pass,
`bun run newbuild` exit 0, `bun run config-check` exit 0.

## Comments

- **Red-before-green transcript.** Slice 1 (the reported bug, cold
  `/<dbName>/<title>`): `NAMING ERROR — I cannot find a Route.Landing type`,
  then green on the logged-in map. Slice 2 (the guest fallthrough):
  `NAMING ERROR — The Route module does not expose a LoginForm variant`, then
  green. Elm's exhaustiveness is why those two slices each arrived as a whole
  `case`: a half-written one does not compile, so the deep-URL and
  correct-the-address-bar cases went green with the slice that forced the
  table. The remaining 18 tests are pins written after, and they are pins on
  purpose — the shapes that already worked, plus the round trip.
- **What is *not* tested, and why.** `Main.init` itself. `Browser.application`
  hands `init` a `Nav.Key`, which only it can make, so the "commands are not
  discarded" half of this ticket is structural, not asserted: `init` has no
  local page to discard a `Cmd` from any more — it calls the same `routeUrl`
  every URL change calls. The type is doing the work a test cannot.
- **Two inits on a corrected URL.** A landing that corrects the address bar
  initializes its page *and* replaces the URL, and the replacement re-enters
  `handleUrlChange`, which initializes the same page again. This is not new —
  guest `/` → Signup has always worked that way — and it is the safe direction:
  the page is on screen with its commands run whether or not the navigation
  fires. The alternative (page-less redirect) is what E4 was.
- **Out of scope, left alone.** `Main`'s unused `Dict` import and the
  `WebSessionData` alias, and the `SettingsChanged` dead `Msg` — ticket 21.
  `docs/CODE_REVIEW.md` keeps E4's text as the historical catalog; no ticket
  annotates it.
