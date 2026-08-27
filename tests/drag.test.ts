/**
 * The drag lifecycle on the JS side of the ports (ADR-0001 seam 4), extracted
 * from doc.js's document-level handlers into src/shared/drag.js.
 *
 * Two drags land on this document and they are not the same thing: a card
 * dragged from one place in the tree to another, which `<gw-tree>` reports and
 * Elm moves, and text dragged in from outside the app, which only this layer
 * can see. Telling them apart is the whole job — and the flag that did it had
 * no live setter, so every internal drag was announced to Elm as text arriving
 * from outside, and the flags were never cleared afterwards (CODE_REVIEW.md
 * E8). `<gw-tree>` stops an internal drop from propagating, so a
 * document-level drop handler is not where a card drag ends; `gw-drag-start` /
 * `gw-drag-end` are.
 *
 * Observed through the boundaries this module actually crosses: the DOM events
 * it listens for, whether it prevented the browser's own drop handling, the
 * `toElm` calls it makes, and the elements it asks to scroll (timers injected,
 * so an autoscroll is a callback this test can run rather than a wait).
 */
import { beforeEach, expect, test } from "bun:test";

import { installDragHandlers } from "../src/shared/drag";

/** Every (data, port, tag) triple sent to Elm, and the tags alone. */
let sent: Array<[unknown, string, string]> = [];
const tags = () => sent.map(([, , tag]) => tag);

/** The intervals the module has running, by the id the fake timer issued. */
let intervals: Map<number, () => void>;
let nextIntervalId: number;

/** Every (dx, dy) an element was asked to scroll by. */
let scrolls: Map<Element, Array<[number, number]>>;

interface Dom {
  root: HTMLElement;
  /** Where <gw-tree> renders: the element that reports card drags, and the one
   * that scrolls sideways through the columns. */
  tree: HTMLElement;
  column: HTMLElement;
  card: HTMLElement;
  /** One of the three drop regions inside a card. */
  region: HTMLElement;
  /** The page header: inside the app, outside any column. */
  header: HTMLElement;
  /** The textarea of a card being edited. */
  editor: HTMLElement;
}

let dom: Dom;
let controller: { dragDone: () => void };

/**
 * The viewport the geometry is measured against: a 1000x800 window with the
 * sidebar rail showing. Coordinates in the tests below are absolute, so
 * `y: 60` is "just under the header" and `y: 780` is "at the bottom edge".
 */
const VIEWPORT = { width: 1000, height: 800, sidebarWidth: 40 };
const MIDDLE = { x: 500, y: 400 };

beforeEach(() => {
  sent = [];
  intervals = new Map();
  nextIntervalId = 0;
  scrolls = new Map();
  document.body.replaceChildren();
  dom = buildDom();

  controller = installDragHandlers({
    root: dom.root,
    toElm: (data: unknown, port: string, tag: string) => sent.push([data, port, tag]),
    viewport: () => VIEWPORT,
    scrollRoot: () => dom.tree,
    timers: {
      setInterval: (fn: () => void) => {
        nextIntervalId += 1;
        intervals.set(nextIntervalId, fn);
        return nextIntervalId;
      },
      clearInterval: (id: number) => {
        intervals.delete(id);
      },
    },
  });
});

