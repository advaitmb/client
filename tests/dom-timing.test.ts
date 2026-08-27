/**
 * The two DOM habits doc.js used to have instead of signals (ADR-0001 seam 4,
 * observed through the real jsdom document) — CODE_REVIEW.md S5 and S6.
 *
 * S5: "act once the element Elm is about to render exists" was written as
 * `setTimeout(fn, 20)` / `setTimeout(fn, 200)`, guesses that are simultaneously
 * too long on a fast machine and too short on a slow one. `whenReady` waits for
 * the DOM change itself.
 *
 * S6: every `ScrollCards` message — one per navigation keystroke — added a
 * fresh anonymous `scroll` listener to every column and removed none, so after
 * a few minutes of arrow-keying a single scroll ran the fillet geometry
 * hundreds of times. The handler is one module-level function now, so the DOM
 * discards the re-registration.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";

import { casesShared, whenReady } from "../src/shared/doc-helpers";

const tick = (ms = 40) => new Promise((resolve) => setTimeout(resolve, ms));

beforeEach(() => {
  document.body.replaceChildren();
});

afterEach(() => {
  document.body.replaceChildren();
});

/* ===== whenReady ===== */

test("an element that is already there is not waited for", async () => {
  document.body.append(document.createElement("div"));
  let ran = 0;

  whenReady(() => document.querySelector("div") !== null, () => { ran += 1; });

  await tick();
  expect(ran).toBe(1);
});

test("nothing runs before the DOM is ready", async () => {
  let ran = 0;

  whenReady(() => document.getElementById("history-slider") !== null, () => { ran += 1; });

  await tick();
  expect(ran).toBe(0);
});

test("the element appearing is what runs it, once", async () => {
  let ran = 0;
  whenReady(() => document.getElementById("history-slider") !== null, () => { ran += 1; });

  const slider = document.createElement("input");
  slider.id = "history-slider";
  document.body.append(slider);
  // Several more mutations, as a real Elm render is.
  document.body.append(document.createElement("span"));
  document.body.append(document.createElement("span"));

  await tick();
  expect(ran).toBe(1);
});

test("an element that never appears gives up, and says so by running anyway", async () => {
  // The callers null-check the element themselves, so running late is how they
  // find out it never came -- and it means neither of them can hang a pending
  // observer on the document for the rest of the session.
  let ran = 0;

  whenReady(() => false, () => { ran += 1; }, 20);

  expect(ran).toBe(0);
  await tick(120);
  expect(ran).toBe(1);
});

test("the callback never runs inside the caller's own turn", async () => {
  // Both call sites are reached from a port handler, i.e. from inside Elm's
  // update cycle: `HistorySlider` dispatches an `input` event Elm listens to,
  // and re-entering Elm from its own handler is what the `setTimeout(…, 0)`
  // was for.
  document.body.append(document.createElement("div"));
  let ran = 0;

  whenReady(() => true, () => { ran += 1; });

  expect(ran).toBe(0);
  await tick();
  expect(ran).toBe(1);
});

/* ===== the fillet scroll listener ===== */

/** One column inside #document, which is what the scroll helpers measure. */
function mountColumn() {
  const doc = document.createElement("div");
  doc.id = "document";
  const column = document.createElement("div");
  column.className = "column";
  doc.append(column);
  document.body.append(doc);
  return column;
}

const scrollCardsMessage = {
  columns: [],
  columnIdx: 1,
  instant: true,
  lastActives: ["root"],
};

function sendScrollCards() {
  const params = {
    localStore: { isReady: () => false },
    lastColumnScrolled: null,
    lastActivesScrolled: null,
    DIRTY: false,
  };
  casesShared(scrollCardsMessage, params)["ScrollCards"]();
}

test("navigating repeatedly binds one scroll handler, not one per message", () => {
  const column = mountColumn();
  const bound: EventListenerOrEventListenerObject[] = [];
  const realAdd = column.addEventListener.bind(column);
  column.addEventListener = ((type: string, fn: EventListenerOrEventListenerObject, opts?: unknown) => {
    if (type === "scroll") bound.push(fn);
    realAdd(type, fn, opts as AddEventListenerOptions);
  }) as typeof column.addEventListener;

  sendScrollCards();
  sendScrollCards();
  sendScrollCards();

  // The same function object every time, which is what makes the repeat
  // registrations no-ops: addEventListener discards a duplicate (type,
  // listener, capture) triple. An anonymous handler is a new object each time,
  // so the DOM kept all three.
  expect(bound.length).toBe(3);
  expect(new Set(bound).size).toBe(1);
});

test("a column added later is bound too", () => {
  mountColumn();
  sendScrollCards();

  const second = document.createElement("div");
  second.className = "column";
  document.getElementById("document")!.append(second);
  const bound: EventListenerOrEventListenerObject[] = [];
  const realAdd = second.addEventListener.bind(second);
  second.addEventListener = ((type: string, fn: EventListenerOrEventListenerObject, opts?: unknown) => {
    if (type === "scroll") bound.push(fn);
    realAdd(type, fn, opts as AddEventListenerOptions);
  }) as typeof second.addEventListener;

  sendScrollCards();

  expect(bound.length).toBe(1);
});
