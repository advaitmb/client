// Which keystrokes the app's shortcuts act on (ADR-0001 seam 14).
//
// Mousetrap binds the whole map on `document` -- `h`/`j`/`k`/`l`, the four
// arrows, `w`, `/`, `?`, `esc` and the mod-chords (`doc-helpers.js`'s
// `shortcuts`) -- so every keystroke anywhere in the page is a candidate for
// moving the card cursor, splitting a card or opening a modal. Whether a given
// one is Mousetrap's business is the `stopCallback` decision, and this module
// is it: from (the element the keystroke was aimed at, the combo it matched) to
// whether the app acts on it.
//
// Mousetrap's own answer ignores form fields and nothing else, which was the
// whole truth while every other control in the app was a `div` with `onclick`.
// It stopped being true when the header's icons, menu entries, theme swatches
// and export toggles became real `<button>`s (tickets 32-34): a focused button
// is not a form field, so typing `j` with the export menu open moved the card
// cursor behind the open menu. The controls guard the keys they *handle*
// (`stopActivationKeys` in `src/ui/header.ts` -- Enter, Space, and the arrows
// the radio groups steer with), which is a different question and cannot cover
// the keys no control handles.

/**
 * The app's chrome: the regions whose own controls a keystroke is for.
 *
 * A region is on this list when the keyboard inside it is aimed at *it* -- the
 * header's menus, the sidebar's rail, a modal's fields and buttons. It is a
 * judgement per surface, not a property of being a custom element: `<gw-tree>`
 * and `<gw-markdown>` render the document itself, where the shortcuts ARE the
 * interaction, so they are deliberately absent. So is the Elm-rendered
 * furniture around the document -- the breadcrumbs, the shortcut tray with its
 * formatting-guide link, the mobile buttons -- for the same reason: the next
 * keystroke after clicking one of those belongs to the document.
 *
 * The Elm-rendered chrome (the export dialog, the sidebar context menu, the
 * toasts, the conflict banner) is not here because it holds no focusable
 * control: every one of them is still a `div` with `onclick` (CODE_REVIEW.md
 * S12's remainder), so no keystroke can be aimed at one. A surface joins this
 * list when it gains a real control, and the sidebar is already here for when
 * its own `div`s become buttons.
 */
const CHROME = [
  "gw-header",
  "gw-sidebar",
  "gw-help-modal",
  "gw-wordcount-modal",
  "gw-switcher-modal",
  "gw-template-modal",
].join(", ");

/**
 * Does a keystroke aimed at `element` reach the app's shortcuts?
 *
 * `combo` is Mousetrap's name for the keystroke ("j", "esc", "mod+s"), not the
 * raw key: this is asked once Mousetrap has matched a binding, so the answer is
 * about a shortcut and not about typing.
 *
 * The rule, in the order the questions have to be asked:
 *
 * 1. `.mousetrap` -- Mousetrap's own opt-in, and this app means it: the card
 *    editor's textarea (`edit mousetrap`) and the switcher's search box are
 *    fields where the shortcuts are half the point (`mod+enter` to save, the
 *    arrows to pick a document). It comes first so a marked field inside the
 *    chrome keeps them.
 * 2. A form field consumes its own keystrokes -- Mousetrap's default rule, kept
 *    whole, Escape included. That is what the title field, the sidebar filter
 *    and the search box already relied on, and narrowing it here would send
 *    `esc` to the document from a field that was only being typed in.
 * 3. Inside the chrome, an *unmodified* keystroke is the control's: a button, a
 *    link or a radio is operated with Enter, Space, the arrows and Tab, and
 *    everything else unmodified is typing. None of it asked for the document
 *    behind the open menu to move. Two exceptions, in opposite directions:
 *    - **Escape** goes to the app, because it is the way *out* of the chrome —
 *      Elm owns which menu or modal is open, and no control here closes itself.
 *    - **A modifier chord** goes to the app, because no button, link or radio
 *      interprets one: `mod+s` means save wherever it is pressed. The controls
 *      that *do* read chords are the fields, and rule 2 has already answered
 *      for them (`mod+v` in the title field is the field's paste). Letting the
 *      chord through also keeps the app's override of the browser's own
 *      shortcuts: `doc-helpers.js`'s `needOverride` cancels `mod+s`, `mod+o`
 *      and `alt+0`-`alt+6` from *inside* the shortcut handler, so a chord
 *      stopped here would open the browser's Save-page or Open-file dialog
 *      instead of doing nothing.
 * 4. Otherwise the keystroke is the document's, which is the deliberate case:
 *    focus on `<body>` after clicking a card, or on a link inside a card's
 *    rendered markdown.
 *
 * Total over whatever the port layer hands it. `element` is `e.target`, which
 * for a keystroke with nothing focused is `document` itself -- no `closest`, and
 * no control the keystroke could have been meant for, so the app gets it.
 */
export function shortcutReachesApp(element, combo) {
  if (!element || typeof element.closest !== "function") return true;

  // `classList` rather than the string match Mousetrap does on `className`:
  // an SVG element's `className` is an SVGAnimatedString, not a string, so the
  // match would silently fail on the glyph inside a button.
  if (element.classList.contains("mousetrap")) return true;

  if (isFormField(element)) return false;

  if (element.closest(CHROME) !== null) return isTheApps(combo);

  return true;
}

/* === Private === */

function isFormField(element) {
  const tag = element.tagName;
  // `isContentEditable` is Mousetrap's own test and is kept for the same
  // reason: an editable div is a field however it is spelled. jsdom does not
  // implement the property, so nothing here can pin it.
  return tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA" || element.isContentEditable === true;
}

/**
 * The two kinds of keystroke the app still acts on from inside the chrome: the
 * way out, and the chords no control reads. See rule 3.
 */
function isTheApps(combo) {
  return isExit(combo) || isChord(combo);
}

/**
 * Escape, by either spelling Mousetrap accepts for it. `doc-helpers.js` binds
 * "esc"; "escape" is the same key and the same intent, and matching both keeps
 * the exit working if a binding is ever written the other way.
 */
function isExit(combo) {
  const raw = String(combo).toLowerCase();
  return raw === "esc" || raw === "escape";
}

/**
 * Does `combo` carry a modifier other than shift?
 *
 * Mousetrap combos are `+`-separated ("mod+shift+j", "alt+left"), and `mod` is
 * its own name for cmd-on-a-Mac-and-ctrl-elsewhere. **Shift is not one of
 * these**: `shift+enter` and `?` are what typing looks like, so they are the
 * control's like every other unmodified key.
 */
function isChord(combo) {
  const raw = String(combo).toLowerCase();
  // Mousetrap's own reading of the plus key, which is a key and not a
  // separator: "+" on its own, and doubled inside a chord ("mod++").
  if (raw === "+") return false;
  const parts = raw.replace(/\+{2}/g, "+plus").split("+");
  // The last part is the key; only what precedes it can be a modifier.
  return parts.slice(0, -1).some((part) => part !== "shift");
}
