/**
 * <gw-tree> — the card tree: columns, groups, and the three card states.
 *
 * Replaces Page/Doc.treeView, viewColumn, viewGroup, viewCardOther,
 * viewCardActive and viewCardEditing. Elm keeps everything that decides
 * anything: the tree itself, which card is active or being edited, the
 * ancestor and descendant sets, search filtering, and every keyboard shortcut.
 * This renders that and reports clicks.
 *
 * RECONCILIATION
 *
 * Unlike every other surface here, this one persists and updates constantly,
 * so it cannot use dom.ts's build-and-replace approach. Page/Doc used
 * lazy2/lazy6 to avoid re-rendering unchanged cards; the equivalent here is a
 * keyed map from card id to element:
 *
 *   - `tree` changing rebuilds the column/group scaffolding but REUSES card
 *     elements by id, and only rewrites a card's content when it differs.
 *   - `view-state` changing (which happens on every arrow keypress) touches
 *     classes only, and never reparses the tree.
 *
 * That split is why the two are separate attributes. Putting them together
 * would mean stringifying the whole document in Elm on every cursor move.
 *
 * Contract — attributes in
 *   tree        JSON [[ [card, …] , …groups ], …columns], already filtered
 *               card = { id, content, hasChildren, isLast }
 *   view-state  JSON { active, editing, ancestors[], descendants[] }
 *   external-drag  "yes" while text is being dragged in from outside the app
 *
 * Contract — events out
 *   gw-activate | gw-open            detail: card id
 *   gw-insert-above | gw-insert-below | gw-insert-child | gw-delete
 *                                    detail: card id
 *   gw-edit-fullscreen | gw-save-close
 *   gw-drop     detail: { dragged, id, where: "above"|"below"|"into" } — the
 *               card that was dragged, and which drop region of which card it
 *               was dropped on.
 *   gw-drag-start | gw-drag-end
 *               a card drag beginning and ending, whatever it ends in. The
 *               port layer listens for these to tell a card being dragged
 *               inside the app from text arriving from outside it: an internal
 *               drop is stopPropagation()ed here, so a document-level drop
 *               handler never sees one (CODE_REVIEW.md E8).
 *   gw-external-enter | gw-external-leave
 *               detail: { id, where } — where to drop text dragged in from
 *               outside. Elm records it and its own document-level drop
 *               handler inserts the text there.
 */

import { h, icon, emit } from "./dom";
import { jsonAttr } from "./modal";

interface Card {
  id: string;
  content: string;
  hasChildren: boolean;
  isLast: boolean;
}
type Group = Card[];
type Column = Group[];

interface ViewState {
  active: string;
  editing: string | null;
  ancestors: string[];
  descendants: string[];
}

const FULLSCREEN_ICON = "M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 0 2-2v-3";

/** The rounded corner joining a parent card to its children's group. */
function fillet(corner: string) {
  return h("div", { class: `fillet ${corner}` });
}

class Tree extends HTMLElement {
  static observedAttributes = ["tree", "view-state", "external-drag"];

  /** Card id -> its element, so an unchanged card is never rebuilt. */
  private cards = new Map<string, HTMLElement>();
  private contents = new Map<string, string>();
  /** The data each card was built from, so one card can be rebuilt alone. */
  private data = new Map<string, Card>();
  private editingId: string | null = null;
  private columnContainer: HTMLElement | null = null;
  private dragged: string | null = null;

  connectedCallback() {
    if (!this.columnContainer) this.scaffold();
    this.renderTree();
  }

  attributeChangedCallback(name: string) {
    if (!this.isConnected || !this.columnContainer) return;
    if (name === "view-state") this.applyViewState();
    else if (name === "external-drag") return; // read live in the drag handlers
    else this.renderTree();
  }

  disconnectedCallback() {
    this.cards.clear();
    this.contents.clear();
    this.columnContainer = null;
    this.replaceChildren();
  }

  private scaffold() {
    this.columnContainer = h("div", { id: "column-container" });
    this.replaceChildren(
      h("div.left-padding-column"),
      this.columnContainer,
      h("div.right-padding-column"),
    );
    this.id = "document";
  }

  /* ---------- structure ---------- */

  private renderTree() {
    const columns = jsonAttr<Column[]>(this, "tree") ?? [];
    const vs = jsonAttr<ViewState>(this, "view-state");
    if (!this.columnContainer) return;

    const seen = new Set<string>();
    this.columnContainer.replaceChildren(
      ...columns.map((col) => this.renderColumn(col, vs, seen)),
    );

    // Cards that left the tree must not keep their elements alive.
    for (const id of [...this.cards.keys()]) {
      if (!seen.has(id)) {
        this.cards.delete(id);
        this.contents.delete(id);
        this.data.delete(id);
      }
    }
    this.applyViewState();
  }

