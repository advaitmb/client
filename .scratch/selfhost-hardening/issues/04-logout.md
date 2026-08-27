# 04: A working logout path

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C3.

**What to build:** A visible control (decision: in the sidebar's settings/
account area, since the old account menu was removed) lets the user log out:
server session ended (POST /logout on gingko/server), local session blob
cleared, redirect to login. Switching accounts becomes possible.

## Acceptance criteria

- [x] A rendered UI control produces the logout flow (the Elm message chain
      or a TS-side event — whichever is cleaner given the sidebar is a custom
      element).
- [x] The JS dispatch table handles the logout tag (today `LogoutUser` throws
      "Unexpected message from Elm"): clears
      `gingko-session-storage`, calls the server, and completes the redirect.
- [x] Local Dexie data handling on logout is deliberate and documented in the
      ticket (kept for offline safety vs cleared — implementer's call, noted
      in Comments).
- [x] Test at the seam that's practical (e.g. dispatch handler unit test).
- [x] CI green.

## Answer

Landed as `65968dd` on `selfhost` (the whole chain in one commit).

**The chain, end to end**

| Step | Where |
|---|---|
| Logout button in the rail, emits `gw-logout` | `src/ui/sidebar.ts` (`#logout-icon`), pinned to `grid-area: bott-row3` in `src/static/style.css` |
| `gw-logout` → `LogoutRequested` | `Page/App.elm` `viewSidebarElement`, beside the other sidebar events |
| `LogoutRequested` → `Session.logout` | `Page/App.elm` (already existed; it had no producer) |
| `Session.logout` → port tag `LogoutUser` | `Session.elm` / `Outgoing.elm` (unchanged) |
| `LogoutUser` handler | **new** `casesWeb.LogoutUser` in `src/shared/doc.js` |
| POST `/logout`, clear `gingko-session-storage`, teardown, notify | **new** `src/shared/session.js` `logoutUser()` |
| stop syncing as the departing user | **new** `stopSyncing()` in `doc.js`: `ws.close()`, drop the trees/cards/history liveQueries, clear `TREE_ID`/`email` |
| `userLoggedOutMsg` → login page | `Main.UserLoggedOut` (already existed; it was unreachable) |

**Elm-side placement.** The event goes to `Page.App`, not to a new TS-side
flow, because `LogoutRequested → Session.logout` was already written and
correct — C3 was a missing *producer*, not a missing handler. Adding one line
to the sidebar translator (where `gw-new`, `gw-switcher`, `gw-sort` … already
live) is the whole Elm-side cost, and it keeps the session state machine in
Elm, which owns the page the user lands on afterwards.

**The server call is verified, not assumed.** `gingko/server`
`src/index.ts:740` — `app.post('/logout', …)` destroys the express session,
`res.clearCookie("connect.sid").status(200).send()`. No body, no CSRF token,
no auth header. Non-2xx and network errors are logged and stepped over
(see Comments).

**Completing the flow: `userLoggedOutMsg`, not a hard redirect.** Chosen
because on selfhost `doc.js` auto-logs-in against `/me` at boot: a
`location.assign("/login")` would re-run that auto-login, and any server
session that outlived a failed POST would silently log the user back in — at
a URL (`/login` while logged in) that `Main.handleUrlChange` no-ops on. The
port hands control to `Main.UserLoggedOut`, which swaps in `Page.Login` and
`replaceUrl "/login"` in place, with no reload and no second `/me`. It also
means the subscription C3 flagged as unreachable now runs.

**Dexie data is kept.** Reasoning in Comments (acceptance criterion).

**Tests — 12 new, red before green**

- `tests/sidebar.test.ts` (4, ADR-0001 seam 3): the control renders with its
  `#logout-icon` id and "Log out" title; a click reports **exactly one**
  `gw-logout` **and nothing else** (the rail's own click handler toggles the
  document list, so a control that let the click through would log out *and*
  open the list); it is reachable while the list is collapsed (the default
  state); the loading (`static`) state leaves it inert.
- `tests/logout.test.ts` (8, new seam 4 — see below): POST `/logout`; blob
  cleared; Elm told once, after the blob is gone; teardown runs before Elm is
  told; blob still cleared and Elm still told when the server answers 404,
  when the network rejects, and when teardown throws; other local keys
  (`gingko-local-store/<treeId>/settings`) survive.
- ADR-0001 required an amendment before either file existed: seam 2 is *pure*
  JS sync helpers, and the logout sequence is not pure. It now lists a
  **seam 4** — session-level sequences extracted from `doc.js`, observed
  through a faked `fetch`, the real `localStorage`, and the callbacks the port
  layer injects. `CONTEXT.md`'s mirror of the seam list gained the same entry.

**Verification** (after rebasing onto tickets 05 and 10)

