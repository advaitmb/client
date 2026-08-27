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

import DOMPurify, { type Config } from "dompurify";
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
 * Card content is untrusted: it reaches a viewer from collaborators (`rt`
 * messages, shared docs), JSON import and external drag-drop, and marked >= 5
 * has no sanitizer — it passes raw inline HTML straight through
 * (CODE_REVIEW.md C1, stored XSS). ADR-0003: one allowlist, defined here, used
 * by every path that assigns markdown-derived HTML.
 *
 * Spelled out rather than left to DOMPurify's defaults, which keep <style> and
 * the style attribute (CSS injection) plus the whole SVG/MathML profile. What
 * has to survive is the app's own output: the <ins>/<del> preprocess()
 * injects, the task-list checkbox wireCheckboxes() enables, and ordinary
 * markdown — headings, lists, links, images, code, tables. Anything executable
 * — script, event handlers, javascript: URLs, style, iframe — is not on the
 * list and so is dropped.
 */
const ALLOWLIST: Config = {
  ALLOWED_TAGS: [
    "a", "abbr", "b", "blockquote", "br", "caption", "code", "col",
    "colgroup", "dd", "del", "details", "div", "dl", "dt", "em", "figcaption",
    "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "input",
    "ins", "kbd", "li", "mark", "ol", "p", "pre", "q", "s", "samp", "small",
    "span", "strong", "sub", "summary", "sup", "table", "tbody", "td",
    "tfoot", "th", "thead", "tr", "u", "ul", "var", "wbr",
  ],
  ALLOWED_ATTR: [
    // Links and images. DOMPurify's URI check rejects javascript: (and every
    // other scheme outside http/https/mailto/tel/ftp/sms/cid/xmpp) here.
    "href", "src", "alt", "title", "target", "rel",
    // Task-list checkboxes.
    "type", "checked", "disabled",
    // Presentation marked emits, or that raw HTML in a card may carry. No
    // "style" (CSS injection) and no "id"/"name" (DOM clobbering).
    "class", "align", "colspan", "rowspan", "span", "start", "width",
    "height", "lang", "dir",
  ],
};

/**
 * The module's contract: card markdown in, HTML safe to assign to innerHTML
 * out. Both Elm call sites — Page/Doc.viewContent and the Export preview —
 * render through <gw-markdown>, so this is the one place they share and the
 * one place the sanitize step can be skipped by mistake. Exported so a render
 * path that ever needs the HTML without this element gets the allowlist by
 * construction instead of remembering a sanitize call (ADR-0003).
 */
export function renderMarkdown(src: string): string {
  // marked.parse is synchronous with these options; the async overload is
  // only used when an async extension is registered, and none is.
  const html = marked.parse(preprocess(src)) as string;
  return DOMPurify.sanitize(html, ALLOWLIST);
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
    holder.innerHTML = renderMarkdown(src);
    wireCheckboxes(holder, cardId);

    this.replaceChildren(holder);
  }
}

customElements.define("gw-markdown", Markdown);