/** The DOM tree.ts renders, as much of it as a drag can land on. */
function buildDom(): Dom {
  const el = (tag: string, attrs: Record<string, string>) => {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, value);
    // Elements in jsdom have no layout and no scrolling, so record the asks.
    (node as unknown as { scrollBy: (x: number, y: number) => void }).scrollBy = (x, y) => {
      const calls = scrolls.get(node) ?? [];
      calls.push([x, y]);
      scrolls.set(node, calls);
    };
    return node;
  };

  const root = el("div", { id: "app" });
  const header = el("div", { id: "header" });
  // `div`, not `gw-tree`: the tag is a defined custom element as soon as any
  // test in the run has imported src/ui/tree, and connecting one replaces its
  // children with its own scaffolding -- which detached this whole fixture from
  // `root`, so nothing bubbled to the handlers under test. Which tag renders
  // the columns is no business of this module's: it is handed the element to
  // scroll, and listens on the document. (`#document` is the id <gw-tree> gives
  // itself.)
  const tree = el("div", { id: "document" });
  const column = el("div", { class: "column" });
  const card = el("div", { class: "card", id: "card-a" });
  const region = el("div", { class: "drop-region-below" });
  const editingCard = el("div", { class: "card active editing", id: "card-b" });
  // What <gw-textarea> puts in the DOM: the host's classes, on a textarea.
  const editor = el("textarea", { class: "edit mousetrap", id: "card-edit-b" });

  card.append(region);
  editingCard.append(editor);
  column.append(card, editingCard);
  tree.append(column);
  root.append(header, tree);
  document.body.append(root);
  return { root, tree, column, card, region, header, editor };
}

/** A drag event as the browser dispatches it, on the element it landed on. */
function drag(
  type: string,
  target: Element,
  opts: { x?: number; y?: number; text?: string; relatedTarget?: EventTarget | null } = {},
): Event {
  const ev = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: opts.x ?? MIDDLE.x,
    clientY: opts.y ?? MIDDLE.y,
  });
  Object.defineProperty(ev, "dataTransfer", {
    value: { getData: () => opts.text ?? "" },
  });
  if ("relatedTarget" in opts) {
    Object.defineProperty(ev, "relatedTarget", { value: opts.relatedTarget });
  }
  target.dispatchEvent(ev);
  return ev;
}

/** What <gw-tree> emits when a card drag starts and ends. */
function treeEvent(name: string, detail?: unknown) {
  dom.tree.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
}

/** Run every interval callback once, as 15ms of autoscroll would. */
function tick() {
  for (const fn of intervals.values()) fn();
}

const scrolledBy = (el: Element) => scrolls.get(el) ?? [];

test("the fixture is one connected tree, so every drag reaches the handlers", () => {
  // Every handler under test listens on `root`, so a fixture node that is not
  // inside it reports nothing and every assertion below reads as "the drag did
  // nothing". This says which it was. It caught the fixture being built from a
  // `gw-tree` element, which replaces its children with its own scaffolding as
  // soon as any other test file in the run has defined it.
  for (const node of [dom.tree, dom.column, dom.card, dom.region, dom.editor, dom.header]) {
    expect(dom.root.contains(node)).toBe(true);
  }
});

test("a card dragged inside the app is not announced to Elm as text from outside", () => {
  treeEvent("gw-drag-start", "card-a");

  drag("dragenter", dom.card);

  expect(tags()).toEqual([]);
});

test("text dragged in from outside is announced once", () => {
  drag("dragenter", dom.card);
  drag("dragenter", dom.region);

  expect(sent).toEqual([[null, "docMsgs", "DragExternalStarted"]]);
});

test("a card drop <gw-tree> keeps to itself still ends the drag", () => {
  treeEvent("gw-drag-start", "card-a");
  // What tree.ts does with an internal drop: handle it, then stop it, so no
  // document-level handler ever sees it.
  dom.region.addEventListener("drop", (e) => e.stopPropagation());
  drag("drop", dom.region);
  treeEvent("gw-drag-end");

  // Nothing was reported for the card drag, and the next external drag is
  // reported again -- so neither flag was left set.
  drag("dragenter", dom.card);

  expect(tags()).toEqual(["DragExternalStarted"]);
});

test("a card dropped anywhere else in the app ends the drag too", () => {
  treeEvent("gw-drag-start", "card-a");
  drag("drop", dom.card, { text: "card-a" });

  drag("dragenter", dom.card);

  expect(tags()).toEqual(["DragExternalStarted"]);
});

