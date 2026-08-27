/**
 * The drag lifecycle on the JS side of the ports (ADR-0001 seam 4).
 *
 * Two different drags land on this document:
 *
 *   - a **card drag**: a card being moved from one place in the tree to
 *     another. `<gw-tree>` owns it end to end — it renders the drop regions,
 *     reports the drop to Elm as `gw-drop`, and stops that drop from
 *     propagating, so a document-level handler never sees one.
 *   - an **external drag**: text (or a file, or an Obsidian link) dragged in
 *     from outside the app. Nothing else can see this one, so recognizing it,
 *     telling Elm where it may land, and handing over what was dropped is this
 *     module's job alone.
 *
 * Telling the two apart is therefore the whole point, and it used to be
 * impossible: the flag was set only by the elm-dnd `DragStart` port, dead on
 * both sides since the tree became a custom element (CODE_REVIEW.md §6), so
 * every card drag announced itself to Elm as text arriving from outside, and
 * nothing ever cleared the flags afterwards (E8). A card drag now says so
 * itself, through the `gw-drag-start` / `gw-drag-end` pair `<gw-tree>` emits:
 * `dragend` fires at the drag's source whatever the drag ended in — dropped,
 * refused, cancelled with Escape — which is the one reset that cannot be
 * missed. Elm's `DragDone` (`dragDone()` below) says the same thing about a
 * drop it has handled.
 *
 * It lives here rather than inline in doc.js for the reason session.js and
 * save.js do: doc.js starts the whole app at module load, so nothing in it can
 * be imported by a test. Its collaborators are passed in — the element to
 * listen on, `toElm`, the viewport geometry doc.js measures, the element that
 * scrolls sideways, and the timers, so an autoscroll is testable without
 * waiting for one.
 */

/** Pixels per autoscroll step, and how often a step is taken. */
const SCROLL_AMOUNT = 20;
const SCROLL_INTERVAL_MS = 15;

/** The header covers the top of the window; scrolling starts below it. */
const HEADER_HEIGHT = 40;

/** How near an edge the pointer has to be for the view to follow it. */
const EDGE_FRACTION = 0.1;

/**
 * Which way the pointer asks to scroll along one axis: -1 back (up / left),
 * 1 on (down / right), 0 nowhere.
 *
 * A span that is zero, negative or unknown (doc.js has no sidebar width until
 * a session is loaded) asks for nothing, rather than for NaN.
 *
 * @param {number} coordinate  the pointer, in client coordinates.
 * @param {number} start  where the scrollable area begins on this axis.
 * @param {number} end  where it ends.
 */
function edgeDirection(coordinate, start, end) {
  const span = end - start;
  if (!(span > 0)) return 0;
  const relative = (coordinate - start) / span;
  if (relative <= EDGE_FRACTION) return -1;
  if (relative >= 1 - EDGE_FRACTION) return 1;
  return 0;
}

/**
 * The textarea of the card being edited: the one element in the app the
 * browser's own drop handling belongs to.
 *
 * Matched on the element rather than an exact class string, because the same
 * two classes reach it from two places (`tree.ts` for the card being edited,
 * `Doc/Fullscreen.elm` for the fullscreen editor) and `<gw-textarea>` copies
 * them onto the textarea it renders.
 */
function isOpenEditor(node) {
  return (
    !!node &&
    node.nodeName === "TEXTAREA" &&
    !!node.classList &&
    node.classList.contains("edit") &&
    node.classList.contains("mousetrap")
  );
}

/**
 * Listen for drags on `root` (the document, in the app).
 *
 * @param {Object}   deps
 * @param {EventTarget} deps.root  where the document-level listeners go.
 * @param {Function} deps.toElm  send a tagged message to Elm.
 * @param {Function} deps.viewport  () => `{width, height, sidebarWidth}`, the
 *   geometry the edge thresholds are measured against.
 * @param {Function} deps.scrollRoot  () => the element that scrolls sideways
 *   through the columns (`#document`).
 * @param {Object}   [deps.timers]  `{setInterval, clearInterval}`.
 * @returns {Object} `{dragDone}` — Elm's side of the same lifecycle.
 */
