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
 * The second half of the file pins the menus and the controls that open them:
 * the settings menu's theme picker (ticket 32) — what it lists, what a choice
 * reports, and that the mark on the current theme is Elm's answer rather than
 * the click's — then the three menu icons and the history menu (ticket 33), and
 * the export menu's two radio groups (ticket 34).
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

/**
 * Activate a control the way a keyboard does. jsdom implements no activation
 * behaviour, so this is the platform's rule written out: the keydown, and then
 * — only for a control the browser itself activates from the keyboard, and
 * only if nothing cancelled the keydown — the click that follows it. A
 * `<div onclick>` gets the keydown and nothing more, which is exactly what a
 * keyboard user gets from one.
 */
function press(node: HTMLElement, key: string) {
  const live = node.dispatchEvent(
    new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
  );
  const activates =
    node instanceof HTMLButtonElement && (key === "Enter" || key === " ");
  if (live && activates) node.click();
}

/**
 * Run `body` with a document-level keydown listener watching for leaks — the
 * stand-in for Mousetrap, which binds the app's shortcuts there.
 */
function withDocumentKeys(body: (escaped: string[]) => void) {
  const escaped: string[] = [];
  const watch = (e: Event) => escaped.push((e as KeyboardEvent).key);
  document.addEventListener("keydown", watch);
  try {
    body(escaped);
  } finally {
    document.removeEventListener("keydown", watch);
  }
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

  withDocumentKeys((escaped) => {
    const entry = themeItem(el, "dark");
    // Mousetrap binds "enter" on `document` and ignores only form fields, so
    // an Enter that got there would open the active card's editor as well as
    // choosing the theme (the reason ticket 24's breadcrumb stops its keydown).
    press(entry, "Enter");
    press(entry, " ");
    expect(escaped).toEqual([]);

    // Narrowly: the app's other keys still get through. Swallowing everything
    // would trap a keyboard user in an open menu.
    press(entry, "Escape");
    expect(escaped).toEqual(["Escape"]);
  });
});

test("the word count entry still opens the word count", () => {
  const [el] = mount({ menu: "settings" });
  const opened: string[] = [];
  el.addEventListener("gw-wordcount", () => opened.push("wordcount"));

  el.querySelector<HTMLButtonElement>("#wordcount-menu-item")!.click();

  expect(opened).toEqual(["wordcount"]);
});

/* === The three menu icons (ticket 33) ===
 *
 * Ticket 32 made the settings menu's *entries* real buttons, and left the
 * honest gap: the icons that open the menus were `div`s with `onclick`, so a
 * keyboard-only user could not reach the picker at all. These pin the icons as
 * controls — and the history menu's own two, which the history icon now opens
 * for a keyboard user.
 */

/** The three icons, by the menu each one owns. */
const ICONS: Array<[id: string, menu: string, label: string]> = [
  ["history-icon", "history", "Version history"],
  ["doc-settings-icon", "settings", "Document settings"],
  ["export-icon", "export", "Export or print"],
];

const control = (el: HTMLElement, id: string) =>
  el.querySelector<HTMLElement>(`#${id}`)!;

/** Collect what the icons ask Elm for, in order. */
function watchMenus(el: HTMLElement): unknown[] {
  const asked: unknown[] = [];
  el.addEventListener("gw-menu", (e) => asked.push((e as CustomEvent).detail));
  return asked;
}

test("each menu icon is a control the keyboard can reach", () => {
  const [el] = mount();

  for (const [id, , label] of ICONS) {
    const icon = control(el, id);
    // A real button, so the platform gives Enter and Space activation and a
    // focus ring without this element implementing any of it (S12).
    expect([id, icon.tagName]).toEqual([id, "BUTTON"]);
    expect([id, icon.getAttribute("type")]).toEqual([id, "button"]);
    expect([id, icon.tabIndex]).toEqual([id, 0]);
    icon.focus();
    expect(document.activeElement).toBe(icon);
    // The label is a tooltip on screen and the accessible name in a screen
    // reader: the icon is a bare glyph, so there is no text to fall back on.
    expect([id, icon.getAttribute("aria-label")]).toEqual([id, label]);
    expect([id, icon.getAttribute("title")]).toEqual([id, label]);
  }
});

test("Enter on an icon asks for the menu that icon owns", () => {
  const [el] = mount();
  const asked = watchMenus(el);

  // Nothing sets `menu` in between, so each icon is still closed: three
  // presses, three requests to open, in the order they were pressed.
  for (const [id] of ICONS) {
    control(el, id).focus();
    press(control(el, id), "Enter");
  }

  expect(asked).toEqual(["history", "settings", "export"]);
});

