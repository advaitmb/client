/**
 * <gw-tree>'s card drags (ADR-0001 seam 3).
 *
 * A card drag is reported entirely through events: `gw-drag-start` and
 * `gw-drag-end` so the port layer can tell it from text dragged in from
 * outside the app, and `gw-drop` so Elm can move the card. What travels in the
 * drag's own `dataTransfer` is a separate question, and the answer is nothing:
 * the payload is what the browser default-drops into whatever the drag lands
 * on, and a card carrying its own id there pasted 24 characters of hex into
 * the card being edited (CODE_REVIEW.md E9).
 */
import { beforeEach, expect, test } from "bun:test";
import "../src/ui/tree";

/** One column, one group, two cards -- the smallest tree with a drop target. */
const TREE = JSON.stringify([[[
  { id: "card-one", content: "One", hasChildren: false, isLast: false },
  { id: "card-two", content: "Two", hasChildren: false, isLast: true },
]]]);

const VIEW_STATE = JSON.stringify({
  active: "card-one",
  editing: null,
  ancestors: [],
  descendants: [],
});

/** The drag events Elm and the port layer listen for. */
const DRAG_EVENTS = ["gw-drag-start", "gw-drag-end", "gw-drop"];

let el: HTMLElement;
let reported: Array<[string, unknown]>;
/** Every (format, data) pair the drag was given to carry. */
let payload: Array<[string, string]>;

beforeEach(() => {
  document.body.replaceChildren();
  el = document.createElement("gw-tree");
  el.setAttribute("tree", TREE);
  el.setAttribute("view-state", VIEW_STATE);
  document.body.append(el);

  reported = [];
  for (const name of DRAG_EVENTS) {
    el.addEventListener(name, (e) => reported.push([name, (e as CustomEvent).detail]));
  }
  payload = [];
});

const card = (id: string) => el.querySelector<HTMLElement>(`#card-${id}`)!;
const region = (id: string, where: string) =>
  card(id).querySelector<HTMLElement>(`.drop-region-${where}`)!;

/** A drag event with the dataTransfer the browser would hand the element. */
function dragEvent(type: string): Event {
  const ev = new MouseEvent(type, { bubbles: true, cancelable: true });
  Object.defineProperty(ev, "dataTransfer", {
    value: {
      effectAllowed: "none",
      setData: (format: string, data: string) => payload.push([format, data]),
      getData: () => "",
    },
  });
  return ev;
}

function startDragging(id: string) {
  card(id).dispatchEvent(dragEvent("dragstart"));
}

test("a card drag carries no text to paste anywhere", () => {
  startDragging("card-one");

  expect(payload).toEqual([["text/plain", ""]]);
});

test("a card drag announces itself as it starts and as it ends", () => {
  startDragging("card-one");
  card("card-one").dispatchEvent(dragEvent("dragend"));

  expect(reported).toEqual([
    ["gw-drag-start", "card-one"],
    ["gw-drag-end", null],
  ]);
});

test("dropping on a region reports the card, the target and the region", () => {
  startDragging("card-one");
  region("card-two", "below").dispatchEvent(dragEvent("drop"));

  expect(reported[1]).toEqual([
    "gw-drop",
    { dragged: "card-one", id: "card-two", where: "below" },
  ]);
});

test("a drop keeps to itself: no document-level handler sees it", () => {
  const escaped: string[] = [];
  const watch = () => escaped.push("drop");
  document.addEventListener("drop", watch);

  startDragging("card-one");
  region("card-two", "above").dispatchEvent(dragEvent("drop"));
  document.removeEventListener("drop", watch);

  expect(escaped).toEqual([]);
});

test("dropping a card on itself is not a move", () => {
  startDragging("card-one");
  region("card-one", "below").dispatchEvent(dragEvent("drop"));

  expect(reported.map(([name]) => name)).toEqual(["gw-drag-start"]);
});
