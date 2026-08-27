# 18: Surface swallowed errors through the app's toast pattern

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E16.

**What to build:** Failures the user needs to know about stop dying in
silence: failed DOCX export shows a toast; an invalid JSON import file shows a
toast; malformed card/push-ack/history payloads surface an error instead of
silently freezing or no-oping; a failed `bulkPut` of pulled cards (lost
incoming sync data!) is reported, not `console.log`ged; clipboard failures are
handled consistently. Use the existing toast machinery — this ticket adds no
new UI concepts.

## Acceptance criteria

- [x] Each site listed in E16 either surfaces a user-visible error or has a
      written-down reason (in Comments) why silence is correct there.
- [x] The `ws.onmessage` catch-all no longer flattens every handler error to
      console noise: sync-data write failures produce a visible error state.
- [x] Tests where a seam allows (decoder failure → error branch).
- [x] CI green.

## Answer

Every one of the seven E16 sites now surfaces. None needed a
silence-is-correct exemption; the judgement calls are all *inside* the
websocket policy, which is per message type and written down in
`src/shared/ws-errors.js`.

**The three `Doc/Data.elm` payloads answered a payload they could not read
the same way they answer "nothing changed".** That is the whole bug: `Nothing`
from `cardDataReceived` and the model handed back from `historyReceived` are
what "no news" looks like, so a malformed payload froze the editor or emptied
the history view with nothing said. Each function now carries the decoder's
reason out:

