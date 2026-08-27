# 31: Fullscreen editing bypasses the document block

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 15 (resolved)

**Covers:** new finding from ticket 15's resolution (not in CODE_REVIEW.md;
E5's family).

**What to build:** `changeMode`'s `FullscreenEditing` target branches have no
`preventIfBlocked` at all, and `"shift+enter"` reaches one directly — so on a
blocked document (history view open, public document) shift+enter really
opens a fullscreen editor and broadcasts `CollabEditing`. Guard all
fullscreen-entering transitions the way ticket 15 ordered the two `Editing`
branches (guard replaces the whole result triple, last in the chain). This is
a behavior change across three-ish branches, not a reordering — read ticket
15's `## Answer` (E5) first, and its note on why elm-test can't inspect the
`Cmd` (verify the guard via the model/mode transition, which IS testable).

## Acceptance criteria

- [x] Red first: on a blocked document, the fullscreen-entering keyboard
      paths leave the mode unchanged (mode transition testable at seam 1/the
      Page.Doc seam even if the Cmd is not).
- [x] Unblocked fullscreen entry still works (pinned).
- [x] Full suite + build green; CI green.

## Answer

One commit on `selfhost`: **`6147f80`** — `src/elm/Page/Doc.elm` (three
guards), `tests/ViewModeTest.elm` (new, 6 tests), `docs/adr/0001` +
`CONTEXT.md` (seam 11). Claim: `02cd37c`.

**The count is three, and all three are `changeMode` branches.** A fullscreen
editor is entered in exactly four ways, one of which never reaches an
unguarded branch:

| route | event | `changeMode` branch | before |
|---|---|---|---|
| `shift+enter` from the normal view | `Keyboard "shift+enter"` | `( Normal _, FullscreenEditing _ )` | unguarded — the ticket's bug |
| the card editor's fullscreen button | `gw-edit-fullscreen` → `EditToFullscreenMode` | `( Editing _, FullscreenEditing _ )` | unguarded |
| the fullscreen view moving focus to another card | `FullscreenCardFocused` | `( FullscreenEditing _, FullscreenEditing _ )` | unguarded |
| inserting a card from a fullscreen editor (`mod+j`/`k`/`l`, `InsertAbove`/`Below`/`Child`) | `insert`'s `newViewMode` | the same third branch | already guarded, by `insert`'s own `preventIfBlocked` |

Nothing else produces a `FullscreenEditing` mode: `lastActives` and
`FieldChanged` rewrite the mode the document is already in (a card id from
storage, a keystroke), and `mod+j`/`mod+k`/`mod+l` set the split field before
handing off to `insert`. Each of the three now ends with
`|> preventIfBlocked model`, last in the pipeline as `insert` and the two
`Editing` branches do it, so the guard replaces the whole
`( model, cmd, msgs )` triple and nothing above it can leak past the block:
not the mode change, not `focus`, not `saveIfAsked`'s save (its `LocalSave`
goes with the dropped `msgs`), and not the `SendCollabState (CollabEditing …)`
that made a blocked reader look like an editor to collaborators — E5's
phantom, which ticket 15 fixed for the normal editor only.

**The fullscreen *exits* stay unguarded, deliberately.**
`( FullscreenEditing _, Editing _ )` and `( FullscreenEditing _, Normal _ )`
have no guard and must not get one: a reader who is somehow in a fullscreen
editor on a blocked document has to be able to leave it, and
`FullscreenEditing → Editing` is where ticket 15's E6 fix lands the browser
leaving fullscreen (Esc, F11). Guarding it would put the editor back on screen
over a window that is no longer fullscreen — the bug E6 closed. Ticket 15's
comment listed that branch as "broadcasts and transitions while blocked"; it
does, and that is the right answer for an exit.

**Tests** — `tests/ViewModeTest.elm`, 6 tests, at the new **ADR-0001 seam 11**
(the document's mode machine: which mode an event leaves the document in,
`getViewMode` after `opaqueIncoming`/`opaqueUpdate` on a document built from
the exported setters). Three blocked cases, all red first — the mode really
became `FullscreenEditing` on a blocked document in each — paired with three
pins that fullscreen entry still works when nothing is blocked. Mutation-checked
one guard at a time: each of the three is caught by exactly one test
(`shift+enter` → "stays in normal mode"; the button → "leaves the card editor
where it is"; the focus move → "does not follow the fullscreen view's focus").

The card editor's button has no test-reachable `Msg`: `Page.Doc.Msg` exports no
constructors, and no `Incoming` message reaches that branch. Its test therefore
goes through the app's own route — simulate `gw-edit-fullscreen` on
`Page.Doc.view` with `Test.Html.Event`, then hand the `Msg` it yields to
`opaqueUpdate`. That is the first use of `Test.Html` in this repo; `lazy3` (the
`<gw-tree>` node) simulates fine.

*What the tests still cannot see:* whether a `Cmd` is sent, so guard **ordering**
is invisible — moving one guard to the front of its pipeline keeps all 139 tests
green (checked). Same limitation ADR-0001 seam 10 records for E5, and the reason
the guard-last convention is written into the comment on each branch.

**Verification** — `bun run test:elm` 139/139 (133 before), `bun test` 98/98,
`bun run newbuild` exit 0, `bun run config-check` exit 0, all on the rebased
tree carrying ticket 09's socket-resend commit. CI green on `selfhost` for
`6147f80`: run
<https://github.com/advaitmb/client/actions/runs/33088692073>.

## Comments

- **Editing *inside* a fullscreen editor on a blocked document is a separate,
  now-unreachable hole — not widened into.** `mod+j`/`mod+k`/`mod+l` truncate
  the open card's field and run `saveCardIfEditing` *before* calling `insert`,
  so `insert`'s guard sees the already-mutated model as its "original": on a
  blocked document in fullscreen, the keypress inserts no card (guard held) but
  leaves the card's content truncated in the working tree. The `Editing` limbs
  of the same three shortcuts are built the same way. Both are gated by
  construction now — after this ticket no editor of either kind opens on a
  blocked document, and the block is only ever set from the normal view
  (`Page.App` runs `maybeActivate` before `setBlock`, and a public document is
  blocked as it loads) — so the fix would be a `preventIfBlocked` on a state
  that cannot arise. It belongs with 24 (`Page.Doc` consistency) if that ticket
  wants the guards to be uniform rather than merely sufficient.
- **Why three duplicated guard lines rather than one hoisted guard.** The
  alternative — guarding the whole `case` — would guard the exits too, which is
  the behavior change the section above rejects, and hoisting the collab
  decision out of all nine branches was already weighed and declined in
  ticket 15's Comments for the same reason. Three explicit lines match the
  file's existing convention (`insert`, the two `Editing` branches, `openCard`,
  `toggleEditing`, `DragDropMsg`) and keep each branch's answer readable at the
  branch.
- **`preventIfBlocked` nests harmlessly.** The insert-from-fullscreen route now
  passes through two guards (`changeMode`'s new one, then `insert`'s). The inner
  one's alert is discarded by the outer one, which replaces the whole triple, so
  a blocked insert still alerts exactly once.
- **ADR-0001 gains seam 11** (the mode machine) rather than stretching seam 10,
  which is explicitly "what the document's chrome says and writes" and pure:
  this seam runs `Page.Doc`'s `update`/`incoming` and reads the state they
  leave, which is a different kind of observation and worth naming separately.
  `CONTEXT.md`'s seam list gains the matching entry.
