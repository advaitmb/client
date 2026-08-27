/**
 * <gw-header>'s title field (ADR-0001 seam 3).
 *
 * The header is the app's one *persistent* custom element: Elm re-renders it
 * on a 9-second clock tick (the `save` attribute carries `now`), plus whenever
 * a menu opens, an export setting changes or the document is renamed. The
 * title input is uncontrolled — Elm's `doc-title` is the last *committed*
 * name, never what is being typed — so a re-render that rebuilds the input
 * from that attribute throws away in-progress typing (CODE_REVIEW.md E12).
 *
 * What these pin: while the field has focus it belongs to the user, whatever
 * attribute changed, and the rest of the header still updates around it.
 */
import { afterEach, expect, test } from "bun:test";
import "../src/ui/header";

const TITLE_EVENTS = [
  "gw-title-input",
  "gw-title-commit",
  "gw-title-cancel",
  "gw-title-focus",
];

function mount(attrs: Record<string, string> = {}): [HTMLElement, string[]] {
  const el = document.createElement("gw-header");
  const defaults = {
    "doc-title": "Untitled",
    owner: "yes",
    menu: "none",
    save: saveAttr(1000),
  };
  for (const [name, value] of Object.entries({ ...defaults, ...attrs })) {
    el.setAttribute(name, value);
  }
  document.body.appendChild(el);

  const reported: string[] = [];
  for (const name of TITLE_EVENTS) {
    el.addEventListener(name, () => reported.push(name));
  }
  return [el, reported];
}

/** The `save` JSON Elm sends; `now` is what the clock tick moves. */
const saveAttr = (now: number) =>
  JSON.stringify({
    dirty: false,
    lastLocalSave: 0,
    lastRemoteSave: 0,
    now,
  });

/**
 * Re-queried on purpose: today's render replaces the input with a new node, so
 * a test holding the old one would pass while the DOM shows something else.
 */
const titleInput = (el: HTMLElement) =>
  el.querySelector<HTMLInputElement>("#title-rename")!;

const shadowText = (el: HTMLElement) =>
  el.querySelector<HTMLElement>(".title-grow-wrap .shadow")!.textContent;

const saveLabel = (el: HTMLElement) =>
  el.querySelector<HTMLElement>("#save-indicator span")!.textContent;

/** Click into the field and type, the way a rename starts. */
function typeTitle(el: HTMLElement, value: string) {
  const input = titleInput(el);
  input.focus();
  input.value = value;
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return input;
}

afterEach(() => {
  document.body.replaceChildren();
});

test("the clock tick does not discard in-progress typing", () => {
  const [el] = mount();
  typeTitle(el, "My new title");

  // The 9-second tick: only `save` changes, and only its `now` field.
  el.setAttribute("save", saveAttr(10000));

  expect(titleInput(el).value).toBe("My new title");
});

test("the clock tick keeps the caret where it was", () => {
  const [el] = mount();
  const input = typeTitle(el, "My new title");
  input.setSelectionRange(2, 6);

  el.setAttribute("save", saveAttr(10000));

  const after = titleInput(el);
  expect(document.activeElement).toBe(after);
  expect([after.selectionStart, after.selectionEnd]).toEqual([2, 6]);
});

test("the clock tick reports nothing to Elm about the title", () => {
  const [el, reported] = mount();
  typeTitle(el, "My new title");
  reported.length = 0;

  el.setAttribute("save", saveAttr(10000));

  // A re-render is not the user touching the field: a focus reported here
  // makes Elm select-all the title (TitleFocused), and a commit renames the
  // document from a value the user has not finished typing.
  expect(reported).toEqual([]);
});

test("a menu opening does not discard in-progress typing", () => {
  const [el] = mount();
  typeTitle(el, "My new title");

  el.setAttribute("menu", "settings");

  expect(titleInput(el).value).toBe("My new title");
  expect(el.querySelector("#doc-settings-menu")).not.toBeNull();
});

test("a rename arriving while the field is focused does not overwrite it", () => {
  const [el] = mount();
  typeTitle(el, "My new title");

  // A second tab (or a collaborator) committed a different name.
  el.setAttribute("doc-title", "Renamed elsewhere");

  expect(titleInput(el).value).toBe("My new title");
});

test("a rename arriving while the field is idle updates it", () => {
  const [el] = mount();

  el.setAttribute("doc-title", "Renamed elsewhere");

  expect(titleInput(el).value).toBe("Renamed elsewhere");
  expect(shadowText(el)).toBe("Renamed elsewhere");
});

test("the sizing shadow follows the text being typed", () => {
  const [el] = mount();
  typeTitle(el, "My new title");

  el.setAttribute("save", saveAttr(10000));

  expect(shadowText(el)).toBe("My new title");
});

test("the save indicator still updates while the title is being typed", () => {
  const [el] = mount();
  typeTitle(el, "My new title");
  expect(saveLabel(el)).toBe("Synced");

  el.setAttribute(
    "save",
    JSON.stringify({ dirty: true, lastLocalSave: 0, lastRemoteSave: 0, now: 10000 }),
  );

  expect(saveLabel(el)).toBe("Unsaved Changes...");
  expect(titleInput(el).value).toBe("My new title");
});

test("a keystroke still reaches Elm after a re-render, exactly once", () => {
  const [el, reported] = mount();
  typeTitle(el, "My new");
  el.setAttribute("save", saveAttr(10000));
  reported.length = 0;

  // The field already has focus, so this is a keystroke and nothing else.
  const input = titleInput(el);
  input.value = "My new title";
  input.dispatchEvent(new Event("input", { bubbles: true }));

  expect(reported).toEqual(["gw-title-input"]);
});

test("the field is disabled for a non-owner and enabled when ownership arrives", () => {
  const [el] = mount({ owner: "no" });
  expect(titleInput(el).disabled).toBe(true);

  el.setAttribute("owner", "yes");

  expect(titleInput(el).disabled).toBe(false);
});