test("Space on an open icon closes its menu again", () => {
  const [el] = mount({ menu: "settings" });
  const asked = watchMenus(el);

  press(control(el, "doc-settings-icon"), " ");

  // The icon is a toggle: Elm is told to close the menu it has open, not to
  // open it a second time.
  expect(asked).toEqual(["none"]);
});

test("an icon says whether its menu is open", () => {
  const [el] = mount({ menu: "settings" });

  expect(control(el, "doc-settings-icon").getAttribute("aria-expanded")).toBe("true");
  expect(control(el, "export-icon").getAttribute("aria-expanded")).toBe("false");

  // Elm's answer, like the theme mark: the icon reports the click and waits.
  el.setAttribute("menu", "export");

  expect(control(el, "doc-settings-icon").getAttribute("aria-expanded")).toBe("false");
  expect(control(el, "export-icon").getAttribute("aria-expanded")).toBe("true");
});

test("Enter and Space on an icon do not also reach the app's shortcuts", () => {
  const [el] = mount();

  withDocumentKeys((escaped) => {
    for (const [id] of ICONS) {
      // Mousetrap binds "enter" on `document` and ignores only form fields, so
      // an Enter that got there would open the active card's editor as well as
      // the menu (ticket 24's breadcrumb, ticket 32's menu entries).
      press(control(el, id), "Enter");
      press(control(el, id), " ");
    }
    expect(escaped).toEqual([]);

    // Narrowly: the app's other keys still get through, so an icon is not a
    // place a keyboard user gets stuck.
    press(control(el, "export-icon"), "Escape");
    expect(escaped).toEqual(["Escape"]);
  });
});

test("the icon keeps the focus while its menu opens and closes", () => {
  const [el] = mount();
  control(el, "doc-settings-icon").focus();

  // Elm's answer rebuilds everything but the title, so without ticket 32's
  // refocus the user who opened the menu is dropped on <body> — unable to tab
  // into what they just opened, or to close it again.
  el.setAttribute("menu", "settings");
  expect(document.activeElement).toBe(control(el, "doc-settings-icon"));

  el.setAttribute("menu", "none");
  expect(document.activeElement).toBe(control(el, "doc-settings-icon"));
});

test("the menu an icon opens is the next thing in the tab order", () => {
  const [el] = mount({ menu: "settings" });

  const icon = control(el, "doc-settings-icon");
  const first = settingsMenu(el).querySelector("button")!;
  // Tab order is document order here (nothing sets tabindex), so this is what
  // makes the picker reachable: Tab off the icon lands in the menu it opened.
  expect(icon.compareDocumentPosition(first) & Node.DOCUMENT_POSITION_FOLLOWING)
    .toBeGreaterThan(0);
  const focusable = Array.from(
    el.querySelectorAll<HTMLElement>("button, input:not([disabled])"),
  );
  expect(focusable[focusable.indexOf(icon) + 1]).toBe(first);
});

/* The history menu's own controls: unreachable until now for the same reason
 * the picker was, and named in ticket 32's Comments as landing with the icons.
 */

test("the history menu's controls are keyboard-operable", () => {
  const [el] = mount({ menu: "history", history: JSON.stringify({ index: 2, max: 5 }) });
  const reported: string[] = [];
  for (const name of ["gw-history-restore", "gw-history-cancel"]) {
    el.addEventListener(name, () => reported.push(name));
  }

  for (const id of ["history-restore", "history-close-button"]) {
    const button = control(el, id);
    expect([id, button.tagName]).toEqual([id, "BUTTON"]);
    expect([id, button.getAttribute("type")]).toEqual([id, "button"]);
    button.focus();
    expect(document.activeElement).toBe(button);
  }

  press(control(el, "history-restore"), "Enter");
  press(control(el, "history-close-button"), " ");

  // Both exits are the ✕'s behaviour since ticket 34 (Page.App's
  // CancelHistory: the working tree goes back to the version the view opened
  // at), and the menu still has to offer its own, where a mouse expects it.
  expect(reported).toEqual(["gw-history-restore", "gw-history-cancel"]);
});

test("the history slider says what it moves through", () => {
  const [el] = mount({ menu: "history", history: JSON.stringify({ index: 2, max: 5 }) });

  // A range input is keyboard-operable and Mousetrap leaves form fields alone,
  // so the slider needed no work in ticket 33 — but a bare one announces itself
  // as "slider, 3 of 6" and nothing about what the 3 is (ticket 34).
  const slider = el.querySelector<HTMLInputElement>("#history-slider")!;
  expect(slider.getAttribute("aria-label")).toBe("Document version");
});

