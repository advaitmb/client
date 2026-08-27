/**
 * Which keystrokes the app's shortcuts act on (ADR-0001 seam 14).
 *
 * Mousetrap binds the whole map on `document` — `h`/`j`/`k`/`l`, the arrows,
 * `w`, `/`, `esc`, the mod-chords — and asks `stopCallback` whether a matched
 * keystroke is its business. `shortcutReachesApp` is that decision, and these
 * pin the scope rule ticket 35 exists to settle: a keystroke aimed at a control
 * in the app's chrome does not also act on the document behind it, while a
 * keystroke with focus on the body, in a card, or in the fields marked for it
 * still does.
 *
 * The fixtures are the real elements, not stand-in markup, because the rule is
 * about *where* a control is: it is asked about `<gw-header>`'s own buttons, so
 * a header that grew a control outside itself would show up here. Every header
 * control is focused before the question is asked, so a control the keyboard
 * cannot reach at all fails these too.
 */
import { afterEach, expect, test } from "bun:test";
import { shortcutReachesApp } from "../src/shared/shortcut-scope";
import "../src/ui/header";
import "../src/ui/sidebar";
import "../src/ui/template-modal";
import "../src/ui/switcher-modal";
import "../src/ui/tree";
// tree.ts renders each card's content as a <gw-markdown>, which has to be
// registered for the link inside one to exist.
import "../src/ui/markdown";

/** The `save` JSON Elm hands the header; it renders the save indicator from it. */
const SAVE = JSON.stringify({
  dirty: false,
  lastLocalSave: 0,
  lastRemoteSave: 0,
  now: 1000,
});

function header(attrs: Record<string, string> = {}): HTMLElement {
  const el = document.createElement("gw-header");
  const defaults = {
    "doc-title": "Untitled",
    owner: "yes",
    menu: "none",
    save: SAVE,
    theme: "default",
    "export-settings": JSON.stringify({ selection: "all", format: "word" }),
    history: JSON.stringify({ index: 3, max: 6 }),
  };
  for (const [name, value] of Object.entries({ ...defaults, ...attrs })) {
    el.setAttribute(name, value);
  }
  document.body.append(el);
  return el;
}

const control = (el: HTMLElement, id: string) =>
  el.querySelector<HTMLElement>(`#${id}`)!;

/**
 * The header's controls that are not form fields, and the menu that has to be
 * open for each: the three icons, both kinds of menu entry (a plain command and
 * a marked choice), an option from each export radio group, and the history
 * menu's two buttons.
 */
const HEADER_CONTROLS: Array<[menu: string, id: string]> = [
  ["none", "history-icon"],
  ["none", "doc-settings-icon"],
  ["none", "export-icon"],
  ["settings", "wordcount-menu-item"],
  ["settings", "theme-dark"],
  ["export", "export-select-subtree"],
  ["export", "export-format-text"],
  ["history", "history-restore"],
  ["history", "history-close-button"],
];

/** And the header's two fields, which Mousetrap's own rule already covered. */
const HEADER_FIELDS: Array<[menu: string, id: string]> = [
  ["none", "title-rename"],
  ["history", "history-slider"],
];

/** Focus the named control and ask what a keystroke on it reaches. */
function reachesFrom(menu: string, id: string, combo: string) {
  const el = header({ menu });
  control(el, id).focus();
  const answer = shortcutReachesApp(document.activeElement, combo);
  el.remove();
  return answer;
}

afterEach(() => {
  document.body.replaceChildren();
});

test("no kind of header control lets a letter shortcut through", () => {
  // `j` moves the card cursor down. Every one of these is a real control since
  // tickets 32-34, so it holds the focus after being used — and a button is not
  // a form field, which is all Mousetrap's own rule ignores: typing `j` with the
  // export menu open moved the card cursor behind the open menu.
  for (const [menu, id] of [...HEADER_CONTROLS, ...HEADER_FIELDS]) {
    expect([id, reachesFrom(menu, id, "j")]).toEqual([id, false]);
  }
});

