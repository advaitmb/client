# 16: Drag-drop correctness (off-by-one, stale flags, id paste, autoscroll throw)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E7, E8, E9, E15.

**What to build:** Native drag-drop behaves: a same-parent downward drop lands
exactly where indicated (compute the index on the pruned tree, E7); internal
drags are not misreported to Elm as external and both sides' drag flags reset
after every drop (E8 — send `DragDone`, fix the internal-drag detection, make
the reset reachable despite `stopPropagation`); dropping a card onto an open
editing textarea does not paste its raw card id (E9); drag auto-scroll over
non-column areas doesn't throw every 15 ms (E15).

## Acceptance criteria

- [x] Failing test first for the drop-index math (seam 1 or extracted
      helper): same-parent downward drop by one lands one slot down, not two.
- [x] Flag lifecycle: after an internal drop, neither JS nor Elm still
      believes a drag is in progress (test at a practical seam).
- [x] Textarea drop is prevented or inert; no raw id insertion.
- [x] Autoscroll handles undefined column hover.
- [x] CI green.

## Answer

Landed in commits `e8e5d38` (E7), `0dbe35f` (E8/E9/E15), `a5ebebb` (review
pass), `f989991` (the CI fix) and `504eaad` (glossary + seams) on `selfhost`
(claim: `7ff1817`).

All four findings are one story: the port layer could not tell a **card drag**
from an **external drag**, and Elm was computing a drop against a tree that
still held the card being dropped.

### E7 — a dropped card lands where it was dropped

`CardDropped` read the target's index off `model.workingTree.tree`, where the
dragged card still counts. `TreeStructure.Mov` prunes that card and *then*
inserts it, and `Doc.Data.placeCard` positions it among siblings that exclude
it — so a drop below the next sibling landed past it *and* past the one after,
persisted positions agreeing, so it stuck.

The decision is now `Doc.TreeStructure.dropPlacement : String -> DropId -> Tree
-> Maybe Placement`, read on the pruned tree. It lives in `TreeStructure`
because the rule it encodes is that module's: the index is an index into the
tree `Mov` inserts into.

| drop (siblings `a b c`) | before | now |
| --- | --- | --- |
| `a` below `b` | `b c a` | `b a c` |
| `a` above `c` | `b c a` | `b a c` |
| `c` below `a` (upward) | `a c b` | `a c b` |
| `a` into `b` | appended | appended |
| `b` into its own child `b1` | **every card under `b` lost** | no move |
| onto a card no longer in the tree | moved to the top of the root | no move |

The last two rows are pruning answering for free what the old elm-dnd path got
by pruning the dragged card out of the *view* at drag start: on the pruned tree
a target inside the dragged subtree has no parent and no index, so there is no
move. Left to go through, `insertSubtree` looked for a parent that had just been
pruned away, found nothing, and dropped the subtree on the floor. `Page.Doc` is
left with the mechanical part, and `CardDropped` now carries a `DropId` rather
than two strings and a `where` it re-cased itself.

### E8 — which drag is in progress

`draggingInternal`'s only setter was the elm-dnd `DragStart` port, dead on both
sides (§6). So `document.ondragenter` announced *every* card drag to Elm as
`DragExternalStarted`, and since `<gw-tree>` `stopPropagation()`s an internal
drop, the document-level handler that cleared the flags never ran on one: both
sides stayed mid-drag for the rest of the session, and a card dropped anywhere
but a drop region was handed to Elm as external text — inserting a new card
containing the dragged card's id.

A card drag now reports itself through the `gw-drag-start` / `gw-drag-end` pair
`<gw-tree>` already emitted and nothing listened to. `dragend` fires at the
drag's source whatever the drag ended in — dropped, refused, cancelled with
Escape — and `<gw-tree>` emits on itself, not on the card, so a re-render during
the drop cannot swallow it. `CardDropped` sends `DragDone` too (both limbs,
including the refused drop), and Elm's `DropExternal` now clears its own flag on
the limb where the drop landed on no drop region.

### E9 — dropping a card on the card being edited

Two halves, both deliberate:

- `tree.ts` sets the drag's `text/plain` payload to `""` again (the old path's
  choice). The payload is what the browser default-drops into whatever the drag
  lands on; which card is being dragged travels in `gw-drop`, where the only
  reader is.
- the drop handler prevents the browser's default over an open editor **only
  for a card drag**. Text dragged in from outside still lands at the caret,
  which is what a text field is for — and Elm is told nothing about it, so no
  card is made from text that is already in the one being edited.

### E15 — autoscroll over the header

`path.filter(…'column')[0]` is `undefined` over the header, the sidebar and the
padding columns — all of which sit inside an edge tenth of the window — and the
`setInterval` body dereferenced it every 15 ms. An autoscroll with nothing to
scroll now doesn't start; one already running is left alone, so a column that
scrolled out from under the pointer keeps going while the pointer stays on the
edge. A card drag cancelled with Escape stops the autoscroll too, which the
never-registered `dragend` branch had been trying to do.

