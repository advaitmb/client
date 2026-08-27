/**
 * What the port layer does when something it dispatched fails
 * (CODE_REVIEW.md S7, ADR-0001 seam 12).
 *
 * `doc.js` receives every message from Elm through one dispatch table, and the
 * whole table used to sit in one
 * `try { cases[msg]() } catch (err) { console.error("Unexpected message from Elm", …) }`.
 * Two things wrong with that, and they compound:
 *
 *   1. It mislabels. A handler that threw is a bug *in the handler*, not an
 *      unexpected message; reported as the latter, the tag looks like the
 *      culprit and the real error is buried behind a wrong sentence.
 *   2. It catches almost nothing. Most handlers are `async`, so their failures
 *      arrive as a rejected promise the `try` never sees — and *every* Dexie
 *      write in the table is one of those. A save, a delete, a rename, an
 *      import failing had exactly the same visible outcome as one that worked.
 *
 * THE POLICY
 *
 * Per tag, and the same shape and direction as `ws-errors.js`'s: an allowlist
 * of the benign tags, everything else reported to the user. Being wrong about a
 * benign tag costs a dialog; being wrong about a persisting one costs the
 * user's work — and a case added to the table later is loud until somebody has
 * decided which side it is on, which is the mistake this file exists to stop
 * repeating.
 *
 * A tag is benign when the failure loses nothing the user cannot see or redo:
 * the scroll did not happen, the caret did not move, the dialog did not open,
 * the collaborator's cursor is one message behind. The copy paths are benign
 * here because `clipboard.js` reports their real failure itself.
 *
 * Everything else either writes to Dexie or localStorage, or asks the server
 * for something that does (`PushDeltas`, `GetDocumentList`). Those are the ones
 * whose failure is invisible, and invisible is the whole problem.
 *
 * WHY A DIALOG AND NOT A TOAST
 *
 * Reaching Elm's toasts from here means the `ErrorAlert` port, which is the
 * *sync* error channel: it sets `errorState` and is cleared by the next
 * successful push. A local write failing has nothing to do with sync and would
 * sit there until an unrelated push cleared it. So the caller `alert()`s, which
 * is what `save.js` and the clipboard paths already do (ticket 18).
 */

/** Tags whose failure the user can do nothing with. See above. */
const BENIGN_MESSAGE_TAGS = [
  // Dialogs and window state: what failed is what the user just asked for and
  // visibly did not get.
  'Alert', 'Print', 'SetFullscreen', 'RequestFullscreen', 'ConfirmCancelCard',
  // Pure DOM — scrolling, selection, the caret, and text edits the user is
  // looking at.
  'ScrollCards', 'ScrollFullscreenCards', 'SelectAll', 'SetField',
  'SetCursorPosition', 'TextSurround', 'InsertMarkdownLink',
  // The clipboard reports its own failures (clipboard.js), with the reason.
  'CopyToClipboard', 'CopyCurrentSubtree',
  // Presence and drags: the next message replaces whatever a failed one lost.
  'SendCollabState', 'DragStart', 'DragDone',
  // The history view: a slider that does not move is the whole of the failure.
  'HistorySlider',
  // A console line, and the handlers that do nothing at all.
  'ConsoleLogRequested', 'UpdateCommits', 'EmptyMessageShown', 'InitBeamer',
  'SocketSend',
];

/**
 * What the user is told when a message that changes something could not be
 * handled.
 *
 * About the consequence rather than the cause, and identical for every tag: the
 * text is what keeps a tag that fails on every message to one dialog instead of
 * a stack of them. The tag and the error itself go to the console, which is
 * where the detail is useful.
 */
const NOT_SAVED_MESSAGE =
  'Something went wrong on this device, and your last change may not have been saved.\n\nPlease reload the page and check your most recent work.';

/**
 * How to report one failed port message.
 *
 * @param {string} tag  the message's tag, as Elm sent it.
 * @param {*} error  whatever was thrown or rejected with. Never read for its
 *   properties: a rejected Dexie promise can carry anything, and the report
 *   must not be the second thing that throws.
 * @returns {{consoleMessage: string, userMessage: string|null}}
 *   `consoleMessage` is always logged (with the error itself alongside it);
 *   `userMessage` is null when the failure stays in the console.
 */
function portMessageFailure(tag, error) {
  const consoleMessage = `port: handling the '${tag}' message from Elm failed`;

  if (BENIGN_MESSAGE_TAGS.includes(tag)) {
    return { consoleMessage: consoleMessage, userMessage: null };
  }

  return { consoleMessage: consoleMessage, userMessage: NOT_SAVED_MESSAGE };
}

/**
 * Whether an uncaught error looks like a browser extension rewriting the DOM
 * under the app.
 *
 * Grammarly and LastPass inject nodes into the editing card; Elm's virtual DOM
 * then patches against children it did not put there and throws from inside its
 * own render. The app cannot recover, so `doc.js`'s `window` error handler says
 * so and moves the injected nodes out of the way.
 *
 * Total over its argument on purpose: the `error` event also fires for failed
 * *resource* loads, whose event carries no `message` at all, and calling
 * `.match` on that threw inside the error handler itself.
 */
function isExtensionInterference(message) {
  if (typeof message !== 'string') {
    return false;
  }

  return (
    /Cannot read properties of undefined \(reading 'childNodes'\)/.test(message) ||
    /Failed to execute 'removeChild' on 'Node'/.test(message)
  );
}

module.exports = {
  portMessageFailure: portMessageFailure,
  isExtensionInterference: isExtensionInterference,
};