test("Enter and Space in the history menu do not reach the app's shortcuts", () => {
  const [el] = mount({ menu: "history", history: JSON.stringify({ index: 2, max: 5 }) });

  withDocumentKeys((escaped) => {
    for (const id of ["history-restore", "history-close-button"]) {
      press(control(el, id), "Enter");
      press(control(el, id), " ");
    }
    expect(escaped).toEqual([]);
  });
});

/* === The export menu's two rows of toggles (ticket 34) ===
 *
 * Eight `div`s with `onclick`, styled as two segmented controls: what to export
 * (Everything / Current Subtree / Leaves-only / Current Column) and in which
 * format (Word / Plain Text / OPML / JSON). Exactly one of each four is in
 * effect, which makes each row a radio group rather than four toggles — and
 * mouse-only, for the reason ticket 33's icons were.
 *
 * So: `<button role="radio">` in a named `role="radiogroup"`, with the keyboard
 * behaviour the platform gives a real radio and not a button — one tab stop for
 * the group, and the arrow keys moving through it, the choice following the
 * focus. Not `aria-pressed` (ticket 32's theme entries): eight independent
 * toggles is not what a segmented control of four exclusive options is, and
 * eight tab stops is what the ARIA pattern exists to avoid.
 */

/** The two rows, by the group each one is: id, child id prefix, name, values. */
const EXPORT_GROUPS: Array<
  [id: string, prefix: string, label: string, values: string[]]
> = [
  [
    "export-selection",
    "export-select-",
    "What to export",
    ["all", "subtree", "leaves", "column"],
  ],
  [
    "export-format",
    "export-format-",
    "Export format",
    ["word", "text", "opml", "json"],
  ],
];

/** The export menu open, with Elm's answer for both settings. */
function mountExport(selection = "all", format = "word") {
  const [el] = mount({
    menu: "export",
    "export-settings": JSON.stringify({ selection, format }),
  });
  const picked: Array<[string, unknown]> = [];
  for (const name of ["gw-export-selection", "gw-export-format"]) {
    el.addEventListener(name, (e) => picked.push([name, (e as CustomEvent).detail]));
  }
  return { el, picked };
}

/**
 * An arrow key on the focused option. Returns what the platform would read
 * from it — false if the element cancelled the event, and so cancelled the
 * page scroll an unhandled arrow key would cause.
 */
function arrow(node: HTMLElement, key: string) {
  node.focus();
  return node.dispatchEvent(
    new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
  );
}

test("each row of export toggles is a named radio group of real controls", () => {
  const { el } = mountExport();

  for (const [id, prefix, label, values] of EXPORT_GROUPS) {
    const group = control(el, id);
    expect([id, group.getAttribute("role")]).toEqual([id, "radiogroup"]);
    // A group with no name announces as "radio group" and nothing about which
    // of the two it is; neither row has a heading on screen to borrow.
    expect([id, group.getAttribute("aria-label")]).toEqual([id, label]);

    const radios = Array.from(group.querySelectorAll<HTMLElement>('button[role="radio"]'));
    expect(radios.map((r) => r.id)).toEqual(values.map((v) => `${prefix}${v}`));
    for (const r of radios) {
      expect([r.id, r.getAttribute("type")]).toEqual([r.id, "button"]);
    }
  }
});

test("the option in effect is the checked one, and the group's only tab stop", () => {
  const { el } = mountExport("leaves", "opml");

  // Eight options, two tab stops: Tab reaches each group once and the arrow
  // keys move within it. Eight stops would make Tab the only way through, and
  // put seven of them between the export icon and whatever follows it.
  const tabStops = Array.from(el.querySelectorAll<HTMLElement>("#export-menu button"))
    .filter((b) => b.tabIndex === 0)
    .map((b) => b.id);
  expect(tabStops).toEqual(["export-select-leaves", "export-format-opml"]);

  const checked = Array.from(
    el.querySelectorAll<HTMLElement>('#export-menu button[aria-checked="true"]'),
  ).map((b) => b.id);
  expect(checked).toEqual(["export-select-leaves", "export-format-opml"]);
  // The stylesheet's hook for the same fact.
  expect(control(el, "export-select-leaves").className).toBe("selected");
});

