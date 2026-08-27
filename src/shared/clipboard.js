/**
 * Clipboard failures, handled the same way wherever they happen
 * (CODE_REVIEW.md E16).
 *
 * There are three clipboard calls in the port layer — copying a card subtree
 * (`CopyCurrentSubtree` in doc-helpers.js), copying a support address
 * (`CopyToClipboard` in doc.js) and pasting (`mod+v`) — and each of them used to
 * treat a refusal differently:
 *
 *   - The paste path caught only errors whose `message` contained "denied" and
 *     dropped everything else on the floor. Worse, it read `err.message`
 *     unguarded, so an error without one threw a second time *inside the catch*.
 *   - Both copy paths attached no handler at all, so a refused copy was an
 *     unhandled rejection — behind a flash animation that told the user it had
 *     worked.
 *
 * Every clipboard call is a browser permission away from failing, on every
 * browser, so all three go through this module now.
 *
 * WHY THESE STAY `alert()`S AND DO NOT BECOME TOASTS
 *
 * The toast machinery is Elm's, and reaching it from here means the `ErrorAlert`
 * port — which is the *sync* error channel: it sets `errorState`, shows a
 * persistent toast, and is cleared by the next successful push (`Page.App`'s
 * PushOk branch). A refused paste has nothing to do with sync and would sit
 * there until an unrelated push cleared it. A clipboard failure is a one-off
 * answer to something the user just pressed, which is what `alert` is for and
 * what the permission-denied path already used — the same choice save.js makes
 * for a failed save.
 */

/**
 * The advice for a refused clipboard permission: the one clipboard failure the
 * user can actually fix, so it says how.
 */
const PERMISSION_MESSAGE =
  'Clipboard access denied. Click on the padlock icon in the address bar and allow clipboard access.';

/**
 * Whether a thrown value is the browser refusing permission.
 *
 * Checks the DOMException name first and the wording second: `NotAllowedError`
 * is what the spec says a refusal is, but the wording check is what the code
 * here has always used and some browsers phrase a refusal without ever setting
 * that name. Both reads are guarded, because this is called from a catch block
 * and must not be the second thing to throw.
 */
function isPermissionDenied(error) {
  if (!error || typeof error !== 'object') return false;

  if (error.name === 'NotAllowedError' || error.name === 'SecurityError') return true;

  return typeof error.message === 'string' && /denied/i.test(error.message);
}

/**
 * Whatever a thrown value has to say for itself, as a string.
 *
 * Never throws, whatever it is handed: a rejected clipboard promise can carry a
 * DOMException, a bare string, or nothing at all.
 */
function describeError(error) {
  if (error === null || error === undefined) return 'unknown error';
  if (typeof error === 'string') return error;

  if (typeof error === 'object') {
    if (typeof error.message === 'string' && error.message !== '') return error.message;
    if (typeof error.name === 'string' && error.name !== '') return error.name;
  }

  return String(error);
}

/**
 * What to tell the user about a failed clipboard call.
 *
 * @param {'copy'|'read'} operation  which direction the clipboard was used in.
 * @param {*} error  whatever the clipboard promise rejected with.
 * @returns {string} a message to show, never empty.
 */
function clipboardErrorMessage(operation, error) {
  if (isPermissionDenied(error)) return PERMISSION_MESSAGE;

  const what = operation === 'copy' ? 'copy to the clipboard' : 'read from the clipboard';

  return `Could not ${what}: ${describeError(error)}`;
}

/**
 * Copy text to the clipboard, reporting a failure instead of rejecting.
 *
 * Both copy call sites live in a synchronous dispatch table that does not await
 * what it calls, so a rejection escaping this function is an unhandled one.
 * Nothing here rejects.
 *
 * @param {string} text  what to put on the clipboard.
 * @param {Object} deps
 * @param {Object|undefined} deps.clipboard  `navigator.clipboard` — undefined
 *   outside a secure context, which is a failure to report like any other.
 * @param {Function} deps.onError  tell the user, given a message.
 * @returns {Promise<boolean>} whether the text was copied.
 */
async function copyText(text, { clipboard, onError }) {
  try {
    if (!clipboard || typeof clipboard.writeText !== 'function') {
      throw new Error('the clipboard is not available in this browser context');
    }

    await clipboard.writeText(text);
    return true;
  } catch (error) {
    onError(clipboardErrorMessage('copy', error));
    return false;
  }
}

module.exports = {
  clipboardErrorMessage: clipboardErrorMessage,
  copyText: copyText,
};