function installDragHandlers(deps) {
  const { root, toElm, viewport, scrollRoot } = deps;
  const timers = deps.timers || { setInterval: setInterval, clearInterval: clearInterval };

  /** Which kind of drag is in progress, if any. */
  let draggingCard = false;
  let draggingExternal = false;

  /** The interval scrolling each axis, while one is scrolling. */
  const scrolling = { vertical: null, horizontal: null };

  function stopScrolling(axis) {
    if (scrolling[axis] === null) return;
    timers.clearInterval(scrolling[axis]);
    scrolling[axis] = null;
  }

  function stopAllScrolling() {
    stopScrolling("vertical");
    stopScrolling("horizontal");
  }

  /**
   * Keep scrolling `element` by (dx, dy) until something stops this axis.
   *
   * With no element there is nothing to scroll and no scrolling starts: the
   * header, the sidebar and the padding columns all sit inside an edge tenth
   * of the window while being no column at all, and the interval body used to
   * dereference that missing column every 15 ms (CODE_REVIEW.md E15). An
   * autoscroll already running is left alone, so a column that scrolled out
   * from under the pointer keeps going while the pointer stays on the edge.
   */
  function startScrolling(axis, element, dx, dy) {
    if (!element || scrolling[axis] !== null) return;
    scrolling[axis] = timers.setInterval(() => element.scrollBy(dx, dy), SCROLL_INTERVAL_MS);
  }

  /** The column under the pointer, if the pointer is over one at all. */
  function columnUnder(ev) {
    const path = ev.path || (ev.composedPath ? ev.composedPath() : []);
    return path.find((node) => node.classList && node.classList.contains("column")) || null;
  }

  function autoScroll(ev) {
    const { width, height, sidebarWidth } = viewport();
    const vertical = edgeDirection(ev.clientY, HEADER_HEIGHT, height);
    const horizontal = edgeDirection(ev.clientX, sidebarWidth, width);

    if (vertical === 0) stopScrolling("vertical");
    else startScrolling("vertical", columnUnder(ev), 0, vertical * SCROLL_AMOUNT);

    if (horizontal === 0) stopScrolling("horizontal");
    else startScrolling("horizontal", scrollRoot(), horizontal * SCROLL_AMOUNT, 0);
  }

  /** No drag is in progress any more, whichever kind it was. */
  function endDrag() {
    draggingCard = false;
    draggingExternal = false;
  }

  /**
   * Hand what was dropped on the tree to Elm, which inserts it as a card.
   *
   * An Obsidian link names a file rather than carrying text, so the file's
   * name becomes the card instead of the URL.
   */
  function dropExternalText(ev) {
    const dropText = ev.dataTransfer.getData("text");
    if (dropText.startsWith("obsidian://open?")) {
      const url = new URL(dropText);
      toElm("# " + url.searchParams.get("file"), "docMsgs", "DropExternal");
    } else {
      toElm(dropText, "docMsgs", "DropExternal");
    }
  }

  /**
   * A drag over the card being edited.
   *
   * The browser's own handling is what belongs here for text from outside the
   * app: an open editor is a text field, and dropped text belongs at the
   * caret. So the default is deliberately *not* prevented, and Elm is told
   * nothing — the text landed in the card being edited, not in the tree, and a
   * card made from it as well would be a second copy.
   *
   * A dragged card is not text, though: it used to insert its own
   * 24-character id into whatever was open (CODE_REVIEW.md E9). Preventing the
   * default is what makes dropping a card on an open editor do nothing at all.
   */
  function onEditorDrag(ev) {
    if (draggingCard) ev.preventDefault();
    if (ev.type === "drop") {
      // Elm keeps believing an external drag is in progress until the next one
      // ends over the tree. That only decides how <gw-tree> reads drag events,
      // of which there are none until a drag starts, and the next external
      // drag sets it again -- where telling Elm "dropped, nothing to insert"
      // through the one message it has for that (`DropExternal`) would risk a
      // blank card from a stale drop region.
      endDrag();
    }
  }

  function onDrag(ev) {
    // A drop ends the drag, wherever it landed, so nothing keeps scrolling.
    if (ev.type === "drop") stopAllScrolling();

    if (isOpenEditor(ev.target)) {
      onEditorDrag(ev);
      return;
    }

    if (ev.type === "dragover") autoScroll(ev);

    if (ev.type === "drop") {
      if (draggingExternal) dropExternalText(ev);
      endDrag();
    }

    // Both types need this: a dragover that allows no drop makes the app an
    // invalid drop target, and a drop left to the browser navigates away to
    // whatever was dropped.
    ev.preventDefault();
  }

  // A card drag reports itself, because nothing else can see one: its drop is
  // stopPropagation()ed inside <gw-tree>.
  root.addEventListener("gw-drag-start", () => {
    draggingCard = true;
  });
  root.addEventListener("gw-drag-end", () => {
    draggingCard = false;
    stopAllScrolling();
  });

  // Anything else entering the document came from outside the app.
  root.addEventListener("dragenter", () => {
    if (draggingCard || draggingExternal) return;
    draggingExternal = true;
    toElm(null, "docMsgs", "DragExternalStarted");
  });

  root.addEventListener("dragleave", (ev) => {
    // Dragged out of the window: there is no pointer over a column any more.
    if (ev.relatedTarget === null) stopAllScrolling();
  });

  root.addEventListener("dragover", onDrag);
  root.addEventListener("drop", onDrag);

  return {
    /** Elm handled a card drop (the `DragDone` port message). */
    dragDone: () => {
      draggingCard = false;
    },
  };
}

module.exports = {
  installDragHandlers: installDragHandlers,
};