  private renderColumn(col: Column, vs: ViewState | null, seen: Set<string>) {
    const buffer = () => h("div.buffer");
    return h(
      "div.column",
      {},
      buffer(),
      ...col.map((group) => this.renderGroup(group, vs, seen)),
      buffer(),
    );
  }

  private renderGroup(group: Group, vs: ViewState | null, seen: Set<string>) {
    const el = h("div.group");
    const isActiveDescendant =
      !!vs && group.length > 0 && vs.descendants.includes(group[0]!.id);

    for (const card of group) {
      seen.add(card.id);
      el.append(this.cardElement(card, vs));
    }
    if (isActiveDescendant) {
      el.append(
        fillet("top-left"), fillet("bottom-left"),
        fillet("top-right"), fillet("bottom-right"),
      );
    }
    return el;
  }

  /* ---------- cards ---------- */

  /** Reuses the existing element for a card id; only content changes rewrite. */
  private cardElement(card: Card, vs: ViewState | null): HTMLElement {
    const editing = vs?.editing === card.id;
    const existing = this.cards.get(card.id);

    // The editing card has a completely different body, so it is rebuilt on
    // entering and leaving edit mode rather than patched.
    const wasEditing = existing?.classList.contains("editing") ?? false;
    if (existing && wasEditing === editing) {
      if (this.contents.get(card.id) !== card.content && !editing) {
        this.setCardContent(existing, card);
      }
      existing.dataset["isLast"] = String(card.isLast);
      existing.classList.toggle("has-children", card.hasChildren);
      this.data.set(card.id, card);
      return existing;
    }

    const el = editing ? this.buildEditingCard(card) : this.buildCard(card);
    this.cards.set(card.id, el);
    this.contents.set(card.id, card.content);
    this.data.set(card.id, card);
    return el;
  }

  private setCardContent(el: HTMLElement, card: Card) {
    const md = el.querySelector("gw-markdown");
    md?.setAttribute("src", card.content);
    this.contents.set(card.id, card.content);
  }

  private buildCard(card: Card): HTMLElement {
    const id = card.id;
    const btn = (cls: string, label: string, ev: string, text?: string) =>
      h(
        "span",
        {
          class: `card-btn ${cls}`,
          title: label,
          onclick: (e: Event) => { e.stopPropagation(); emit(this, ev, id); },
        },
        text ?? null,
      );

    const el = h(
      "div",
      {
        id: `card-${id}`,
        class: `card${card.hasChildren ? " has-children" : ""}`,
        dir: "auto",
        draggable: true,
        ondragstart: (e: Event) => this.onDragStart(e as DragEvent, id),
        ondragend: () => this.onDragEnd(),
      },
      h("div.drag-region", { title: "Drag to move" }, h("div.handle")),
      // Overlay buttons exist on every card; CSS shows them on the active one.
      h("div.flex-row.card-top-overlay", {}, btn("ins-above", "Insert Above", "gw-insert-above", "+")),
      h(
        "div.flex-column.card-right-overlay",
        {},
        btn("delete", "Delete Card", "gw-delete"),
        btn("ins-right", "Insert Child", "gw-insert-child", "+"),
        btn("edit", "Edit Card", "gw-open"),
      ),
      h("div.flex-row.card-bottom-overlay", {}, btn("ins-below", "Insert Below", "gw-insert-below", "+")),
      h(
        "div.view",
        {
          onclick: () => emit(this, "gw-activate", id),
          ondblclick: () => emit(this, "gw-open", id),
        },
        h("gw-markdown", { src: card.content, "card-id": id }),
      ),
    );
    el.dataset["isLast"] = String(card.isLast);
    if (card.hasChildren) el.append(fillet("top-right"), fillet("bottom-right"));
    this.attachDropRegions(el, id);
    return el;
  }

  private buildEditingCard(card: Card): HTMLElement {
    const textarea = h("gw-textarea", {
      "card-id": card.id,
      dir: "auto",
      class: "edit mousetrap",
      "data-private": "lipsum",
      "data-gramm": "false",
      "start-value": card.content,
    });
    const el = h(
      "div",
      {
        id: `card-${card.id}`,
        class: `card active editing${card.hasChildren ? " has-children" : ""}`,
        dir: "auto",
        "data-cloned-content": card.content,
      },
      textarea,
      h(
        "div.flex-column.card-right-overlay",
        {},
        h(
          "div.fullscreen-card-btn",
          { title: "Edit in Fullscreen", onclick: () => emit(this, "gw-edit-fullscreen") },
          icon(FULLSCREEN_ICON, 16),
        ),
        h("div.card-btn.save", {
          title: "Save Changes",
          onclick: () => emit(this, "gw-save-close"),
        }),
      ),
    );
    el.dataset["isLast"] = String(card.isLast);
    return el;
  }

