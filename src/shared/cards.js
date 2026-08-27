/**
 * Reading the local card log (ADR-0001 seam 4).
 *
 * `cards` is an append-mostly table of version rows: a card is edited by
 * writing a new row with a newer stamp, and deleted by writing a row with
 * `deleted: 1`. So no reader may take the table at face value. Every one of
 * them has to collapse it to one row per id — the newest — and *then* drop the
 * ids whose newest row is a deletion (ADR-0005 §1, and `newestVisible` in
 * `Doc/Data.elm`, which is the Elm half of the same rule).
 *
 * The order matters and is the reason this is a module rather than two lines at
 * each call site: filtering `deleted` first leaves a deleted card's older row
 * as the newest survivor, so the card comes back — with its pre-deletion
 * content.
 *
 * It lives outside `doc.js` for the reason `save.js` and `session.js` do:
 * `doc.js` boots the whole app at module load, so nothing in it can be
 * imported by a test.
 */

const { newestVersionPerId } = require("./stamps");

/**
 * The document's cards, as the log currently says they are: one row per id,
 * the newest, with the deleted ids gone. Newest card first (the order
 * `newestVersionPerId` yields); no reader here depends on that order.
 *
 * @param {Array<Object>} rows  version rows, straight from Dexie.
 */
function visibleCards(rows) {
  return newestVersionPerId(rows).filter((card) => !card.deleted);
}

/**
 * The card to activate when a document opens: its first root card.
 *
 * "First" is by `position`, the same order the tree view puts them in — a
 * document can have several root cards, and the activation used to take
 * whichever Dexie happened to return first (`updatedAt` order), which is the
 * most recently written one, not the top one.
 *
 * @returns {string|null} null when the document has no visible root card,
 *   which the caller must handle: reading `.id` off the missing card is what
 *   made a document whose root had been deleted white-screen on open (S8).
 */
function rootCardId(rows) {
  const roots = visibleCards(rows)
    .filter((card) => card.parentId === null)
    .sort((a, b) => a.position - b.position);

  return roots.length === 0 ? null : roots[0].id;
}

/**
 * The whole document as one `<gingko-card>` string — what the ImmortalDB
 * backup holds. Write-only: nothing reads it back, it is there so a user whose
 * IndexedDB is lost still has their text somewhere.
 *
 * Because it is built from `visibleCards`, a deleted card's subtree goes with
 * it: `treeHelper` only descends from cards that are in the snapshot, so an
 * orphan cannot reappear as a root card either.
 */
function backupSnapshotText(rows) {
  return treeHelper(visibleCards(rows), null).map(treeToGkw).join("\n");
}

/* === Private === */

function treeHelper(cards, parentId) {
  return cards
    .filter((card) => card.parentId === parentId)
    .sort((a, b) => a.position - b.position)
    .map((card) => ({
      id: card.id,
      content: card.content,
      children: treeHelper(cards, card.id),
    }));
}

function treeToGkw(tree) {
  return (
    '<gingko-card id="' +
    tree.id +
    '">\n\n' +
    tree.content +
    "\n\n" +
    tree.children.map(treeToGkw).join("\n\n") +
    "</gingko-card>"
  );
}

module.exports = {
  visibleCards: visibleCards,
  rootCardId: rootCardId,
  backupSnapshotText: backupSnapshotText,
};