test("nor does any other unmodified shortcut, the arrows included", () => {
  // What a button, a link or a radio is operated with, plus everything else
  // that is just typing. `w` would open the word count over the open menu, `/`
  // would jump the focus to the search field, and the four arrows are how
  // Mousetrap moves between cards — which is why ticket 34's radio groups had
  // to stop them one control at a time. `shift+enter` counts as unmodified:
  // shift is what typing looks like.
  for (const combo of ["w", "/", "[", "]", "?", "left", "down", "up", "right", "shift+enter"]) {
    expect([combo, reachesFrom("settings", "theme-dark", combo)]).toEqual([combo, false]);
  }
});

test("Escape still reaches the app from every header control", () => {
  // Escape is the way out of the chrome — Elm owns which menu is open and no
  // control here closes itself — so it is the one unmodified key a control must
  // not swallow.
  for (const [menu, id] of HEADER_CONTROLS) {
    expect([id, reachesFrom(menu, id, "esc")]).toEqual([id, true]);
  }
});

test("a chord still reaches the app from a header control", () => {
  // No button, link or radio interprets a modifier chord, so `mod+s` means save
  // wherever it is pressed — and the app's *override* of the browser's own
  // shortcuts rides on the keystroke reaching the handler: `needOverride`
  // cancels `mod+s`, `mod+o` and `alt+0`–`alt+6` from inside it, so a chord
  // stopped here would open the browser's Save-page dialog instead of doing
  // nothing at all.
  for (const combo of ["mod+s", "mod+o", "mod+z", "mod+shift+z", "alt+j", "alt+3"]) {
    expect([combo, reachesFrom("settings", "theme-dark", combo)]).toEqual([combo, true]);
  }
});

test("a form field in the chrome consumes Escape and the chords as well", () => {
  // Mousetrap's form-field rule, kept whole rather than narrowed to match the
  // exemptions the chrome's *buttons* get: the title field handles Escape
  // itself (it reverts the rename through `gw-title-cancel`), and a chord in a
  // field is the field's — `mod+v` there is a paste into the title, not into
  // the document. So a field is asked about before either exemption.
  for (const [menu, id] of HEADER_FIELDS) {
    for (const combo of ["esc", "mod+v"]) {
      expect([id, combo, reachesFrom(menu, id, combo)]).toEqual([id, combo, false]);
    }
  }
});

test("with nothing focused the shortcuts are the document's", () => {
  // The deliberate case, and the common one: the header is on the page but
  // holds no focus, so `j` moves the card cursor, which is the whole point of
  // the map.
  header();

  expect(shortcutReachesApp(document.body, "j")).toBe(true);
});

test("a keystroke with no element behind it is the app's", () => {
  // `stopCallback` is handed `e.target`, which for a keystroke dispatched at
  // the document itself is the document — no `closest`, and no control it could
  // have been meant for.
  expect(shortcutReachesApp(document, "j")).toBe(true);
  expect(shortcutReachesApp(null, "j")).toBe(true);
});

test("a card and its content are not chrome, link and all", () => {
  const tree = document.createElement("gw-tree");
  tree.setAttribute("tree", JSON.stringify([[[
    {
      id: "card-one",
      content: "see [the guide](http://commonmark.org/help)",
      hasChildren: false,
      isLast: true,
    },
  ]]]));
  tree.setAttribute("view-state", JSON.stringify({
    active: "card-one",
    editing: null,
    ancestors: [],
    descendants: [],
  }));
  document.body.append(tree);

  // Card content is the document, not the chrome. A link opened in a new tab
  // leaves the focus on itself in this one, and the next `j` is still a card
  // move — which is why the rule is about the region and not about whether the
  // focused thing happens to be a control.
  const card = tree.querySelector<HTMLElement>("#card-card-one")!;
  const link = card.querySelector<HTMLElement>("gw-markdown a")!;
  link.focus();

  expect(shortcutReachesApp(card, "j")).toBe(true);
  expect(shortcutReachesApp(link, "j")).toBe(true);
});

