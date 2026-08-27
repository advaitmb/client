/**
 * Document metadata going out to the server (ADR-0001 seam 4): which `trees`
 * rows the server has not acknowledged, and getting them there — including
 * after the socket has been away.
 *
 * The `trees` table is where a document's name, its `deletedAt` and its
 * location live, and a row is stamped `synced: false` by every write that
 * changes one (rename, delete, and every card save, which bumps the
 * document's timestamp). Cards travel as deltas the Elm core pushes; metadata
 * travels as this one message, and nothing else tells the server about it —
 * there is no card in a rename or a delete.
 *
 * Two events decide when it goes out, and this module exists so that the
 * second one exists at all: the trees liveQuery emitting (Dexie is local, so
 * that happens whether or not there is a connection) and the socket opening.
 * Before, only the first did, and it sent with "drop it if the socket is
 * down" — so a rename or delete made offline sat unsynced until an unrelated
 * tree-table change or a reload happened to retrigger the liveQuery
 * (CODE_REVIEW.md D6).
 *
 * WHY A RECONNECT RE-DERIVES THE STATE INSTEAD OF QUEUEING THE MESSAGES
 *
 * The alternative fix was to let the liveQuery's message into doc.js's send
 * queue (`wsSend(…, true)`), which `onopen` drains. That queues one emission's
 * worth of rows at a time, and every one but the last is a state the document
 * has already left: an offline session that renames a document twice would
 * push the first name and then the second. Those rows are not invalid — they
 * carry their own `updatedAt` — but they are stale, they arrive as new news,
 * and a server that takes the last message it received at face value would
 * answer with the older name in a `trees` message, which doc.js bulk-puts
 * straight over the newer row in Dexie. The queue also grows without bound
 * while the connection is away.
 *
 * So the queue stays for the messages that are events (`pull`, `rt:join`), and
 * metadata — which is *state* — is re-derived at send time from the newest
 * emission. Both senders are this module, both send the same projection of the
 * same rows, and what they read only ever moves forward (a newer emission
 * replaces an older one, and every send reads it synchronously), so no send
 * can carry state older than one already sent, and a reconnect sends at most
 * one message however long it was away.
 *
 * The one thing that read is *behind* is a write whose emission has not
 * arrived yet, and that emission is exactly what sends it — the socket being
 * up by then.
 *
 * That last property is also why the resend reads the emission rather than
 * querying Dexie itself on reconnect. A query is asynchronous, so a rename
 * committed while it is in flight can emit, and be sent, before the query
 * answers — leaving the resend to send the state *before* that rename, after
 * the newer state has already gone out. Reading what the liveQuery last
 * emitted takes no turn of the event loop, so there is no window to lose.
 */

/**
 * The rows of the trees table that the server has not acknowledged, in the
 * shape the `trees` message carries.
 *
 * `synced` is this client's own bookkeeping and `collaborators` is the
 * server's answer rather than the client's to state, so neither is sent. A row
 * with no `synced` column at all is unsynced: that is a document this client
 * has just created (`InitDocument` writes no `synced`), and it has to go out.
 *
 * @param {Array<Object>} trees  every row of the trees table.
 */
function unsyncedTreeRows(trees) {
  return trees
    .filter((tree) => !tree.synced)
    .map(({ synced, collaborators, ...row }) => row);
}

/**
 * Start syncing document metadata for one session.
 *
 * One instance per logged-in session: `stop()` makes it inert for good (the
 * counterpart of `stopSyncing`'s teardown), and logging in again builds a new
 * one, so a reconnect can never push the rows of the account that left.
 *
 * @param {Object}   deps
 * @param {Function} deps.send    `send(tag, data)` — hand one message to the
 *                                socket. Called only when `isOpen()` is true.
 * @param {Function} deps.isOpen  whether the socket will take a message right
 *                                now (`ws.readyState === ws.OPEN`). Asked at
 *                                send time rather than tracked here, so this
 *                                module cannot come to disagree with the
 *                                socket about whether it is up.
 * @returns {{treesChanged: Function, socketOpened: Function, stop: Function}}
 */
function createMetadataSync({ send, isOpen }) {
  // The trees table as the liveQuery last emitted it. Not a backlog: a newer
  // emission replaces an older one, because what the server needs is the state
  // of those rows, not their history.
  let latestTrees = [];
  let stopped = false;

  function sendUnsynced() {
    if (stopped) return;
    if (!isOpen()) return;

    const unsynced = unsyncedTreeRows(latestTrees);
    if (unsynced.length === 0) return;

    send('trees', unsynced);
  }

  return {
    /**
     * The trees table changed: `trees` is every row of it, as the liveQuery
     * emitted it. Sends the unsynced rows if the socket is up, and otherwise
     * leaves them for the next `socketOpened` — which is the whole of D6.
     */
    treesChanged(trees) {
      latestTrees = trees;
      sendUnsynced();
    },

    /** The socket is open again: everything the server has not seen goes out. */
    socketOpened() {
      sendUnsynced();
    },

    /**
     * Stop syncing as this session (logout). Permanent: pws stops reconnecting
     * only once it has been closed explicitly, so an `onopen` for the departing
     * user can still be in flight after the liveQueries are gone.
     */
    stop() {
      stopped = true;
      latestTrees = [];
    },
  };
}

module.exports = {
  createMetadataSync: createMetadataSync,
};