  /* ---------- view state ---------- */

  /**
   * Mostly classes: this runs on every arrow keypress, so it must stay cheap
   * and must not reparse the tree.
   *
   * Entering or leaving edit mode is the exception -- that swaps a card's whole
   * body -- so the affected cards, and only those, are rebuilt in place.
   */
  private applyViewState() {
    const vs = jsonAttr<ViewState>(this, "view-state");
    if (!vs) return;

    const nextEditing = vs.editing ?? null;
    if (nextEditing !== this.editingId) {
      const affected = [this.editingId, nextEditing].filter((x): x is string => !!x);
      this.editingId = nextEditing;
      for (const id of affected) this.rebuildCard(id, nextEditing === id);
    }

    const ancestors = new Set(vs.ancestors);

    for (const [id, el] of this.cards) {
      el.classList.toggle("active", id === vs.active);
      el.classList.toggle("ancestor", ancestors.has(id));
    }
    for (const group of this.querySelectorAll<HTMLElement>(".group")) {
      const ids = [...group.querySelectorAll<HTMLElement>('[id^="card-"]')].map(
        (c) => c.id.slice(5),
      );
      group.classList.toggle("has-active", ids.includes(vs.active));
      group.classList.toggle(
        "active-descendant",
        ids.length > 0 && vs.descendants.includes(ids[0]!),
      );
    }
  }

  /** Replace one card's element in place, keeping its position in the DOM. */
  private rebuildCard(id: string, editing: boolean) {
    const old = this.cards.get(id);
    const card = this.data.get(id);
    if (!old || !card || !old.parentElement) return;
    const fresh = editing ? this.buildEditingCard(card) : this.buildCard(card);
    old.replaceWith(fresh);
    this.cards.set(id, fresh);
    this.contents.set(id, card.content);
  }

  /* ---------- drag and drop ---------- */

  private onDragStart(e: DragEvent, id: string) {
    this.dragged = id;
    // Deliberately empty: a drag needs a payload to start in some browsers,
    // but the payload is what the browser inserts wherever the drag lands, and
    // a card is not text. Which card is being dragged travels in `gw-drop`
    // instead. The id used to be the payload, and dropping a card on the one
    // being edited pasted 24 characters of hex into it (CODE_REVIEW.md E9).
    e.dataTransfer?.setData("text/plain", "");
    if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
    this.setAttribute("dragging", "");
    emit(this, "gw-drag-start", id);
  }

  private onDragEnd() {
    this.dragged = null;
    this.removeAttribute("dragging");
    for (const r of this.querySelectorAll(".drop-hover")) r.classList.remove("drop-hover");
    emit(this, "gw-drag-end");
  }

  /**
   * Drop targets are always in the DOM and revealed by CSS while [dragging] is
   * set, rather than added and removed as Elm's dropRegions did. Adding
   * elements mid-drag is what makes HTML5 drag/drop flicker.
   */
  private attachDropRegions(el: HTMLElement, id: string) {
    const region = (where: "above" | "into" | "below") => {
      const r = h("div", { class: `drop-region-${where}` });
      const external = () => this.getAttribute("external-drag") === "yes";

      r.addEventListener("dragover", (e) => {
        if (!this.dragged && !external()) return;
        if (this.dragged === id) return;
        e.preventDefault();
        r.classList.add("drop-hover");
      });
      // Text dragged in from outside is dropped by doc.js's document handler,
      // which asks Elm where -- so an external drag only reports the target.
      r.addEventListener("dragenter", (e) => {
        if (this.dragged || !external()) return;
        e.preventDefault();
        e.stopPropagation();
        emit(this, "gw-external-enter", { id, where });
      });
      r.addEventListener("dragleave", (e) => {
        r.classList.remove("drop-hover");
        if (this.dragged || !external()) return;
        e.stopPropagation();
        emit(this, "gw-external-leave", { id, where });
      });
      r.addEventListener("drop", (e) => {
        r.classList.remove("drop-hover");
        const dragged = this.dragged;
        if (!dragged || dragged === id) return; // external: doc.js handles it
        e.preventDefault();
        e.stopPropagation();
        emit(this, "gw-drop", { dragged, id, where });
      });
      return r;
    };
    el.append(region("above"), region("into"), region("below"));
  }
}

customElements.define("gw-tree", Tree);
