/**
 * <gw-sidebar> — the left rail: brand, new / documents / switcher buttons, and
 * the document list with its sort controls and filter.
 *
 * Replaces UI/Sidebar.elm and Doc.List.viewSidebarList. Elm still owns the
 * open/closed state, the sort criterion, the filter term and the sorted list
 * itself; this renders them and reports clicks.
 *
 * UI/Sidebar.elm was the only module using elm-css, so the dependency goes
 * with it. The styles it generated are now plain rules in theme.css.
 *
 * The filter input is uncontrolled, as in gw-switcher-modal: Elm learns the
 * term from gw-filter and sends back a filtered list, and never writes the
 * value down while it is being typed into.
 *
 * Contract — attributes in
 *   open              "yes" when the document list is showing
 *   static            present in the loading state: render, but wire nothing
 *   current           id of the open document
 *   sort              "alpha" | "modified" | "created"
 *   docs              JSON [{ id, name }], already filtered and sorted
 *   switcher-enabled  "no" disables the quick-switcher button
 *
 * There was a `context-target` attribute here — the id of the document whose
 * context menu is open, which marked its row — documented, styled, observed,
 * and never set by Elm: `SidebarContextClicked` puts the id in
 * `ModalState.SidebarContextMenu` and Elm renders the menu itself, over an
 * overlay, without telling the rail anything. So the mark never appeared.
 * Removed by ticket 22 rather than wired up, because giving it a producer is a
 * UI change (one `attribute "context-target"` in `Page.App.viewSidebarElement`
 * plus the CSS back) and this is a purge.
 *
 * Contract — events out
 *   gw-sidebar-toggle
 *   gw-new | gw-switcher | gw-logout
 *   gw-filter   detail: the search term
 *   gw-sort     detail: "alpha" | "modified" | "created"
 *   gw-context  detail: { id, x, y }
 */

import { h, icon, emit } from "./dom";
import { jsonAttr } from "./modal";

const I = {
  fileAdd: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M12 11v6M9 14h6",
  folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  folderOpen: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2M3 7v11a2 2 0 0 0 2 2h13.5a2 2 0 0 0 1.9-1.4l1.8-6A1.5 1.5 0 0 0 20.8 11H6.9a2 2 0 0 0-1.9 1.4L3 18",
  search: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4",
  left: "M15 18l-6-6 6-6",
  menu: "M4 7h16M4 12h16M4 17h16",
  edit: "M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z",
  file: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5",
  logout: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9",
};

interface Doc {
  id: string;
  name: string | null;
}

const SORTS: Array<[value: string, id: string, label: string, glyph: string | null]> = [
  ["alpha", "sort-alphabetical", "Abc", null],
  ["modified", "sort-modified", "Sort by last modified", I.edit],
  ["created", "sort-created", "Sort by date created", I.file],
];

class Sidebar extends HTMLElement {
  static observedAttributes = [
    "open", "current", "sort", "docs", "switcher-enabled", "static",
  ];

  private list: HTMLElement | null = null;
  // Built once and reused: the filter is uncontrolled, so recreating it on a
  // re-render (changing the sort, say) would silently discard what was typed.
  private filterInput: HTMLInputElement | null = null;

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback(name: string) {
    if (!this.isConnected) return;
    // Only the rows change on most updates; re-rendering the whole sidebar
    // would blow away the filter input's caret.
    if (name === "docs" || name === "current") {
      if (this.list) return this.renderRows();
    }
    this.render();
  }

  disconnectedCallback() {
    this.list = null;
    this.filterInput = null;
    this.replaceChildren();
  }

  private get isStatic() {
    return this.hasAttribute("static");
  }

  private on(handler: () => void) {
    return this.isStatic ? undefined : handler;
  }

