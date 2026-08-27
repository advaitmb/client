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
 *
 * The second half of the file pins the settings menu's theme picker (ticket
 * 32): what it lists, what a choice reports, and that the mark on the current
 * theme is Elm's answer rather than the click's.
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
    theme: "default",
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

test("an unknown owner leaves the field inert but not marked as forbidden", () => {
  // The first moments of a boot: the document list has not answered yet (S3).
  const [el] = mount({ owner: "unknown" });

  // Inert, so a document that turns out not to be ours cannot be renamed in
  // the meantime...
  expect(titleInput(el).disabled).toBe(true);
  // ...but nothing on screen says so, so nothing is taken back when the answer
  // arrives. `not-allowed` is what a known non-owner gets.
  expect(titleInput(el).style.cursor).toBe("");
});

test("a known non-owner is told the title is not theirs to edit", () => {
  const [el] = mount({ owner: "no" });

  expect(titleInput(el).style.cursor).toBe("not-allowed");
});

/* === The settings menu's theme picker (ticket 32) ===
 *
 * The six themes' CSS ships and `SaveThemeSetting` -> `Theme.fromLocalStore`
 * round-trips (ticket 17), but nothing constructed `ThemeChanged`: the picker
 * was removed with the rest of the SaaS chrome. These pin the producer.
 */

const settingsMenu = (el: HTMLElement) =>
  el.querySelector<HTMLElement>("#doc-settings-menu")!;

/** Every entry of the settings menu, in the order it is offered. */
const menuLabels = (el: HTMLElement) =>
  Array.from(settingsMenu(el).querySelectorAll("button")).map((b) => b.textContent);

const themeItem = (el: HTMLElement, name: string) =>
  el.querySelector<HTMLButtonElement>(`#theme-${name}`)!;

/** Collect what the picker reports, in order. */
function watchThemes(el: HTMLElement): unknown[] {
  const picked: unknown[] = [];
  el.addEventListener("gw-theme", (e) => picked.push((e as CustomEvent).detail));
  return picked;
}

test("the settings menu offers every theme whose CSS ships", () => {
  const [el] = mount({ menu: "settings" });

  // Word count first, then the picker, in the order the removed Elm picker
  // used (a203a9c's parent: Default, Dark, Classic, Gray, Green, Turquoise).
  expect(menuLabels(el)).toEqual([
    "Word count...",
    "Default",
    "Dark Mode",
    "Classic Gingkoapp",
    "Gray",
    "Green",
    "Turquoise",
  ]);
  // Real buttons, so Enter and Space activate them without this element
  // implementing either (S12).
  expect(settingsMenu(el).querySelectorAll('button[type="button"]').length).toBe(7);
});

test("choosing a theme reports its name to Elm, exactly once", () => {
  const [el] = mount({ menu: "settings" });
  const picked = watchThemes(el);

  themeItem(el, "green").click();

  expect(picked).toEqual(["green"]);
});

test("the names the picker reports are the ones a saved theme is stored under", () => {
  const [el] = mount({ menu: "settings" });
  const picked = watchThemes(el);

  for (const b of settingsMenu(el).querySelectorAll<HTMLButtonElement>('button[id^="theme-"]')) {
    b.click();
  }

  // `Theme.toValue`'s strings: what SaveThemeSetting writes into the
  // document's localStore, and what `Theme.fromLocalStore` reads back.
  expect(picked).toEqual(["default", "dark", "classic", "gray", "green", "turquoise"]);
});

test("the current theme is the marked one", () => {
  const [el] = mount({ menu: "settings", theme: "green" });

  const marked = Array.from(
    settingsMenu(el).querySelectorAll<HTMLElement>('button[aria-pressed="true"]'),
  ).map((b) => b.textContent);
  expect(marked).toEqual(["Green"]);
  // The stylesheet's hook for the same fact.
  expect(themeItem(el, "green").className).toBe("selected");
  // Every entry says where it stands, so a screen reader hears the six as a
  // set rather than one lone pressed button.
  expect(settingsMenu(el).querySelectorAll("button[aria-pressed]").length).toBe(6);
});

test("the mark moves when Elm says so, not when the button is clicked", () => {
  const [el] = mount({ menu: "settings", theme: "default" });

  themeItem(el, "dark").click();

  // Elm owns the theme (it also has to save it); the element only reports the
  // click. A mark moved here would show a theme that is not the one applied.
  expect(themeItem(el, "default").getAttribute("aria-pressed")).toBe("true");
  expect(themeItem(el, "dark").getAttribute("aria-pressed")).toBe("false");

  el.setAttribute("theme", "dark");

  expect(themeItem(el, "dark").getAttribute("aria-pressed")).toBe("true");
  expect(themeItem(el, "default").getAttribute("aria-pressed")).toBe("false");
});

test("a theme arriving does not discard in-progress typing", () => {
  const [el] = mount({ menu: "settings" });
  typeTitle(el, "My new title");

  el.setAttribute("theme", "dark");

  // E12's rule, through the attribute this ticket adds: the field belongs to
  // the user whichever attribute the re-render came from.
  expect(titleInput(el).value).toBe("My new title");
  expect(document.activeElement).toBe(titleInput(el));
});

test("the entry chosen with the keyboard still has focus after Elm answers", () => {
  const [el] = mount({ menu: "settings", theme: "default" });
  themeItem(el, "dark").focus();

  // The answer rebuilds the menu, which takes the focused node with it. A
  // keyboard user who lands back on <body> cannot try the next theme.
  el.setAttribute("theme", "dark");

  expect(document.activeElement).toBe(themeItem(el, "dark"));
});

test("Enter on a menu entry does not also reach the app's shortcuts", () => {
  const [el] = mount({ menu: "settings" });
  const escaped: string[] = [];
  const watch = (e: Event) => escaped.push((e as KeyboardEvent).key);
  document.addEventListener("keydown", watch);

  try {
    const enter = (key: string) =>
      themeItem(el, "dark").dispatchEvent(
        new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
      );
    // Mousetrap binds "enter" on `document` and ignores only form fields, so
    // an Enter that got there would open the active card's editor as well as
    // choosing the theme (the reason ticket 24's breadcrumb stops its keydown).
    enter("Enter");
    enter(" ");
    expect(escaped).toEqual([]);

    // Narrowly: the app's other keys still get through. Swallowing everything
    // would trap a keyboard user in an open menu.
    enter("Escape");
    expect(escaped).toEqual(["Escape"]);
  } finally {
    document.removeEventListener("keydown", watch);
  }
});

test("the word count entry still opens the word count", () => {
  const [el] = mount({ menu: "settings" });
  const opened: string[] = [];
  el.addEventListener("gw-wordcount", () => opened.push("wordcount"));

  el.querySelector<HTMLButtonElement>("#wordcount-menu-item")!.click();

  expect(opened).toEqual(["wordcount"]);
});

test("the header says when it has rendered, so nothing has to poll its geometry", () => {
  // The port layer fixed-positions the GitHub sync button against
  // #history-icon and used to re-measure the header every 800ms, forever, to
  // notice that the icon had moved or appeared (CODE_REVIEW.md S5). This event
  // is that news; a ResizeObserver covers the rest.
  const rendered: string[] = [];
  const watch = () => rendered.push("rendered");
  document.addEventListener("gw-header-rendered", watch);

  try {
    const [el] = mount();
    expect(rendered.length).toBe(1);

    // Every later render too: a menu opening adds a row and moves the icons.
    el.setAttribute("menu", "history");
    expect(rendered.length).toBe(2);
  } finally {
    document.removeEventListener("gw-header-rendered", watch);
  }
});