test("Elm reporting the drop it handled ends the drag", () => {
  treeEvent("gw-drag-start", "card-a");
  controller.dragDone();

  drag("dragenter", dom.card);

  expect(tags()).toEqual(["DragExternalStarted"]);
});

test("dropping a card on the card being edited inserts nothing", () => {
  treeEvent("gw-drag-start", "card-a");

  // The browser's default here is to insert the drag's text/plain payload at
  // the caret -- which used to be the dragged card's 24-character id
  // (CODE_REVIEW.md E9).
  const dropped = drag("drop", dom.editor, { text: "card-a" });

  expect(dropped.defaultPrevented).toBe(true);
  expect(tags()).toEqual([]);
});

test("text dragged in from outside still drops into the card being edited", () => {
  drag("dragenter", dom.editor);

  const over = drag("dragover", dom.editor);
  const dropped = drag("drop", dom.editor, { text: "pasted from elsewhere" });

  // Left to the browser on purpose: an open editor is a text field, and text
  // dropped on it belongs at the caret. Elm is told nothing, so no card is
  // made from text that is already in the one being edited.
  expect(over.defaultPrevented).toBe(false);
  expect(dropped.defaultPrevented).toBe(false);
  expect(tags()).toEqual(["DragExternalStarted"]);

  // The drag is over, though: the next one is announced again.
  drag("dragenter", dom.card);
  expect(tags()).toEqual(["DragExternalStarted", "DragExternalStarted"]);
});

test("text dropped on the tree is handed to Elm", () => {
  drag("dragenter", dom.region);
  drag("drop", dom.region, { text: "# A dropped heading" });

  expect(sent).toEqual([
    [null, "docMsgs", "DragExternalStarted"],
    ["# A dropped heading", "docMsgs", "DropExternal"],
  ]);
});

test("an Obsidian note dropped on the tree becomes its title", () => {
  drag("dragenter", dom.region);
  drag("drop", dom.region, { text: "obsidian://open?vault=notes&file=My%20Note" });

  expect(sent[1]).toEqual(["# My Note", "docMsgs", "DropExternal"]);
});

test("dragging over the top of a column scrolls that column up", () => {
  drag("dragover", dom.region, { y: 60 });
  tick();

  expect(scrolledBy(dom.column)).toEqual([[0, -20]]);
});

test("dragging over the bottom of a column scrolls that column down", () => {
  drag("dragover", dom.region, { y: 780 });
  tick();

  expect(scrolledBy(dom.column)).toEqual([[0, 20]]);
});

test("dragging over the left edge scrolls the tree back", () => {
  drag("dragover", dom.region, { x: 60 });
  tick();

  expect(scrolledBy(dom.tree)).toEqual([[-20, 0]]);
});

test("dragging over the right edge scrolls the tree on", () => {
  drag("dragover", dom.region, { x: 980 });
  tick();

  expect(scrolledBy(dom.tree)).toEqual([[20, 0]]);
});

test("dragging over the header scrolls nothing", () => {
  // The header sits above every column, so the pointer is inside the top tenth
  // of the window with no column under it at all. Asking the column that isn't
  // there to scroll threw every 15ms (CODE_REVIEW.md E15).
  drag("dragover", dom.header, { y: 60 });

  expect(intervals.size).toBe(0);
  expect(() => tick()).not.toThrow();
});

test("a drop stops the autoscroll", () => {
  drag("dragover", dom.region, { y: 60 });
  expect(intervals.size).toBe(1);

  drag("drop", dom.region);

  expect(intervals.size).toBe(0);
});

test("a cancelled drag stops the autoscroll", () => {
  drag("dragover", dom.region, { y: 60 });
  expect(intervals.size).toBe(1);

  // Escape during a card drag: no drop event anywhere, only the drag ending.
  treeEvent("gw-drag-end");

  expect(intervals.size).toBe(0);
});

test("dragging back to the middle stops the autoscroll", () => {
  drag("dragover", dom.region, { y: 60 });
  drag("dragover", dom.region);

  expect(intervals.size).toBe(0);
});
