/**
 * A three-function DOM helper for the interface layer.
 *
 * Deliberately not a framework. These surfaces are rendered once when they
 * open and thrown away when they close, so there is nothing for a virtual DOM
 * to diff. Elm still owns when a surface appears; this owns what it looks
 * like. See src/ui/README.md for the boundary.
 */

type Child = Node | string | null | undefined | false;
type Attrs = Record<string, string | number | boolean | EventListener | null | undefined>;

/**
 * h("div.modal", {…}, …children) — the spec may carry #id and .classes,
 * in either order: "input#switcher-input.mousetrap".
 */
const SPEC = /^([a-z][a-z0-9-]*)?(#[A-Za-z0-9_-]+)?((?:\.[A-Za-z0-9_-]+)*)$/;

export function h(spec: string, attrs: Attrs = {}, ...children: Child[]): HTMLElement {
  const m = SPEC.exec(spec);
  // Loud on purpose: an unparsed spec used to reach createElement as a bogus
  // tag name and produce an element that silently matched no selector.
  if (!m) throw new Error(`h(): malformed spec ${JSON.stringify(spec)}`);
  const [, tag, id, classSpec] = m;

  const el = document.createElement(tag || "div");
  if (id) el.id = id.slice(1);
  if (classSpec) el.className = classSpec.slice(1).split(".").join(" ");

  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue;
    if (k.startsWith("on") && typeof v === "function") {
      el.addEventListener(k.slice(2).toLowerCase(), v as EventListener);
    } else if (k === "class") {
      el.className = el.className ? `${el.className} ${v}` : String(v);
    } else {
      el.setAttribute(k, v === true ? "" : String(v));
    }
  }

  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    el.append(typeof c === "string" ? document.createTextNode(c) : c);
  }
  return el;
}

/** Inline SVG, so icons scale and recolour with the text around them. */
export function icon(pathData: string, size = 20): SVGElement {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("width", String(size));
  svg.setAttribute("height", String(size));
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "1.6");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  const p = document.createElementNS("http://www.w3.org/2000/svg", "path");
  p.setAttribute("d", pathData);
  svg.append(p);
  return svg;
}

/**
 * Tell Elm something happened. Elm listens with
 * `Html.Events.on "gw-close" (Decode.succeed ModalClosed)`, so the event must
 * bubble and must be composed to escape a shadow root if one is ever used.
 */
export function emit(el: HTMLElement, name: string, detail?: unknown): void {
  el.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
}
