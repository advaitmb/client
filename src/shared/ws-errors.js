/**
 * What a failed websocket message handler owes the user (CODE_REVIEW.md E16).
 *
 * `doc.js`'s `ws.onmessage` handles every message type in one `switch`, and
 * that switch used to sit in one `try { … } catch (e) { console.log(e) }`. So a
 * Dexie write that threw while saving cards the server had just sent — incoming
 * sync data that never reached this device — produced exactly the same outcome
 * as a collaborator's cursor position failing to decode: a console line nobody
 * reads, and a user left editing a document quietly behind the server.
 *
 * The fix is not "surface everything": `rt` arrives every time a collaborator
 * moves, so a message type that fails on every frame would fill the screen. The
 * fix is to judge per message type, and this module is where that judgement
 * lives so it can be read and tested in one place.
 *
 * THE POLICY
 *
 * An allowlist of the benign types, and everything else is reported. Two
 * reasons for that direction rather than the other:
 *
 *   1. The serious cases are the ones that persist data. Being wrong about a
 *      benign type costs a toast; being wrong about a data type costs the
 *      user's work.
 *   2. A case added to the switch later is loud until somebody has thought
 *      about which side it is on. A list of serious types would let a new one
 *      be silent by default, which is how E16 happened.
 *
 * A type is benign only if a failure loses nothing the user cannot get back:
 *
 *   - `user` — an account-settings merge. The document is untouched, and the
 *     server re-sends the settings on the next change.
 *   - `rt`, `rt:users` — collaborator presence and cursor positions. The
 *     highest-frequency messages there are, and the next one replaces whatever
 *     a failed one lost.
 *   - `pushOk` — the acknowledgement of a push. Failing to apply it leaves the
 *     rows marked unsynced, so they go out again; and an acknowledgement Elm
 *     itself cannot read is reported from the Elm side (`Doc.Data.pushOkHandler`).
 *   - `pushError` — the push-failure path counts failures and raises its own
 *     `ErrorAlert` on the fourth, which is a better signal than one thrown
 *     handler.
 *
 * Everything else persists something (`cards`, `cardsConflict`, `trees`,
 * `treesOk`, `history`, `historyMeta`), asks for something that persists
 * (`doPull` — a pull that never goes out leaves this client silently behind), or
 * removes something (`removedFrom`). Those are reported, as is a frame that did
 * not parse, where there is no type to judge by at all.
 *
 * ONE TEXT PER FAILURE, DELIBERATELY
 *
 * The user-facing message carries no message type and no error detail. Partly
 * because `data.t` is protocol jargon, and partly because `Page.App` adds these
 * with `Toast.addUnique`: identical text is what keeps a type that fails on
 * every frame to a single toast. The type and the error itself go to the
 * console, which is where the detail is useful.
 */

/** Message types whose failure the user can do nothing with. See above. */
const BENIGN_MESSAGE_TYPES = ['user', 'rt', 'rt:users', 'pushOk', 'pushError'];

/**
 * What the user is told when a message that carries data could not be handled.
 *
 * Deliberately about the consequence ("may be missing", "reload") rather than
 * the cause: what all of these have in common is that this device's copy of the
 * document is no longer what the server sent, and reloading is the one thing
 * the user can do about it.
 */
const DATA_LOST_MESSAGE =
  'Some changes from the server could not be saved on this device, so what you see may be out of date. Please reload the page.';

/**
 * How to report one failed websocket message.
 *
 * @param {string|null} messageType  the message's `t` field, or null when the
 *   frame itself could not be parsed and there is no type to judge by.
 * @param {*} error  whatever was thrown. Never read for its properties: a
 *   rejected Dexie promise can carry anything, and this must not be the second
 *   thing that throws.
 * @returns {{consoleMessage: string, userMessage: string|null}}
 *   `consoleMessage` is always logged (with the error itself alongside it);
 *   `userMessage` is null when the failure stays in the console.
 */
function wsMessageFailure(messageType, error) {
  if (messageType === null || messageType === undefined) {
    return {
      consoleMessage: 'websocket: could not parse a message from the server',
      userMessage: DATA_LOST_MESSAGE,
    };
  }

  const consoleMessage = `websocket: handling a '${messageType}' message failed`;

  if (BENIGN_MESSAGE_TYPES.includes(messageType)) {
    return { consoleMessage: consoleMessage, userMessage: null };
  }

  return { consoleMessage: consoleMessage, userMessage: DATA_LOST_MESSAGE };
}

module.exports = {
  wsMessageFailure: wsMessageFailure,
};
