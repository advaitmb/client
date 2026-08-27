/**
 * <gw-textarea> lifecycle contract (ADR-0001 seam 3).
 *
 * The element's public surface is its attributes (`start-value`, `card-id`),
 * the textarea it renders, and the `toElm` port function it was defined with:
 * every keystroke must reach Elm as `FieldChanged`, every cursor move as
 * `TextCursor`, and a click outside the card as `ClickedOutsideCard`, for as
 * long as the card is being edited.
 *
 * `<gw-tree>` reuses card elements across renders, so a tree change that
 * arrives mid-edit (a second tab writing, a collaborator edit, a checkbox
 * toggle) re-parents the editing card into freshly built column/group
 * scaffolding. That fires disconnectedCallback + connectedCallback on the
 * `gw-textarea` inside it. The element has to come back fully wired -- and
 * wired exactly once, so one keystroke is still one `FieldChanged`.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";

import { defineCustomTextarea } from "../src/shared/doc-helpers";

/** Every (data, port, tag) triple the element has sent to Elm. */
let sent: Array<[unknown, string, string]> = [];

// Matches doc.js's CARD_DATA: card-based documents, the only mode gw-textarea
// treats specially (fullscreen autosave).
const CARD_DATA = Symbol.for("cardbased");

defineCustomTextarea(
  (data: unknown, port: string, tag: string) => {
    sent.push([data, port, tag]);
  },
  () => CARD_DATA,
);

const tags = () => sent.map(([, , tag]) => tag);
const dataFor = (tag: string) =>
  sent.filter(([, , t]) => t === tag).map(([data]) => data);

/**
 * The DOM tree.ts builds around an editing card:
 * div#document > div.column > div.group > div.card.active.editing > gw-textarea,
 * plus the buffer div that pads a column -- inside the document but outside any
 * card, i.e. a place where clicking ends the edit.
 */
function mountEditingCard(cardId: string, content: string) {
  const doc = document.createElement("div");
  doc.id = "document";
  const card = document.createElement("div");
  card.className = "card active editing";
  card.id = `card-${cardId}`;
  const el = document.createElement("gw-textarea");
  el.setAttribute("card-id", cardId);
  el.setAttribute("class", "edit mousetrap");
  el.setAttribute("dir", "auto");
  el.setAttribute("start-value", content);

  card.append(el);
  const column = buildColumn(card);
  doc.append(column);
  document.body.append(doc);
  return { doc, column, card, el };
}

function buildColumn(card: HTMLElement) {
  const column = document.createElement("div");
  column.className = "column";
  const group = document.createElement("div");
  group.className = "group";
  const buffer = document.createElement("div");
  buffer.className = "buffer";
  group.append(card);
  column.append(buffer, group);
  return column;
}

/**
 * What renderTree() does when the `tree` attribute changes: build fresh
 * column/group scaffolding, move the reused card element into it, then swap the
 * scaffolding in. The card element -- and the gw-textarea inside it -- is
 * detached and re-attached.
 */
function reparent(doc: HTMLElement, card: HTMLElement) {
  const column = buildColumn(card);
  doc.replaceChildren(column);
  return column;
}

function textareaOf(el: Element): HTMLTextAreaElement {
  const ta = el.querySelector("textarea");
  if (!ta) throw new Error("gw-textarea rendered no textarea");
  return ta as HTMLTextAreaElement;
}

/** A keystroke: the browser updates the value, then fires `input`. */
function typeInto(el: Element, value: string) {
  const ta = textareaOf(el);
  ta.value = value;
  ta.dispatchEvent(new Event("input", { bubbles: true }));
}

/** A cursor move: arrow keys and clicks both report the caret. */
function moveCaret(el: Element, position: number) {
  const ta = textareaOf(el);
  ta.setSelectionRange(position, position);
  ta.dispatchEvent(new Event("keyup", { bubbles: true }));
}

/** A click inside the document but outside the card being edited. */
function clickOutsideCard(column: HTMLElement) {
  column
    .querySelector(".buffer")!
    .dispatchEvent(new Event("click", { bubbles: true }));
}

beforeEach(() => {
  sent = [];
});

afterEach(() => {
  document.body.replaceChildren();
});

test("a keystroke reaches Elm as FieldChanged", () => {
  const { el } = mountEditingCard("1", "saved text");

  typeInto(el, "saved text plus more");

  expect(sent).toEqual([["saved text plus more", "docMsgs", "FieldChanged"]]);
});

test("keystrokes still reach Elm after the editing card is re-parented", () => {
  const { doc, card, el } = mountEditingCard("1", "saved text");
  typeInto(el, "first edit");
  sent = [];

  reparent(doc, card);
  typeInto(el, "second edit");

  expect(dataFor("FieldChanged")).toEqual(["second edit"]);
});

test("cursor moves still reach Elm after the editing card is re-parented", () => {
  const { doc, card, el } = mountEditingCard("1", "saved text");

  reparent(doc, card);
  typeInto(el, "abc");
  sent = [];
  moveCaret(el, 3);

  expect(tags()).toEqual(["TextCursor"]);
  expect(dataFor("TextCursor")).toEqual([
    { selected: false, position: "end", text: ["abc", ""] },
  ]);
});

test("clicking outside the card still ends the edit after a re-parent", () => {
  const { doc, card } = mountEditingCard("1", "saved text");

  const column = reparent(doc, card);
  clickOutsideCard(column);

  expect(sent).toEqual([[null, "docMsgs", "ClickedOutsideCard"]]);
});

test("re-parenting twice does not double-report a keystroke", () => {
  const { doc, card, el } = mountEditingCard("1", "saved text");

  reparent(doc, card);
  const third = reparent(doc, card);
  sent = [];
  typeInto(el, "typed once");
  moveCaret(el, 0);
  clickOutsideCard(third);

  expect(third.contains(el)).toBe(true);
  expect(tags()).toEqual(["FieldChanged", "TextCursor", "ClickedOutsideCard"]);
});

test("text typed before a re-parent is not reverted to start-value", () => {
  const { doc, card, el } = mountEditingCard("1", "saved text");
  typeInto(el, "saved text, still being written");

  reparent(doc, card);

  expect(textareaOf(el).value).toBe("saved text, still being written");
});

test("a card that leaves the DOM stops reporting to Elm", () => {
  const { doc, card, el } = mountEditingCard("1", "saved text");
  const column = doc.querySelector(".column") as HTMLElement;

  card.remove();
  typeInto(el, "typed after removal");
  moveCaret(el, 0);
  clickOutsideCard(column);

  expect(sent).toEqual([]);
});