- `cardDataReceived : … -> Result String (Maybe { … })`. Three answers, because
  there are three things to say: `Err reason` (unreadable), `Ok Nothing`
  (decoded, changed nothing — the common case, since every write to the `cards`
  table fires the liveQuery including this client's own echo), `Ok (Just …)`.
  Collapsing the first two is what hid E16, and a test pins them apart.
- `pushOkHandler : … -> Result String Outgoing.Msg`. Its `Nothing` was only
  ever the failure, so no `Maybe` was needed. The reason names the stamps that
  came in, since they are the only evidence of what the server is saying.
- `historyReceived : … -> Result String Model`.

`Page.App` turns each into a **persistent** error toast plus a console line.
Persistent because none of the three clears itself: the next liveQuery emission
carries the same unreadable rows. `AddToast Persistent` adds with
`Toast.addUnique`, so that is one toast, not a stack — which is why the toast
text is **fixed per site** and the decoder's reason goes to the console
(`ConsoleLogRequested`) instead of into the message.

That split turned out to be load-bearing for a second reason: `Doc.UI.viewToast`
renders a toast's `message` through `Markdown.Parser` and falls back to the
literal string `<parse error>`. Interpolating a filename, a URL or a server
response body into a toast could therefore come back as emphasis, as a heading,
or as that fallback. `httpErrorToString` is deliberately server-text-free for
the same reason, with `httpErrorDetail` carrying the URL/body to the console
(`Debug.toString` is not available — the release build runs `--optimize`).

**A push acknowledgement that does not parse is no longer treated as a
successful sync.** The `PushOk` branch clears `errorState` and shows "Sync
successful"; doing that in the same update that reports an unreadable ack would
have shown both at once. The `Err` branch now leaves the error state exactly as
it was.

**`ws.onmessage`'s catch-all is judged per message type**, via
`src/shared/ws-errors.js` — an allowlist of the benign types, so a case added to
the switch later is loud until somebody classifies it (a list of the *serious*
types would let a new case be silent by default, which is how E16 happened).
Benign, with the reason each: `user` (a settings merge; the document is
untouched and the server re-sends), `rt`/`rt:users` (collaborator presence — the
highest-frequency messages there are, and the next one replaces what a failed
one lost), `pushOk` (the rows stay unsynced and go out again, and Elm now
reports an ack *it* cannot read), `pushError` (that path counts failures and
raises its own `ErrorAlert` on the fourth). Everything else persists something
(`cards`, `cardsConflict`, `trees`, `treesOk`, `history`, `historyMeta`), asks
for something that persists (`doPull` — a pull that never goes out leaves this
client silently behind), or removes something (`removedFrom`), and goes to the
user through the existing `ErrorAlert` port. `cards` is the E16 case by name:
a failed `bulkPut` there is incoming sync data that never reached this device.

Two adjacent swallows in the same handler, both of which destroyed the evidence
rather than merely hiding it:

- `JSON.parse(e.data)` sat **outside** the try, so a frame that was not JSON
  rejected the async handler with nobody listening. It is inside now, reported
  as an unknown-type failure (no type to judge by ⇒ surface).
- `historyMeta`'s inner catch read `e.failures` unguarded, so an error that was
  not a Dexie `BulkError` threw a `TypeError` *from inside the catch* and lost
  the real reason; and `[].every(…)` is `true`, so an empty `failures` list read
  as "all benign". Both guarded.

**All three clipboard call sites go through `src/shared/clipboard.js`.** The
paste path caught only errors whose `message` contained `"denied"` — reading
that message unguarded, so an error without one threw a second time inside its
own catch — while both copy paths (`CopyToClipboard`, `CopyCurrentSubtree`)
attached no handler at all, leaving a refused copy as an unhandled rejection
behind a flash animation that said it had worked. `clipboardErrorMessage` is
total over whatever was thrown, `undefined` included, and keeps the
permission-denied padlock advice (recognized by `NotAllowedError` *and* by
wording, since only the wording check existed before).

These stay `alert()`s rather than toasts, deliberately: reaching Elm's toasts
from the port layer means the `ErrorAlert` port, which is the *sync* error
channel (it sets `errorState` and is cleared by the next successful push). A
refused paste has nothing to do with sync and would sit there until an unrelated
push cleared it. `alert` is what the permission-denied path already used and
what `save.js` uses for a failed save.

**Tests.** 158 elm-test (was 154) and 143 bun test (was 108). Red first
throughout: the four Elm tests were written against the `Result` API before it
existed, and the three reason assertions were re-checked by blanking the reasons
to `Err "unreadable"` and confirming exactly those three fail. `ws-errors.js`
and `clipboard.js` are a new seam, recorded as **ADR-0001 seam 12** ("what a
failure is worth telling the user"), as that ADR requires.

**Verified by inspection**, being out of reach at every seam: the `Page.App`
wiring that turns each `Result` into a toast (`update` needs a `Nav.Key` no test
can make — ADR-0001 seams 5, 7–10), the `switch` in `ws.onmessage` itself
(Dexie, a live socket, `doc.js` module state), and the three clipboard call
sites.

## Comments

- **No site was left silent**, so there is no silence-is-correct exemption to
  record. The five *per-message-type* silences in `ws-errors.js` are argued
  above and in the module's own header, which is the place a future reader will
  look.
- **`errorState` and the data-decode toasts are deliberately separate.** A
  failed decode does not set `errorState`, because that flag means "sync is
  failing" and is cleared by the next successful push — which would clear a
  still-broken decode. The `ErrorAlert` path from `ws-errors.js` *does* set it,
  because that is the flag's existing meaning and those failures are sync
  failures.
- **The `ErrorAlert` caveat, inherited not introduced:** a successful push
  clears `errorState` and removes every `Error` toast from the tray, including
  one raised by a failed `bulkPut` of pulled cards, which a push does not fix.
  Narrowing that filter is a change to the sync-error model rather than to E16,
  so it is left alone; noted here in case it is worth its own ticket.
- **The copy paths still flash optimistically.** The flash is synchronous and
  the failure is asynchronous, so a refused copy flashes and *then* alerts.
  Making the flash conditional would have meant reordering both call sites for
  no gain — the alert lands on top of it.
- Not touched, and not in E16: `fromElm`'s dispatch-table catch, the
  `window.addEventListener("error")` handler, `SetFullscreen`'s
  `.catch(console.log)`, and the two `catch (e) { console.log(e) }` blocks in
  `InitDocument`/`LoadDocument`. Those are ticket 23's `js-robustness` territory
  (S5–S8, S13) if anyone wants them.
- One drive-by that is worth knowing: the outer `catch (e)` in `ws.onmessage`
  **shadowed the `MessageEvent` parameter `e`**. It is `catch (err)` now.
- Verification: `bun run test:elm` 158/158, `bun test` 143/143,
  `bun run newbuild` succeeds, `node config-check.js` exits 0.
