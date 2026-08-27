/**
 * <gw-switcher-modal docs="[…]" current="id" selected="id">
 *   the ⌘O quick document switcher.
 *
 * Ported from Doc/Switcher.view and Doc/List.viewSwitcher. Everything that
 * decides *which* documents show and which is highlighted stays in Elm —
 * Doc.Switcher.up/down/search own the selection, and the global keyboard
 * handler in Page/App still drives ↑ ↓ Enter Esc. This renders the result.
 *
 * The search input is deliberately UNCONTROLLED. Elm learns the term from the
 * gw-search event and sends back a filtered list; it never writes the value
 * back down. Re-rendering a controlled input on every keystroke is what
 * destroys the caret, and it is the same problem gw-textarea exists to solve.
 *
 * Contract
 *   attribute  docs      JSON [{ id, name }], already filtered and sorted
 *   attribute  current   id of the document being edited
 *   attribute  selected  id of the highlighted row
 *   event      gw-search detail: the search term
 *   event      gw-close  dismissed
 */

import { h } from "./dom";
import { jsonAttr } from "./modal";
import { emit } from "./dom";

interface Doc {
  id: string;
  name: string | null;
}

class SwitcherModal extends HTMLElement {
  static observedAttributes = ["docs", "selected", "current"];

  private list: HTMLElement | null = null;

  connectedCallback() {
    if (this.list) return; // already built; attributeChangedCallback refreshes
    const close = () => emit(this, "gw-close");

    const input = h("input#switcher-input.mousetrap", {
      type: "search",
      placeholder: "Type file name to select",
      // Keeps the document list out of screenshots and error reports, as the
      // Elm version did.
      "data-private": "lipsum",
      oninput: (e: Event) =>
        emit(this, "gw-search", (e.target as HTMLInputElement).value),
    });

    this.list = h("div.switcher-document-list");

    this.replaceChildren(
      h(
        "div.modal-container",
        {},
        h("div.modal-overlay", { onclick: close }),
        h(
          "div",
          { id: "switcher-modal" },
          input,
          this.list,
          h(
            "div.switcher-instructions",
            {},
            instruction("↓ ↑", " to select"),
            instruction("Enter", " to open"),
            instruction("Esc", " to dismiss"),
          ),
        ),
      ),
    );

    this.renderList();
    input.focus();
  }

  attributeChangedCallback() {
    this.renderList();
  }

  disconnectedCallback() {
    this.list = null;
    this.replaceChildren();
  }

  private renderList() {
    if (!this.list) return;
    const docs = jsonAttr<Doc[]>(this, "docs") ?? [];
    const current = this.getAttribute("current");
    const selected = this.getAttribute("selected");

    this.list.replaceChildren(
      ...docs.map((d) => {
        const classes = ["switcher-document-item"];
        if (d.id === current) classes.push("current");
        if (d.id === selected) classes.push("selected");
        return h(
          "div",
          { class: classes.join(" ") },
          h("a", { href: `/${d.id}`, "data-private": "lipsum" }, d.name || "Untitled"),
        );
      }),
    );
  }
}

function instruction(key: string, rest: string) {
  return h("div.switcher-instruction", {}, h("span.shortcut-key", {}, key), rest);
}

customElements.define("gw-switcher-modal", SwitcherModal);