  private render() {
    const open = this.getAttribute("open") === "yes";
    const switcherOff =
      this.isStatic || this.getAttribute("switcher-enabled") === "no";

    const button = (
      id: string,
      glyph: string,
      label: string,
      onclick?: () => void,
      extra?: string,
    ) =>
      h(
        "div",
        {
          id,
          class: `sidebar-button${extra ? " " + extra : ""}`,
          title: label,
          onclick: onclick && ((e: Event) => { e.stopPropagation(); onclick(); }),
        },
        icon(glyph),
      );

    this.list = open ? h("div", { id: "sidebar-document-list" }) : null;

    const parts: Array<Node | null> = [
      h(
        "div",
        { id: "brand" },
        // Absolute: the build copies src/static/. to the web root, and the rail
        // is rendered on every route (CODE_REVIEW.md S13).
        h("img", { src: "/gingko-leaf-logo.svg", width: 28, alt: "" }),
        open ? h("h2", { id: "brand-name" }, "Gingko Writer") : null,
        open ? h("div", { id: "sidebar-collapse-icon" }, icon(I.left)) : null,
        h("div", { id: "hamburger-icon" }, icon(I.menu)),
      ),
      button("new-icon", I.fileAdd, "New document", this.on(() => emit(this, "gw-new"))),
      button(
        "documents-icon",
        open ? I.folderOpen : I.folder,
        "Show document list",
        undefined,
        open ? "open" : undefined,
      ),
      open ? this.listWrap() : null,
      button(
        "document-switcher-icon",
        I.search,
        "Quick document switcher",
        switcherOff ? undefined : this.on(() => emit(this, "gw-switcher")),
        switcherOff ? "disabled" : undefined,
      ),
      // The only way out of the session: the account menu that used to host
      // logout is gone (CODE_REVIEW.md C3). style.css pins it to the bottom
      // of the rail, where that menu was.
      button("logout-icon", I.logout, "Log out", this.on(() => emit(this, "gw-logout"))),
    ];

    this.id = "sidebar";
    this.className = `${open ? "open" : ""}${this.isStatic ? " static" : ""}`.trim();
    this.onclick = this.isStatic ? null : () => emit(this, "gw-sidebar-toggle");

    this.replaceChildren(...parts.filter((n): n is Node => n !== null));
    if (this.list) this.renderRows();
  }

  private listWrap() {
    const sort = this.getAttribute("sort") ?? "modified";
    const stop = (e: Event) => e.stopPropagation();

    this.filterInput ??= h("input", {
      id: "document-list-filter",
      type: "search",
      placeholder: "Find file by name",
      onclick: stop,
      oninput: (e: Event) => {
        e.stopPropagation();
        if (!this.isStatic) emit(this, "gw-filter", (e.target as HTMLInputElement).value);
      },
    }) as HTMLInputElement;

    return h(
      "div",
      { id: "sidebar-document-list-wrap" },
      h(
        "div",
        { id: "document-list-buttons", onclick: stop },
        ...SORTS.map(([value, id, label, glyph]) =>
          h(
            "div",
            {
              id,
              class: `sort-button${value === sort ? " selected" : ""}`,
              title: label,
              onclick: (e: Event) => {
                e.stopPropagation();
                if (!this.isStatic) emit(this, "gw-sort", value);
              },
            },
            glyph ? icon(glyph, 14) : label,
          ),
        ),
      ),
      this.filterInput,
      this.list,
    );
  }

  private renderRows() {
    if (!this.list) return;
    const docs = jsonAttr<Doc[]>(this, "docs") ?? [];
    const current = this.getAttribute("current");

    if (docs.length === 0) {
      this.list.replaceChildren(h("div", { id: "no-documents" }, "No Documents Found"));
      return;
    }

    this.list.replaceChildren(
      ...docs.map((d) => {
        const classes = ["sidebar-document-item"];
        if (d.id === current) classes.push("active");
        return h(
          "div",
          { class: classes.join(" ") },
          h(
            "a",
            {
              href: `/${d.id}`,
              "data-private": "lipsum",
              onclick: (e: Event) => e.stopPropagation(),
              oncontextmenu: (e: Event) => {
                e.preventDefault();
                e.stopPropagation();
                const m = e as MouseEvent;
                if (!this.isStatic)
                  emit(this, "gw-context", { id: d.id, x: m.clientX, y: m.clientY });
              },
            },
            d.name || "Untitled",
          ),
        );
      }),
    );
  }
}

customElements.define("gw-sidebar", Sidebar);