### Where it lives, and the seams

The document-level handlers moved to `src/shared/drag.js` — nothing in `doc.js`
is importable by a test — taking `{root, toElm, viewport, scrollRoot, timers}`
and returning `{dragDone}` for the port. `doc.js` lost five module-level
variables and ~95 lines. ADR-0001 gains **seam 9** (drop placement, Elm, pure)
and seam 4 gains `drag.js`; CONTEXT.md gains **card drag / external drag** and
**drop placement**; ARCHITECTURE.md's module table, custom-element section and
test inventory name the new module.

39 tests: 16 at seam 9 (`tests/DropTest.elm`, 8 red first), 18 at seam 4
(`tests/drag.test.ts`, 5 red first + 1 fixture guard added with the CI fix), 5
at seam 3 (`tests/tree.test.ts`, 1 red first).

### Verification

Rebased on `selfhost` at `504eaad`: `bun run test:elm` 122/122, `bun test`
85/85 across 11 files, `bun run newbuild` succeeds, `bun run config-check` exit
0. CI green on `selfhost`: runs
<https://github.com/advaitmb/client/actions/runs/33075349905> (`504eaad`,
carrying the CI fix) and
<https://github.com/advaitmb/client/actions/runs/33075543048> (`5e33ebe`, the
tracker). The two runs before them —
<https://github.com/advaitmb/client/actions/runs/33074480423> (`0dbe35f`) and
<https://github.com/advaitmb/client/actions/runs/33074852813> (`a5ebebb`) —
were red in the TS-test step on the fixture bug below, and red for the two
ticket-30 commits pushed between them.

## Comments

- Red-first evidence, E7 (the current index math extracted verbatim first, so
  the seam could be red on shipped behavior): `a` below `b` gave
  `{parentId = "0", index = 2}` → `b c a`; `a` above `c` gave index 2 → `b c a`;
  and all five impossible drops answered `Just` — `b` into `b1` answering
  `{parentId = "b1", index = 999999}`, which is the subtree-losing insert.
- Red-first evidence, E8/E9/E15 (same verbatim-extraction-then-fix): 5 of 17 —
  a card drag announced as `DragExternalStarted`; a card dropped on the open
  editor not prevented; the editor drop leaving `externalDrag` set so the next
  external drag was invisible; the header hover starting an interval whose body
  throws; a cancelled card drag leaving the autoscroll running. `tree.ts`'s half
  was red on the payload: `[["text/plain", "card-one"]]`.
- **CI was red on 14 of the drag tests while all 17 passed locally**, fixed in
  `f989991`. The fixture named its scroll root `gw-tree` — a real custom
  element, whose `connectedCallback` replaces its children with its own
  scaffolding, so the column, card, drop region and editor were detached from
  the element the handlers listen on and nothing bubbled. Only the three tests
  that assert *nothing* happened passed, which is why the failure looked
  environmental. It depended on file order and on the runner: CI (bun 1.3.14)
  shares one jsdom and one `customElements` registry across test files and runs
  `tree.test.ts` first; local bun 1.3.11 does not share them. Reproduced locally
  by importing `src/ui/tree` into the drag suite (3 pass / 14 fail, CI's
  signature exactly), green with the fixture built from plain `div`s. A first
  test now pins that the fixture is one connected tree, and `tests/dom.ts`
  records the shared-document rule for the next DOM test.
- **Deliberate residue:** dropping text from outside the app into the *open
  editor* leaves Elm believing an external drag is still in progress. It is
  invisible — the flag only decides how `<gw-tree>` reads drag events, of which
  there are none until a drag starts, and the next external drag sets it again —
  and the alternative was worse: the only message Elm has for "the external drag
  ended" is `DropExternal`, which inserts a card wherever a drop region was last
  hovered. Telling Elm on `dragleave` was rejected too: browsers differ on
  whether `relatedTarget` is `null` for element-to-element leaves, so it could
  end a live external drag and make the drop regions stop responding.
- **Out of scope, found while in the file: a card's own descendants still offer
  drop regions during a drag.** The drop is now refused (E7 above) rather than
  losing the subtree, but the user gets the same `drop-hover` highlight as a
  legal target and then nothing happens. The old path avoided it by pruning the
  dragged card out of the *view*; the native one could hide the regions on the
  dragged card's descendants while `[dragging]` is set. That is a `tree.ts` /
  CSS change, and it needs the dragged card's descendant set, which Elm already
  computes for the active card only.
- The dead elm-dnd `DragStart` port case keeps its body minus the flag it used
  to set; ticket 22 removes the path on both sides. Nothing in this ticket
  builds on it.
- `docs/CODE_REVIEW.md` left as the catalog as found, matching tickets 02–14.
