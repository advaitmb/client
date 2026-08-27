/**
 * <gw-help-modal platform="mac"> — the keyboard shortcut reference.
 *
 * Ported from Doc/HelpScreen.elm. Elm decides when it is on screen; this owns
 * the markup. Class names match src/static/style.css so the existing modal
 * styling still applies.
 *
 * Contract
 *   attribute  platform  "mac" | "other"
 *   event      gw-close  the overlay or close button was clicked
 */

import { h } from "./dom";
import { mountModal } from "./modal";

type Row = [keys: string[], description: string];

/**
 * A shortcut key rendered as a <span class="shortcut-key">. An entry padded
 * with spaces (" or ", " ... ") is connective text between keys, not a key --
 * that is how Elm distinguished them too, via `text` rather than `key`.
 */
function keys(...ks: string[]) {
  return ks.map((k) =>
    k !== k.trim()
      ? document.createTextNode(k)
      : h("span.shortcut-key", {}, k),
  );
}

function row([ks, description]: Row) {
  return h(
    "tr.shortcut-row",
    {},
    h("td", { style: "text-align: right" }, ...keys(...ks)),
    h("td", {}, `: ${description}`),
  );
}

function table(title: string, rows: Row[], note?: string) {
  return h(
    "div.shortcut-table-wrapper",
    {},
    h("h4.shortcut-table-title", {}, title),
    h(
      "table.shortcut-table",
      {},
      ...(note ? [h("tr", {}, h("th", { colspan: 2 }, note))] : []),
      ...rows.map(row),
    ),
  );
}

/**
 * Upstream rendered the Alt key as the literal string "AltKey" — the
 * translation entry was a placeholder that never got filled in. Alt is ⌥ on
 * macOS and Alt elsewhere.
 */
function shortcutSections(isMac: boolean) {
  const mod = isMac ? "⌘" : "Ctrl";
  const alt = isMac ? "⌥" : "Alt";
  const OR = " or ";

  const viewMode: Array<[string, Row[], string?]> = [
    ["Card Edit, Create, Delete", [
      [["Enter"], "Edit card"],
      [["Shift", "Enter"], "Edit card in fullscreen mode"],
      [[mod, "↓", OR, mod, "J"], "Add card below"],
      [[mod, "↑", OR, mod, "K"], "Add card above"],
      [[mod, "→", OR, mod, "L"], "Add card to the right (as child)"],
      [[mod, "Backspace"], "Delete card (and its children)"],
    ]],
    ["Navigation, Moving Cards", [
      [["↑", "↓", "←", "→", OR, "H", "J", "K", "L"], "Go up/down/left/right"],
      [["PageUp"], "Go to beginning of group"],
      [["PageDown"], "Go to end of group"],
      [["Home"], "Go to beginning of column"],
      [["End"], "Go to end of column"],
      [[alt, "(any of above)", OR, "Drag card by left edge"], "Move current card (and children)"],
    ]],
    ["Copy/Paste", [
      [[mod, "C"], "Copy current subtree"],
      [[mod, "V"], "Paste subtree below current card"],
      [[mod, "Shift", "V"], "Paste subtree as child of current card"],
      [["Drag selected text into tree"], "Insert selected text as new card"],
    ], "(Works across documents)"],
    ["Searching, Merging Cards", [
      [["/"], "Search"],
      [["Esc"], "Clear search, focus current card"],
      [[mod, "Shift", "↑", OR, mod, "Shift", "J"], "Merge card up"],
      [[mod, "Shift", "↓", OR, mod, "Shift", "K"], "Merge card down"],
    ]],
    ["Help, Info, Documents", [
      [["W"], "Word counts"],
      [[mod, "O"], "Switch to different document"],
      [["?"], "This help screen"],
    ]],
  ];

  const editMode: Array<[string, Row[]]> = [
    ["Card Save, Create", [
      [[mod, "S"], "Save changes"],
      [[mod, "Enter"], "Save changes and exit card"],
      [[mod, "J"], "Add card below (split at cursor)"],
      [[mod, "K"], "Add card above (split at cursor)"],
      [[mod, "L"], "Add card to the right (split at cursor)"],
      [["Esc"], "Exit edit mode"],
    ]],
    ["Formatting", [
      [[mod, "B"], "Bold selection"],
      [[mod, "I"], "Italicize selection"],
      [[mod, alt, "K"], "Insert Link"],
      [[alt, "1", " ... ", "6"], "Set title level (# to #####)"],
    ]],
  ];

  return [
    h("h2", { id: "shortcut-main-title" }, "Keyboard Shortcuts"),
    h(
      "div",
      { id: "shortcut-modes-wrapper" },
      h(
        "div",
        {},
        h("h3", { id: "view-mode-shortcuts-title" }, "View Mode Shortcuts"),
        ...viewMode.map(([t, rows, note]) => table(t, rows, note)),
      ),
      h("div", { id: "mode-divider" }),
      h(
        "div",
        {},
        h("h3", { id: "edit-mode-shortcuts-title" }, "Edit Mode Shortcuts"),
        ...editMode.map(([t, rows]) => table(t, rows)),
      ),
    ),
  ];
}

class HelpModal extends HTMLElement {
  connectedCallback() {
    // The overlay, the header and the close button are every modal's, so they
    // come from `mountModal` -- which is also the only place the close icon's
    // path data lives now. This element owns the shortcut tables and nothing
    // else (CODE_REVIEW.md S13).
    mountModal(
      this,
      "Help",
      shortcutSections(this.getAttribute("platform") === "mac"),
      { modalClass: "help-modal" },
    );
  }

  disconnectedCallback() {
    this.replaceChildren();
  }
}

customElements.define("gw-help-modal", HelpModal);
