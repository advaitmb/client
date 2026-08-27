/**
 * The chrome every modal shares — overlay, header, close button.
 *
 * This began as a mirror of `SharedUI.modalWrapper`, so that the two could
 * coexist while surfaces moved across one at a time. Every modal has moved and
 * ticket 21 removed the Elm one, so this is now the only implementation -- but
 * the class names are still `src/static/style.css`'s and cannot be renamed
 * here alone.
 */

import { h, icon, emit } from "./dom";

const CLOSE_ICON =
  "M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zM15 9l-6 6M9 9l6 6";

export interface ModalOptions {
  /** Extra class on the .modal element, matching the Elm wrapper's argument. */
  modalClass?: string;
}

/**
 * Build a modal around `body` and mount it into `host`. Clicking the overlay
 * or the close button emits "gw-close" from `host`, which Elm listens for.
 */
export function mountModal(
  host: HTMLElement,
  title: string,
  body: Node[],
  { modalClass }: ModalOptions = {},
): void {
  const close = () => emit(host, "gw-close");
  host.replaceChildren(
    h("div.modal-overlay", { onclick: close }),
    h(
      "div.max-width-grid",
      {},
      h(
        "div.modal",
        { class: modalClass },
        h(
          "div.modal-header",
          {},
          h("h2", {}, title),
          h("div.close-button", { onclick: close, title: "Close" }, icon(CLOSE_ICON)),
        ),
        h("div.modal-guts", {}, ...body),
      ),
    ),
  );
}

/** "1 word" / "2 words" — the plural rule the Elm strings encoded inline. */
export function plural(n: number, singular: string, pluralForm: string): string {
  return `${n} ${n === 1 ? singular : pluralForm}`;
}

/**
 * Read a JSON attribute. Attributes are strings, so a surface that needs a
 * record gets one JSON attribute rather than a dozen scalar ones. That is a
 * single encoder per surface, not the per-message pair a port would need.
 * Returns null when absent or malformed; callers render nothing rather than
 * throwing inside connectedCallback.
 */
export function jsonAttr<T>(el: HTMLElement, name: string): T | null {
  const raw = el.getAttribute(name);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    console.error(`<${el.tagName.toLowerCase()}> could not parse ${name}`, raw);
    return null;
  }
}
