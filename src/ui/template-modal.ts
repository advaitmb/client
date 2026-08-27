/**
 * <gw-template-modal> — the New Document picker.
 *
 * Ported from Doc/UI.viewTemplateSelector. Pure presentation: every tile is
 * either a link to a route Elm already owns, or the one JSON-import action.
 *
 * The import tile wraps a real <input type="file">. Routing the click through
 * a CustomEvent into an Elm Cmd loses the user-gesture context that the file
 * picker requires, so Elm's Select.file silently did nothing. Picking the file
 * is an interface concern anyway; Elm receives its name and contents.
 *
 * Contract
 *   event  gw-close        dismissed
 *   event  gw-import-json  detail: { name, text } of the chosen file
 */

import { h, icon, emit } from "./dom";
import { mountModal } from "./modal";

/** 48px line icons, drawn rather than pulled from an icon font. */
const ICONS = {
  fileCode: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M10 12l-2 2 2 2M14 12l2 2-2 2",
  calendar: "M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zM4 9h16M8 3v4M16 3v4",
  flask: "M10 3h4M10 3v6l-5 9a2 2 0 0 0 1.8 3h10.4a2 2 0 0 0 1.8-3l-5-9V3M7.5 15h9",
  bulb: "M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.4.3.5.7.5 1.1h6c0-.4.1-.8.5-1.1A6 6 0 0 0 12 3z",
  bolt: "M13 2L4.5 13.5H11l-1 8.5 8.5-11.5H12z",
};

interface Tile {
  id: string;
  href?: string;
  file?: (f: File) => void;
  iconPath: string | null;
  title: string;
  description?: string;
}

function tile(t: Tile) {
  const inner = [
    h(
      "div.template-thumbnail",
      { class: t.iconPath ? undefined : "new" },
      t.iconPath ? icon(t.iconPath, 48) : null,
    ),
    h("div.template-title", {}, t.title),
    t.description ? h("div.template-description", {}, t.description) : null,
  ];

  if (t.href) return h("a.template-item", { id: t.id, href: t.href }, ...inner);

  if (t.file) {
    const input = h("input", {
      type: "file",
      accept: "application/json,text/plain,.json",
      style: "position:absolute; width:1px; height:1px; opacity:0; pointer-events:none",
      onchange: (e: Event) => {
        const f = (e.target as HTMLInputElement).files?.[0];
        if (f) t.file!(f);
      },
    }) as HTMLInputElement;
    // A label keeps the picker inside the browser's own user-gesture path.
    return h(
      "label.template-item",
      { id: t.id, style: "position: relative" },
      ...inner,
      input,
    );
  }

  return h("div.template-item", { id: t.id }, ...inner);
}

function row(...tiles: Tile[]) {
  return h("div.template-row", {}, ...tiles.map(tile));
}

class TemplateModal extends HTMLElement {
  connectedCallback() {
    mountModal(this, "New Document", [
      h(
        "div",
        { id: "templates-block" },
        h("h2", {}, "New"),
        row({ id: "template-new", href: "/new", iconPath: null, title: "Blank Tree" }),

        h("h2", {}, "Import"),
        row({
          id: "template-import",
          file: async (f) =>
            emit(this, "gw-import-json", { name: f.name, text: await f.text() }),
          iconPath: ICONS.fileCode,
          title: "Import JSON tree",
          description: "From Gingko Desktop or Online export file",
        }),

        h("h2", {}, "Templates & Examples"),
        row(
          {
            id: "template-timeline",
            href: "/import/timeline",
            iconPath: ICONS.calendar,
            title: "Timeline 2026",
            description: "A tree-based calendar",
          },
          {
            id: "template-academic",
            href: "/import/academic-paper",
            iconPath: ICONS.flask,
            title: "Academic Paper",
            description: "Starting point for journal paper",
          },
          {
            id: "template-project",
            href: "/import/project-brainstorming",
            iconPath: ICONS.bulb,
            title: "Project Brainstorming",
            description: "Example on clarifying project goals",
          },
          {
            id: "template-heros-journey",
            href: "/import/heros-journey",
            iconPath: ICONS.bolt,
            title: "Hero's Journey",
            description: "A framework for fictional stories",
          },
        ),
      ),
    ]);
  }

  disconnectedCallback() {
    this.replaceChildren();
  }
}

customElements.define("gw-template-modal", TemplateModal);
