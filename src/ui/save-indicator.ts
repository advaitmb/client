/**
 * <gw-save-indicator> — whether the document's work is safe: saved here,
 * synced to the server, or neither.
 *
 * Replaces Doc.UI.viewSaveIndicator, and the copy of it that used to live
 * inside header.ts. There were two implementations of these branches, and they
 * had drifted (CODE_REVIEW.md S1): the copy had no "Database Error..." branch,
 * and it read the zero timestamp of a document still loading as an offline
 * save. There is one now, and both surfaces render it as this element:
 *
 *   - the document header (`header.ts`, inside the title span)
 *   - the fullscreen editor (`Doc/Fullscreen.elm`, via Doc.UI.viewSaveIndicator)
 *
 * Elm decides the state and encodes it once, in `Doc.UI.encodeSaveState`, so a
 * future change to what "saved" means is made in one place on each side.
 *
 * Contract — attributes in
 *   save   JSON { dirty, lastLocalSave, lastRemoteSave, now } (epoch ms;
 *          lastLocalSave/lastRemoteSave may be null). Absent means "no answer
 *          yet", and renders empty.
 *
 * No events out: nothing here is clickable.
 *
 * The stylesheet keys off `#save-indicator.<state>` (and
 * `#fullscreen-buttons #save-indicator`), so the *caller* gives this element
 * its id — as Elm gives `<gw-header>` its `#document-header` — and the element
 * owns its class list.
 */

import { h, icon } from "./dom";
import { jsonAttr } from "./modal";
import { relativeTime } from "./relative-time";

/** The document's save state, as Elm's `save` attribute carries it. */
export interface Save {
  dirty: boolean;
  lastLocalSave: number | null;
  lastRemoteSave: number | null;
  now: number;
}

const GLYPH = {
  /** A 3/4 circle; the stylesheet spins it for `.never-saved`. */
  loading: "M20.9 12a9 9 0 1 0-3.6 7.2",
  info: "M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zM12 16v-4M12 8h.01",
  warning:
    "M12 9v4M12 17h.01M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z",
  check: "M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zM7.5 12.4l3 3 6-6.4",
  error: "M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zM15 9l-6 6M9 9l6 6",
};

interface State {
  /** What the user reads. */
  label: string;
  /** The `title` tooltip: when the thing the label is about last happened. */
  tip: string;
  /** The stylesheet's name for this state. */
  name: string;
  glyph: string;
}

/**
 * The one set of branches, in the order Doc.UI.viewSaveIndicator had them.
 *
 * A `lastLocalSave` of epoch 0 with nothing synced is a document still loading,
 * not an offline save: an unset timestamp decodes to 0, and the two are
 * indistinguishable from here.
 */
export function saveState(s: Save): State {
  const since = (t: number | null) => (t === null ? "" : relativeTime(t, s.now));
  const loading = { label: "Loading...", tip: "", name: "never-saved", glyph: GLYPH.loading };

  if (s.dirty) {
    return {
      label: "Unsaved Changes...",
      tip: `Last saved ${since(s.lastLocalSave)}`,
      name: "unsaved",
      glyph: GLYPH.info,
    };
  }
  if (s.lastLocalSave === null && s.lastRemoteSave === null) return loading;
  if (s.lastRemoteSave === null) {
    if (s.lastLocalSave === 0) return loading;
    return {
      label: "Saved Offline",
      tip: `Last synced ${since(s.lastLocalSave)}`,
      name: "saved-offline",
      glyph: GLYPH.warning,
    };
  }
  if (s.lastLocalSave === null) {
    // The server has this document and this browser's database has no record
    // of ever saving it.
    return {
      label: "Database Error...",
      tip: `Last synced ${since(s.lastRemoteSave)}`,
      name: "database-error",
      glyph: GLYPH.error,
    };
  }
  if (s.lastLocalSave <= s.lastRemoteSave) {
    return {
      label: "Synced",
      tip: `Last edit ${since(s.lastLocalSave)}`,
      name: "synced",
      glyph: GLYPH.check,
    };
  }
  return {
    label: "Saved Offline",
    tip: `Last synced ${since(s.lastRemoteSave)}`,
    name: "saved-offline",
    glyph: GLYPH.warning,
  };
}

class SaveIndicator extends HTMLElement {
  static observedAttributes = ["save"];

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render();
  }

  private render() {
    const save = jsonAttr<Save>(this, "save");
    if (save === null) {
      // No answer yet (the document is being opened). Showing a state here
      // would be inventing one.
      this.className = "";
      this.replaceChildren();
      return;
    }

    const { label, tip, name, glyph } = saveState(save);
    // `inset` is carried over from the Elm view's class list.
    this.className = `inset ${name}${save.dirty ? " saving" : ""}`;
    this.replaceChildren(icon(glyph, 16), h("span", { title: tip }, label));
  }
}

customElements.define("gw-save-indicator", SaveIndicator);
