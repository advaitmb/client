# 09: Renames/deletes made offline are re-sent on reconnect

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D6.

**What to build:** A document rename or delete performed while the socket is
down reaches the server as soon as the connection returns — not "whenever an
unrelated tree-table change or reload happens to retrigger the liveQuery".

## Acceptance criteria

- [x] On socket (re)open, unsynced tree-metadata rows are sent (queue the
      `trees` message, or re-send unsynced rows in `onopen` alongside the
      existing queue drain and `rt:join`).
- [x] Test at a practical seam (extracted resend logic, or an integration
      test with a fake socket).
- [x] CI green.

## Answer

Landed as `570af59` (the fix), `e6288bd` (docs and the seam list) and
`c1595b1` (review pass) on `selfhost`; claim `3f357ed`.

**The defect.** The trees liveQuery is local — Dexie emits whether or not
there is a connection — but it sent with `wsSend('trees', unsyncedTrees,
false)`, and that `false` means "drop it if the socket is down". `ws.onopen`
drained the explicit send queue and re-sent `rt:join`, and asked nothing about
metadata. So a rename or a delete made offline sat unsynced until an unrelated
tree-table change or a reload happened to retrigger the liveQuery. There is no
second channel that could have covered it: cards travel as deltas, and a
rename or a delete produces no card.

**The fix.** Both senders of the `trees` message now live in
`src/shared/metadata.js` (ADR-0001 seam 4), which keeps the trees table as the
liveQuery last emitted it and derives the message from it at send time:

| Event | doc.js | metadata.js |
|---|---|---|
| the trees liveQuery emits | `metadataSync.treesChanged(trees)` | remember the rows; send the unsynced ones if the socket is up |
| the socket opens | `metadataSync.socketOpened()` in `ws.onopen`, after the queue drain | send the unsynced ones (this is D6) |
| logout | `metadataSync.stop()` in `stopSyncing` | inert for good |

Injected: `send(tag, data)` (`wsSend(…, false)`) and `isOpen()`
(`ws.readyState === ws.OPEN`, asked at send time so the module cannot come to
disagree with the socket about whether it is up). One instance per session,
created in `setUserDbs` before `initWebSocket`, so logging in again builds a
new one and a reconnect can never push the rows of the account that left.
`doc.js` lost the inline filter/`_.omit` projection, and the send queue is
untouched.

