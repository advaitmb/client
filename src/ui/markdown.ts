/**
 * <gw-markdown src="..." card-id="..."> — rendered card content.
 *
 * Replaces the two `Markdown.toHtmlWith` call sites: Page/Doc.viewContent (the
 * cards) and Page/Doc/Export.elm (the DOCX preview). They shared a renderer, so
 * they move together — leaving one behind would let the same text render two
 * different ways.
 *
 * WHAT CHANGES
 *
 * The old renderer was elm-explorations/markdown, a wrapper around a very old
 * marked, configured with breaks: true. It merged adjacent lists: bullets, an
 * ordered list and a task list in one card collapsed into a single <ul>, and
 * "1." lost its numbering. Current marked gets this right, so lists now render
 * as written. verify/tree.mjs records the old behaviour and will flag the
 * change rather than let it pass unnoticed.
 *
 * Export was never affected: gingko-export emits the markdown verbatim and
 * pandoc handles it.
 *
 * Contract
 *   attribute  src       the raw markdown
 *   attribute  card-id   the card's id, for checkbox round-tripping
 */

import { marked } from "marked";

/** `breaks: true` matches the old options: a single newline is a line break. */
marked.setOptions({ gfm: true, breaks: true });

/**
 * Preprocessing the Elm version did before parsing. Reproduced rather than
 * dropped: {++ ++} and {-- --} are CriticMarkup insertions and deletions, and
 * the checkbox rewrite is what makes tasks clickable.
 */
function preprocess(src: string): string {
  return src
    .replace(/\{\+\+/g, "<ins class='diff'>")
    .replace(/\+\+\}/g, "</ins>")
    .replace(/\{--/g, "<del class='diff'>")
    .replace(/--\}/g, "</del>");
}

/**
 * marked renders GFM tasks as a disabled checkbox. The app needs them
 * clickable, numbered in document order, and wired to the same global the Elm
 * version called — window.checkboxClicked, defined in src/shared/doc.js.
 */
function wireCheckboxes(root: HTMLElement, cardId: string): void {
  const boxes = root.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
  boxes.forEach((box, i) => {
    box.disabled = false;
    box.addEventListener("click", (e) => {
      e.stopPropagation();
      const fn = (window as unknown as {
        checkboxClicked?: (id: string, n: number) => void;
      }).checkboxClicked;
      fn?.(cardId, i + 1);
    });
  });
}

class Markdown extends HTMLElement {
  static observedAttributes = ["src", "card-id"];

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render();
  }

  private render() {
    const src = this.getAttribute("src") ?? "";
    const cardId = this.getAttribute("card-id") ?? "";

    const holder = document.createElement("div");
    holder.setAttribute("data-private", "lipsum");
    // marked.parse is synchronous with these options; the async overload is
    // only used when an async extension is registered, and none is.
    holder.innerHTML = marked.parse(preprocess(src)) as string;
    wireCheckboxes(holder, cardId);

    this.replaceChildren(holder);
  }
}

customElements.define("gw-markdown", Markdown);