| Gate | Result |
|---|---|
| `bun test` | **40/40** across 6 files (28 pre-existing + 12 new) |
| `bun run test:elm` | **12/12** (unchanged by this ticket) |
| `bun run newbuild` | exit 0 |
| `node config-check.js` | exit 0 |
| built bundles | `web/ui.js` has `#logout-icon`/`gw-logout`, `web/elm.js` has `gw-logout` + `LogoutUser` + `userLoggedOutMsg`, `web/doc.js` has `LogoutUser:async`, `method:"POST"` and `gingko-session-storage` |
| CI | run 33066171083 green |

Docs: `ARCHITECTURE.md` §4.2 and §7 describe the round trip (§7's
`LogoutUser` (⚠ no JS handler) marker is gone), and `src/shared/session.js`
has its row in the repository-layout table.

## Comments

- **Dexie/local data on logout: kept, deliberately.** Unsynced card rows are
  the *only* copy of work done offline (`cards` is append-mostly and pushes
  only when the socket is up), so clearing on logout would make logout a
  silent, unrecoverable delete — the worst failure mode this fork can have.
  The same call covers the `tree_snapshots` history, the ImmortalDB backups
  and the `gingko-local-store/<treeId>/settings` entries. Only the session
  blob goes. Consequence, stated plainly: on a shared machine the next person
  to log in still sees the previous account's cached document list, because
  the Dexie database is one global `"db"`, not one per account. That is a
  pre-existing property of the schema, not something logout introduces, and
  the honest fix is at *login* time (where the email being adopted is known)
  or by scoping the database name per account — a separate ticket, not a
  logout-time guess about whether the same user is coming back.
- **Server failures never trap the user.** `logoutUser` steps over a non-2xx
  response, a rejected `fetch`, a `localStorage` that throws, and a throwing
  teardown; `onLoggedOut` runs last and always. A self-host whose server is
  down, unreachable, or older than POST `/logout` must still be able to log
  out of the machine in front of it. **Known limitation:** if the POST fails
  while the *server* session is actually still alive, the user is logged out
  locally but a later page load can auto-login again via `/me`. Surfacing
  that (a toast, or suppressing auto-login after a failed logout) needs a UI
  decision and is left out of this ticket rather than guessed at.
- **Scope disclosure — the dirty guard.** `LogoutRequested` now refuses while
  the document is dirty, alerting instead. It is not in the acceptance
  criteria; it is here because logout discards `Page.App`, an in-progress edit
  lives in the Elm model (normal editing has no autosave — only fullscreen
  does), and the sidebar sits outside `#document`, so clicking it does *not*
  fire `gw-textarea`'s `ClickedOutsideCard` commit. Without the guard the new
  button would eat the paragraph the user was typing. `Main.elm`'s router
  already refuses to navigate away while dirty with the same message, so the
  string moved into `SharedUI.unsavedChangesAlert` and both call it — one copy,
  not two. Escape hatches: save (`mod+enter`) or `esc`.
- **`stopSyncing`.** Without it the pws socket keeps reconnecting and
  re-`rt:join`ing as the user who just left, and the trees liveQuery keeps
  pushing `documentListChanged` into a login page. pws reconnects until
  `close()` is called explicitly, so this is a real leak, not a tidiness
  point. The trees liveQuery had no handle to unsubscribe, so `setUserDbs`
  now keeps one (`treeListSubscription`), mirroring the card/history
  subscriptions. Logout → login again in the same page load therefore ends up
  with exactly one of each subscription.
- **What is *not* covered by a test, and why.** (1) The tag↔handler name match
  (`Outgoing.elm`'s `"LogoutUser"` ⇄ `casesWeb.LogoutUser`) — the exact defect
  C3 describes — cannot be asserted at any seam, because `doc.js` boots the
  app at module load and is not importable. Verified instead by grepping the
  built bundles (table above) and by keeping the sequence in an importable
  module so only the key name lives in the untestable file. (2) The full UI
  flow (click → server → login page) needs a browser and a running server;
  neither exists in this environment. The seams cover both ends of it.
- **Red-before-green transcript.** Sidebar: with the tests written and no
  control, 3 of 4 failed (`#logout-icon` missing → no title, no event); the
  4th ("the loading state leaves logout inert") passed vacuously, as a guard
  should, and became meaningful once the control existed. Logout sequence:
  first `Cannot find module '../src/shared/session'` (8 fail), then a
  deliberately minimal implementation (no `try`/`catch`) left exactly the two
  hardening tests red — "logs out locally when the server cannot be reached"
  and "logs out even if tearing down the socket throws" — which is what drove
  the best-effort structure. The 404 case passed under the minimal version
  (nothing read `response.ok` yet), so it is a guard, not a driver.
- **Adjacent, left alone:** `ToggledAccountMenu` / `SidebarMenuState.Account`
  in `Page/App.elm` (and `#account-menu` / `#account-dropdown` in
  `style.css`) are still producer-less dead code from the removed account
  menu. Logout deliberately did **not** revive a menu, so they belong to the
  dead-code tickets (21/22/20), not here.
