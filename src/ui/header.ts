/**
 * <gw-header> — the whole document header: title, save state, the three menu
 * buttons and the menus they open.
 *
 * Replaces UI/Header.elm and Doc/History.view. Elm keeps every decision: which
 * menu is open, whether the title is editable, what the export settings are,
 * and which version the history slider maps to. This renders that state and
 * reports intent back. The save state is <gw-save-indicator>'s, which the
 * fullscreen view renders too — this only forwards the attribute.
 *
 * The title input is UNCONTROLLED, for the reason gw-switcher-modal's is: Elm
 * re-renders the header on every save-status tick, and writing the value back
 * on each one would fight the caret while you are typing a title. `doc-title`
 * is the last *committed* name, never the text being typed, so the input node
 * itself is built once and kept: a re-render (from any attribute) replaces
 * everything after the title, and touches the field only while it is idle.
 *
 * Contract — attributes in
 *   doc-title        current document name
 *   owner            "yes" | "no" | "unknown" — whether the title may be
 *                    edited, or that the document list has yet to say
 *   menu             "none" | "history" | "settings" | "export"
 *   save             JSON { dirty, lastLocalSave, lastRemoteSave, now }
 *                    (epoch ms; lastLocalSave/lastRemoteSave may be null)
 *   export-settings  JSON { selection, format }
 *   history          JSON { index, max }
 *
 * Contract — events out
 *   gw-title-input     detail: string
 *   gw-title-commit    Enter or blur
 *   gw-title-cancel    Escape
 *   gw-title-focus
 *   gw-menu            detail: which menu to show ("none" closes)
 *   gw-export-selection / gw-export-format   detail: the chosen value
 *   gw-wordcount
 *   gw-history-checkout  detail: slider index (Elm maps it to a version)
 *   gw-history-restore | gw-history-cancel
 */

import { h, icon, emit } from "./dom";
import { jsonAttr } from "./modal";
// The save indicator is its own element, shared with the fullscreen view; the
// import is what registers it (S1).
import "./save-indicator";

const I = {
  history: "M3 3v6h6M3.5 13a9 9 0 1 0 2.1-6.4L3 9",
  settings: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2v.1a2 2 0 1 1-4 0v-.2a1.7 1.7 0 0 0-3-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H3a2 2 0 1 1 0-4h.2a1.7 1.7 0 0 0 1.1-3l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V3a2 2 0 1 1 4 0v.2a1.7 1.7 0 0 0 3 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9H21a2 2 0 1 1 0 4h-.2a1.7 1.7 0 0 0-1.4 1z",
  export: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M9 15h6M9 12h6",
  close: "M18 6L6 18M6 6l12 12",
};

/**
 * The container id and the child id prefix differ in the existing stylesheet
 * (#export-selection holds #export-select-all, …), so both are passed.
 */
function toggleGroup(
  containerId: string,
  childPrefix: string,
  current: string,
  options: Array<[value: string, label: string]>,
  onPick: (v: string) => void,
) {
  return h(
    "div",
    { id: containerId, class: "toggle-button" },
    ...options.map(([value, label]) =>
      h(
        "div",
        {
          id: `${childPrefix}${value}`,
          class: value === current ? "selected" : undefined,
          onclick: () => onPick(value),
        },
        label,
      ),
    ),
  );
}

/** The nodes render() keeps rather than rebuilds; see Header.renderTitle. */
interface TitleParts {
  span: HTMLElement;
  input: HTMLInputElement;
  shadow: HTMLElement;
  /**
   * <gw-save-indicator>, inside the title span. Kept like the rest: it renders
   * itself from its own `save` attribute, so the header only forwards it.
   */
  indicator: HTMLElement;
}

class Header extends HTMLElement {
  static observedAttributes = [
    "doc-title", "owner", "menu", "save", "export-settings", "history",
  ];