**Why not queue the message** (the ticket's other option), and why not query
Dexie in `onopen` either: both can put stale state on the wire *after* newer
state. Reasoning in Comments; it is also the module header's "WHY A RECONNECT
RE-DERIVES THE STATE" section and ARCHITECTURE §6.3.

**Tests — 10 at seam 4** (`tests/metadata.test.ts`), driven by the two events
against a fake socket (a mutable `socketOpen` flag) and observed through the
messages the module asks to be sent:

- the D6 case: offline rename → reconnect → **exactly one** `trees` message
  carrying the renamed row;
- the delete half of D6: a `deletedAt` set offline goes out the same way;
- the payload is the unsynced rows without `synced`/`collaborators` — the same
  projection the liveQuery path sends, since it is now the same code;
- two renames offline are **one** message carrying the second name;
- nothing while the socket is down; nothing when every row is acknowledged;
  nothing after `stop()`, on either event;
- a connection that opens before the liveQuery's first emission sends nothing,
  and that emission still goes out.

**Verification** (rebased onto `selfhost` with tickets 17 and 31 in flight)

| Gate | Result |
|---|---|
| `bun test` | **98/98** across 12 files at `c1595b1` (88 before + 10); **108/108** across 13 files once ticket 17's suite rebased in |
| `bun run test:elm` | **139/139**, then **154/154** — untouched by this ticket either way |
| `bun run newbuild` | exit 0 |
| `node config-check.js` | exit 0 |
| built bundle | `web/doc.js` carries `createMetadataSync`, `treesChanged`, `socketOpened` |
| CI | all green on `selfhost`: `570af59` (run 33088504485), `c1595b1` (33088917522), `a4ed2f2` (33089126136) |

Docs: `ARCHITECTURE.md` §2 (module table), §6.1 (bootstrap), §6.3 (the
reconnect list and the queue-vs-state rule) and §8 (test inventory);
ADR-0001 seam 4 and `CONTEXT.md`'s mirror of it; `CONTEXT.md` gains
**document metadata** as a term.

## Comments

- **Why the reconnect re-derives the state instead of queueing the message.**
  Queueing (`wsSend('trees', …, true)`) is the smaller diff and it is wrong in
  a way that matters: the queue would hold one message per liveQuery emission,
  and every one but the last is a state the document has already left. An
  offline session that renames a document twice would push the first name and
  then the second. Those rows are not invalid — each carries its own
  `updatedAt` — but they are stale and they arrive as news, so a server that
  takes the last message it received at face value answers with the *older*
  name in a `trees` message, which `doc.js` bulk-puts straight over the newer
  row in Dexie. It also grows without bound while the connection is away. The
  queue is right for messages that are **events** (`pull`, `pullHistoryMeta`,
  `rt:join`): those are requests, and replaying them verbatim is exactly what
  they need. Metadata is **state**.
- **Why not a fresh Dexie read in `onopen` either** — the ticket's first
  option, and the one I expected to take. `await db.trees.toArray()` is
  asynchronous, so a rename that commits while the read is in flight emits and
  is sent (the socket is up by then), and then the read answers with the state
  *before* that rename and sends it: newer state on the wire first, older
  second, which is the very double-send the ticket asks the design to make
  impossible. Reading what the liveQuery last emitted takes no turn of the
  event loop, so there is no window. The two senders being the same code makes
  the ordering argument total: every `trees` message is drawn from the same
  monotonic sequence of emissions (a newer emission replaces an older one, and
  every send reads the variable synchronously), so no send can carry state
  older than one already sent, and a reconnect sends at most one message
  however long it was away.
- **Nothing is lost by not reading the database.** The one thing the cached
  emission is behind is a write whose emission has not arrived yet — and that
  emission is what sends it, the socket being up by then. A reconnect that
  overlaps such a write therefore sends the pre-write state and the emission
  sends the post-write state, in that order, which is the correct order.
- **Interaction with ticket 04's `stopSyncing` (asked for by the ticket).**
  `stop()` is permanent and clears the cached rows; `stopSyncing` calls it
  beside the three `unsubscribe()`s. Two other gates already stood between a
  post-logout reconnect and the wire — `stopSyncing` nulls `ws`, which
  `isOpen()` and `wsSend` both check, and pws stops reconnecting once closed
  explicitly — but neither is a property of *this* module, and the ticket asks
  for "nothing sent after logout/teardown" as a pinned behavior, so the module
  owns one. A login → logout → login in the same page load ends with exactly
  one live instance, mirroring what ticket 04 did for the subscriptions.
- **Red-first transcript.** Three of the ten drove the implementation. (1) The
  D6 test with no module: `Cannot find module '../src/shared/metadata'`. (2)
  The projection test against a deliberately minimal `latest.filter(t =>
  !t.synced)`: red on `+ "collaborators": []` and `+ "synced": false`, which is
  what moved the `_.omit` projection into the module rather than leaving it
  duplicated in the liveQuery. (3) Both logout tests: `TypeError: sync.stop is
  not a function`. The other six are guards, green on the implementation those
  three produced — including "two renames offline are one message", which is
  green *by construction* in this design and red in the queueing design it
  rules out. That is the point of keeping it: it fails the moment someone
  replaces the cache with a backlog.
- **Not covered by a test, and why.** Whether `ws.onopen` calls
  `socketOpened()` at all, and whether the liveQuery calls `treesChanged` —
  `doc.js` boots the app at module load and is not importable, the same limit
  seams 4 and 10 already record. Verified by inspection of the four-line diff
  and by the built bundle carrying all three method names. The pws contract
  that `onopen` fires on every reconnect is what the pre-existing queue drain
  already depends on.
- **Scope disclosure.** The liveQuery's *other* half (`documentListChanged` to
  Elm, the `firstLoad`/`loadingDocs` gate) is untouched, as is the send queue.
  Adjacent and deliberately left alone: `setUserDbs` can be called twice
  without a logout (`StoreUser`), and `initWebSocket` then builds a second pws
  without closing the first — a pre-existing leak that predates this ticket and
  belongs with 23. The new instance-per-session at least means the second
  socket's `onopen` drives the current session's metadata, not a stale one.
- **`docs/CODE_REVIEW.md`** left as the catalog as found, matching tickets
  02–16.
