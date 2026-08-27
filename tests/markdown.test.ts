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

// Hostile card content (CODE_REVIEW.md C1, ADR-0003): cards come from
// collaborators, JSON import, and drag-drop, so anything executable must be
// stripped while ordinary markup survives.

test("script tags in card content are stripped", () => {
  const el = mount({ src: "before <script>window.pwned = true</script> after" });

  expect(el.querySelector("script")).toBeNull();
  expect(el.textContent).toContain("before");
  expect(el.textContent).toContain("after");
});

test("event-handler attributes are stripped from inline HTML", () => {
  const el = mount({ src: '<img src=x onerror="window.pwned = true"> and <b onclick="window.pwned = true">bold</b>' });

  expect(el.querySelector("[onerror]")).toBeNull();
  expect(el.querySelector("[onclick]")).toBeNull();
  // The harmless parts of the markup stay.
  expect(el.querySelector("img")).not.toBeNull();
  expect(el.querySelector("b")?.textContent).toBe("bold");
});

test("javascript: URLs are neutralized in markdown and inline HTML links", () => {
  const el = mount({
    src: '[md link](javascript:alert(1)) <a href="jAvAsCrIpT:alert(1)">raw link</a>',
  });

  const hrefs = Array.from(el.querySelectorAll("a")).map(
    (a) => a.getAttribute("href") ?? "",
  );
  expect(hrefs.some((h) => h.toLowerCase().includes("javascript:"))).toBe(false);
  // The link text itself is not lost.
  expect(el.textContent).toContain("md link");
  expect(el.textContent).toContain("raw link");
});

test("style and iframe elements are removed", () => {
  const el = mount({
    src: '<style>body { display: none; }</style><iframe src="https://evil.example"></iframe>ok',
  });

  expect(el.querySelector("style")).toBeNull();
  expect(el.querySelector("iframe")).toBeNull();
  expect(el.textContent).toContain("ok");
});

test("ordinary markdown output survives sanitizing", () => {
  const el = mount({
    src: "# Title\n\n[safe](https://example.com/page)\n\n![alt text](https://example.com/pic.png)\n\n`code`",
  });

  expect(el.querySelector("h1")?.textContent).toBe("Title");
  expect(el.querySelector("a")?.getAttribute("href")).toBe("https://example.com/page");
  expect(el.querySelector("img")?.getAttribute("src")).toBe("https://example.com/pic.png");
  expect(el.querySelector("code")?.textContent).toBe("code");
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