  private titleParts: TitleParts | null = null;

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render();
  }

  disconnectedCallback() {
    this.titleParts = null;
    this.replaceChildren();
  }

  private menuButton(id: string, glyph: string, menu: string, label: string) {
    const open = this.getAttribute("menu") === menu;
    return h(
      "div",
      {
        id,
        class: `header-button${open ? " open" : ""}`,
        title: label,
        onclick: () => emit(this, "gw-menu", open ? "none" : menu),
      },
      icon(glyph),
    );
  }

  private render() {
    const menu = this.getAttribute("menu") ?? "none";

    const title = this.renderTitle();

    const parts: Array<Node | null> = [
      this.menuButton("history-icon", I.history, "history", "Version history"),
      menu === "history" ? this.historyMenu() : null,
      this.menuButton("doc-settings-icon", I.settings, "settings", "Document settings"),
      menu === "settings" ? this.settingsMenu() : null,
      this.menuButton("export-icon", I.export, "export", "Export or print"),
      menu === "export" ? this.exportMenu() : null,
    ];
    // Everything except the title is thrown away and rebuilt. The title span
    // stays put: detaching it -- which replaceChildren() does even when the
    // same node goes straight back -- takes the focus, the caret and the
    // browser's own undo stack with it.
    for (const child of Array.from(this.children)) {
      if (child !== title.span) child.remove();
    }
    this.append(...parts.filter((n): n is Node => n !== null));
  }

  /**
   * Update the title in place, building it on the first render of a
   * connection. The one rule: while the field has focus it belongs to the
   * user, so nothing writes its value -- whichever attribute the re-render
   * came from (E12: the `save` tick alone fires every 9 seconds). Elm learns
   * the text through `gw-title-input` and hands back a new `doc-title` only
   * once the rename is committed.
   */
  private renderTitle(): TitleParts {
    // Three values, not two (S3): Elm answers "unknown" while the document
    // list -- the only thing that knows who owns a document -- is still on its
    // way. The field is inert until the answer arrives, so a non-owner never
    // gets a rename window, but it is marked forbidden only for a *known*
    // non-owner: the not-allowed cursor is the whole of what the user sees
    // here, and showing it and taking it back is the flap.
    const owner = this.getAttribute("owner");
    const docTitle = this.getAttribute("doc-title") ?? "Untitled";

    const title =
      this.titleParts?.span.parentNode === this
        ? this.titleParts
        : (this.titleParts = this.buildTitle());

    if (title.input !== document.activeElement) title.input.value = docTitle;
    title.input.disabled = owner !== "yes";
    title.input.style.cursor = owner === "no" ? "not-allowed" : "";
    // The shadow sizes the input, so it follows what the input shows.
    title.shadow.textContent = title.input.value || " ";

    // Forwarded, not interpreted: what the state means is
    // <gw-save-indicator>'s, which the fullscreen view renders too.
    const save = this.getAttribute("save");
    if (save === null) title.indicator.removeAttribute("save");
    else title.indicator.setAttribute("save", save);

    return title;
  }

  private buildTitle(): TitleParts {
    const input = h("input", {
      id: "title-rename",
      type: "text",
      size: 1,
      "data-private": "lipsum",
      oninput: (e: Event) =>
        emit(this, "gw-title-input", (e.target as HTMLInputElement).value),
      onfocus: () => emit(this, "gw-title-focus"),
      onblur: () => emit(this, "gw-title-commit"),
      onkeyup: (e: Event) => {
        const k = (e as KeyboardEvent).key;
        if (k === "Enter") emit(this, "gw-title-commit");
        if (k === "Escape") emit(this, "gw-title-cancel");
      },
    }) as HTMLInputElement;
    // .title-grow-wrap + .shadow is how the input sizes itself to its
    // content; the shadow must carry identical text and typography.
    const shadow = h("div.shadow", {}, " ");
    // The id is the stylesheet's hook (`#save-indicator`), given by the caller
    // the way Elm gives <gw-header> its `#document-header`.
    const indicator = h("gw-save-indicator", { id: "save-indicator" });
    const span = h(
      "span",
      { id: "title" },
      h("div.title-grow-wrap", {}, shadow, input),
      indicator,
    );

    // First child, ahead of the menu buttons render() appends after it.
    this.prepend(span);
    return { span, input, shadow, indicator };
  }

  private settingsMenu() {
    return h(
      "div",
      { id: "doc-settings-menu", class: "header-menu" },
      h(
        "div",
        { id: "wordcount-menu-item", onclick: () => emit(this, "gw-wordcount") },
        "Word count...",
      ),
    );
  }

  private exportMenu() {
    const s = jsonAttr<{ selection: string; format: string }>(this, "export-settings");
    return h(
      "div",
      { id: "export-menu" },
      toggleGroup("export-selection", "export-select-", s?.selection ?? "all", [
        ["all", "Everything"],
        ["subtree", "Current Subtree"],
        ["leaves", "Leaves-only"],
        ["column", "Current Column"],
      ], (v) => emit(this, "gw-export-selection", v)),
      toggleGroup("export-format", "export-format-", s?.format ?? "word", [
        ["word", "Word"],
        ["text", "Plain Text"],
        ["opml", "OPML"],
        ["json", "JSON"],
      ], (v) => emit(this, "gw-export-format", v)),
      // Download and Print are NOT here: Page/Doc/Export.elm renders them in
      // the preview pane, and duplicating them would give two of each.
    );
  }

  private historyMenu() {
    const hist = jsonAttr<{ index: number; max: number }>(this, "history");
    return h(
      "div",
      { id: "history-menu" },
      h("input", {
        id: "history-slider",
        type: "range",
        min: 0,
        max: hist?.max ?? 0,
        step: 1,
        value: hist?.index ?? 0,
        // Elm owns the index -> version mapping; it only needs the position.
        oninput: (e: Event) =>
          emit(this, "gw-history-checkout", (e.target as HTMLInputElement).value),
      }),
      h(
        "button",
        { id: "history-restore", onclick: () => emit(this, "gw-history-restore") },
        "Restore this Version",
      ),
      h(
        "div",
        {
          id: "history-close-button",
          title: "Cancel",
          onclick: () => emit(this, "gw-history-cancel"),
        },
        icon(I.close),
      ),
    );
  }
}

customElements.define("gw-header", Header);
