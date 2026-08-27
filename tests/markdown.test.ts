/**
 * <gw-markdown> attribute → DOM contract (ADR-0001 seam 3).
 *
 * The element's public surface is its attributes (src, card-id), the DOM it
 * renders, and the window.checkboxClicked global that GFM task checkboxes
 * call back through (defined by src/shared/doc.js in the app).
 */
import { afterEach, expect, test } from "bun:test";
import "../src/ui/markdown";

declare global {
  interface Window {
    checkboxClicked?: (cardId: string, checkboxNumber: number) => void;
  }
}

function mount(attrs: Record<string, string>): HTMLElement {
  const el = document.createElement("gw-markdown");
  for (const [name, value] of Object.entries(attrs)) {
    el.setAttribute(name, value);
  }
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  document.body.replaceChildren();
  delete window.checkboxClicked;
});

test("renders the src attribute as markdown", () => {
  const el = mount({ src: "# A title\n\nwith **emphasis**" });

  expect(el.querySelector("h1")?.textContent).toBe("A title");
  expect(el.querySelector("strong")?.textContent).toBe("emphasis");
});

test("re-renders when the src attribute changes", () => {
  const el = mount({ src: "first draft" });
  el.setAttribute("src", "second draft");

  expect(el.textContent).toContain("second draft");
  expect(el.textContent).not.toContain("first draft");
});

test("renders CriticMarkup insertions and deletions as ins/del.diff", () => {
  const el = mount({ src: "kept {++added++} and {--removed--}" });

  expect(el.querySelector("ins.diff")?.textContent).toBe("added");
  expect(el.querySelector("del.diff")?.textContent).toBe("removed");
});

test("task checkboxes are enabled and report card id and 1-based index", () => {
  const clicks: Array<[string, number]> = [];
  window.checkboxClicked = (cardId, n) => clicks.push([cardId, n]);

  const el = mount({ src: "- [ ] first task\n- [x] second task", "card-id": "card-7" });
  const boxes = el.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');

  expect(boxes.length).toBe(2);
  expect(boxes[1]!.disabled).toBe(false);
  boxes[1]!.click();

  expect(clicks).toEqual([["card-7", 2]]);
});