test("the same link inside a modal is the modal's", () => {
  const modal = document.createElement("gw-template-modal");
  document.body.append(modal);

  const link = modal.querySelector<HTMLElement>("#template-new")!;
  link.focus();

  // Same element, opposite answer: the rule generalizes to the modals without
  // the call site naming any of them, and `<a>` versus `<button>` never enters
  // into it.
  expect(shortcutReachesApp(document.activeElement, "j")).toBe(false);
  expect(shortcutReachesApp(document.activeElement, "esc")).toBe(true);
});

test("the sidebar gets the rule too, without being named at the call site", () => {
  const rail = document.createElement("gw-sidebar");
  rail.setAttribute("docs", "[]");
  document.body.append(rail);

  // The rail's own controls are still `div`s (CODE_REVIEW.md S12's remainder),
  // so this is the keystroke arriving from inside the region rather than from a
  // focusable control: the answer is the region's either way, and it is already
  // right for the day those `div`s become buttons.
  const hamburger = rail.querySelector<HTMLElement>("#hamburger-icon")!;
  expect(shortcutReachesApp(hamburger, "j")).toBe(false);
  expect(shortcutReachesApp(hamburger, "esc")).toBe(true);
});

test("the switcher's search box keeps the shortcuts it is marked for", () => {
  const switcher = document.createElement("gw-switcher-modal");
  switcher.setAttribute("docs", JSON.stringify([{ id: "a", name: "A" }]));
  document.body.append(switcher);

  const input = switcher.querySelector<HTMLElement>("#switcher-input")!;

  // `input#switcher-input.mousetrap` — the class is Mousetrap's own opt-in, and
  // the switcher depends on it: the arrows move through the document list,
  // Enter opens the selected one and `mod+o` closes the modal, all of them
  // through `Page.App`'s FileSwitcher branch. So `.mousetrap` is asked first,
  // ahead of both the form-field rule and the chrome this modal is part of.
  for (const combo of ["down", "up", "enter", "mod+o", "esc"]) {
    expect([combo, shortcutReachesApp(input, combo)]).toEqual([combo, true]);
  }
});

test("the card editor keeps the shortcuts, Tab included", () => {
  // What `gw-textarea` puts on the page: it copies its own `class` onto the
  // inner textarea (`defineCustomTextarea`'s connectedCallback in
  // src/shared/doc-helpers.js), which is the node a keystroke lands on.
  const editor = document.createElement("textarea");
  editor.setAttribute("class", "edit mousetrap");
  document.body.append(editor);

  // `mod+enter` saves, `esc` cancels the edit, `alt+3` sets a heading level —
  // the shortcuts are half of what editing a card is. Tab is bound to insert
  // two spaces, and this is the only field that wants that.
  for (const combo of ["mod+enter", "esc", "alt+3", "tab"]) {
    expect([combo, shortcutReachesApp(editor, combo)]).toEqual([combo, true]);
  }
});

test("the search field is left exactly as Mousetrap had it", () => {
  // Elm renders this one (`Doc.UI.viewSearchField`), outside every chrome
  // element and with no `.mousetrap` class: typing a letter into it must reach
  // the field and nothing else, which the form-field rule already ensured.
  const search = document.createElement("input");
  search.type = "search";
  search.id = "search-input";
  document.body.append(search);
  search.focus();

  expect(shortcutReachesApp(document.activeElement, "j")).toBe(false);
});

test("Tab is the chrome's, so the focus moves instead of two spaces being typed", () => {
  // `Mousetrap.bind(["tab"])` inserts two spaces and returns false, which
  // cancels the keystroke — so Tab moved the focus nowhere at all outside a
  // marked field, and the tab stops tickets 33 and 34 built into the header
  // were unreachable by Tab. Taking the chrome's keystrokes off the app hands
  // Tab back to the platform.
  expect(reachesFrom("export", "export-format-text", "tab")).toBe(false);
});
