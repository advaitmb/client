# 38: a boot against a server without `/me` reports a failure that isn't one

Part of `../map.md`. **Type:** bug · **Status:** resolved

**Blocked by:** none — found by running the app (2026-08-28)

**Covers:** new finding, NOT in CODE_REVIEW.md. Pre-existing, and visible on
every boot of a working install.

**What was wrong:** `doc.js`'s boot asks `/me` when it has no stored account or
an empty local `trees` table, and read `res.ok` as "this is an account":

```js
const res = await fetch("/me");
if (res.ok) { const me = await res.json(); … }
```

`gingko/server` master does not implement `/me`. Its last route is
`app.get('*')`, which serves this app's own `index.html` — so `/me` answers
**200 with HTML**, `res.ok` is true, `res.json()` throws, and every boot logged

```
auto-login failed SyntaxError: Unexpected token '<', "<!DOCTYPE "... is not valid JSON
```

Confirmed live: `curl -o /dev/null -w '%{http_code} %{content_type}' /me` →
`200 text/html; charset=UTF-8`, and the console error appeared on every boot of
the self-hosted app. Nothing was broken by it — Elm boots to the login form,
which is the right answer — but the app accused itself of a failure it did not
have, and the docs listed `/me` in the server contract as if it were required.

## Acceptance criteria

- [x] The answer to `/me` is classified, not trusted: JSON is an account; a 200
      that is not JSON, or a 404, is a server without the endpoint; 401/403 is a
      server that has it and no session here; anything else is reported once.
- [x] A boot against a server with no `/me` logs nothing.
- [x] A `/me` that answers 500 still says so, once, with the status.
- [x] Tested without a server or a browser (ADR-0001 seam 4).
- [x] The docs stop claiming `/me` is part of the required contract.
- [x] Full suite + typecheck + build green.

## Answer

`src/shared/session.js` gains `fetchAccount(fetchFn)` — the probe as a function
of the injected `fetch`, returning one of four statuses (`account`,
`no-endpoint`, `no-session`, `unavailable`) instead of throwing. `doc.js` acts
on the status and warns only for `unavailable`: a self-host without the probe
and a browser nobody has logged in on are both ordinary.

Ten tests in `tests/autologin.test.ts` cover each classification, including the
200-with-HTML answer that started this and a missing `content-type`.

`docs/ARCHITECTURE.md` (§3 checklist, §4.2, §6.1 step 3, the module table) and
`README.md` now say `/me` is optional and what a server without it means.

Verified in headless Chromium against the real `gingko/server`:

| boot | console |
| --- | --- |
| fresh profile, no stored session | *(empty)* — lands on `/signup` |
| logged in, then reloaded | *(empty)* — reopens the document |
| `/me` stubbed to 500 | one line: `auto-login: could not read /me — the server answered 500` |

## Comments

- The endpoint is genuinely optional, so this is deliberately not a "fix the
  server" ticket. Anyone who does add `/me` to their deployment gets the
  auto-login path back with no client change.
- CI green on `selfhost`: `1182ab8` — <https://github.com/advaitmb/client/actions/runs/33156500375>