test("the checked option is Elm's answer, not the click", () => {
  const { el } = mountExport("all", "word");

  control(el, "export-format-json").click();

  // Elm owns the export settings — it is what builds the file — so the element
  // reports the choice and waits, as ticket 32's theme picker does.
  expect(control(el, "export-format-word").getAttribute("aria-checked")).toBe("true");
  expect(control(el, "export-format-json").getAttribute("aria-checked")).toBe("false");

  el.setAttribute("export-settings", JSON.stringify({ selection: "all", format: "json" }));

  expect(control(el, "export-format-json").getAttribute("aria-checked")).toBe("true");
  expect(control(el, "export-format-word").getAttribute("aria-checked")).toBe("false");
});

test("clicking an export option still reports it to Elm", () => {
  const { el, picked } = mountExport();

  control(el, "export-select-subtree").click();
  control(el, "export-format-opml").click();

  expect(picked).toEqual([
    ["gw-export-selection", "subtree"],
    ["gw-export-format", "opml"],
  ]);
});

test("Enter and Space choose an export option, and stop there", () => {
  const { el, picked } = mountExport();

  withDocumentKeys((escaped) => {
    press(control(el, "export-select-subtree"), "Enter");
    press(control(el, "export-format-opml"), " ");
    // As everywhere else in the header: an Enter that reached `document` would
    // open the active card's editor as well as choosing the option.
    expect(escaped).toEqual([]);
  });

  expect(picked).toEqual([
    ["gw-export-selection", "subtree"],
    ["gw-export-format", "opml"],
  ]);
});

test("the arrow keys move through a row of export options, wrapping, and choose", () => {
  const { el, picked } = mountExport("all", "word");
  const from = (id: string, key: string) => {
    arrow(control(el, id), key);
    return document.activeElement;
  };

  // Both axes: the group is a row on screen, and Left/Right and Up/Down are
  // the same movement in the ARIA radio pattern.
  expect(from("export-select-all", "ArrowRight")).toBe(control(el, "export-select-subtree"));
  expect(from("export-select-subtree", "ArrowDown")).toBe(control(el, "export-select-leaves"));
  expect(from("export-select-leaves", "ArrowUp")).toBe(control(el, "export-select-subtree"));
  // Wrapping, in both directions, so four options are a loop and not a wall.
  expect(from("export-select-all", "ArrowLeft")).toBe(control(el, "export-select-column"));
  expect(from("export-select-column", "ArrowRight")).toBe(control(el, "export-select-all"));
  // The other row is the same group, wired the same way.
  expect(from("export-format-word", "ArrowRight")).toBe(control(el, "export-format-text"));

  // The arrow does not only move the focus: in a radio group the selection
  // follows it, so every step is a choice reported to Elm — which is also why
  // nothing checked moves here, Elm having answered none of them.
  expect(picked).toEqual([
    ["gw-export-selection", "subtree"],
    ["gw-export-selection", "leaves"],
    ["gw-export-selection", "subtree"],
    ["gw-export-selection", "column"],
    ["gw-export-selection", "all"],
    ["gw-export-format", "text"],
  ]);
});

test("the arrow keys in the export menu do not also reach the app's shortcuts", () => {
  const { el } = mountExport();

  withDocumentKeys((escaped) => {
    for (const key of ["ArrowRight", "ArrowLeft", "ArrowDown", "ArrowUp"]) {
      // Cancelled, so the page does not scroll under the open menu as well.
      expect([key, arrow(control(el, "export-select-all"), key)]).toEqual([key, false]);
    }
    // Mousetrap binds "left"/"right"/"up"/"down" on `document` to move between
    // cards, so an arrow that got there would move the card cursor behind the
    // open menu as well as the choice inside it.
    expect(escaped).toEqual([]);

    // Narrowly, as ever: Escape still closes the menu.
    press(control(el, "export-select-all"), "Escape");
    expect(escaped).toEqual(["Escape"]);
  });
});

test("the option chosen with an arrow key still has focus after Elm answers", () => {
  const { el } = mountExport("all", "word");

  arrow(control(el, "export-select-all"), "ArrowRight");

  // Elm's answer rebuilds everything but the title, so without ticket 32's
  // refocus-by-id the arrow key that made the choice also drops the user on
  // <body> — and the next arrow key moves a card instead of the choice.
  el.setAttribute("export-settings", JSON.stringify({ selection: "subtree", format: "word" }));

  const chosen = control(el, "export-select-subtree");
  expect(document.activeElement).toBe(chosen);
  // And the group's one tab stop moved with the choice.
  expect(chosen.tabIndex).toBe(0);
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
