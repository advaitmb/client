/**
 * <gw-wordcount-modal stats="{…}"> — word and character counts.
 *
 * Ported from Doc/UI.viewWordCount. The counting itself stays in Elm:
 * Doc.UI.getStats walks the tree, and that is data logic, not presentation.
 * This renders the table Elm used to build.
 *
 * Contract
 *   attribute  stats     JSON, the Stats record below
 *   event      gw-close  the overlay or close button was clicked
 */

import { h } from "./dom";
import { mountModal, plural, jsonAttr } from "./modal";

interface Stats {
  cardWords: number;
  subtreeWords: number;
  groupWords: number;
  columnWords: number;
  sessionWords: number;
  documentWords: number;
  cardChars: number;
  subtreeChars: number;
  groupChars: number;
  columnChars: number;
  documentChars: number;
  cards: number;
}

function column(rows: string[]) {
  return h("div.word-count-column", {}, ...rows.map((r) => h("span", {}, r)));
}

class WordcountModal extends HTMLElement {
  connectedCallback() {
    const s = jsonAttr<Stats>(this, "stats");
    if (!s) return;

    const w = (label: string, n: number) => `${label} : ${plural(n, "word", "words")}`;
    const c = (label: string, n: number) => `${label} : ${plural(n, "character", "characters")}`;

    mountModal(this, "Word & Character Counts", [
      h(
        "div",
        { id: "word-count-table" },
        column([
          w("Card", s.cardWords),
          w("Subtree", s.subtreeWords),
          w("Group", s.groupWords),
          w("Column", s.columnWords),
          w("Session", s.sessionWords),
          w("Total", s.documentWords),
        ]),
        column([
          c("Card", s.cardChars),
          c("Subtree", s.subtreeChars),
          c("Group", s.groupChars),
          c("Column", s.columnChars),
          c("Total", s.documentChars),
        ]),
      ),
      h("span", { style: "text-align: center" }, `Total Cards in Tree : ${s.cards}`),
    ]);
  }

  disconnectedCallback() {
    this.replaceChildren();
  }
}

customElements.define("gw-wordcount-modal", WordcountModal);
