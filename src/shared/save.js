/**
 * The local half of a save — the port layer's side of `SaveCardBased`
 * (ADR-0001 seam 4).
 *
 * Elm decides *what* a save changes (`Doc.Data.localSave`, `cardDataReceived`,
 * `restore`, `resolveConflicts`, `pushOkHandler`, `importTree`) and hands the
 * change lists over the port; this is everything that happens next locally:
 * the card rows are applied in one transaction, a local history snapshot is
 * written when the document's content changed, and the document's row is
 * stamped unsynced so the trees liveQuery pushes the new timestamp.
 *
 * It lives here rather than inline in `doc.js`'s dispatch table because
 * `doc.js` starts the whole app at module load (`initElmAndPorts`), so nothing
 * in it can be imported by a test. Its collaborators are passed in: the Dexie
 * database, the three clock/id sources, and the two callbacks for what only
 * the port layer owns (the dirty flag and telling the user).
 */

const { maxStamp, newestVersionPerId } = require("./stamps");

/**
 * Everything about a save that can be decided without touching the database.
 *
 * `treeId` is required, and that is the point: a save says which document it
 * belongs to. There is no falling back to the document on screen — an import
 * saves into a document nobody has opened yet, and the port message that
 * creates it travels in the same unordered `Cmd.batch` (CODE_REVIEW.md D5).
 *
 * @param {Object} payload  the `SaveCardBased` port payload.
 * @returns {string|null} the message to show the user, or null if the payload
 *   is one we can apply.
 */
function cardBasedSaveError(payload) {
  if (payload && Array.isArray(payload.errors)) {
    return "Error saving data!\n\n" + payload.errors.join("\n----\n");
  }

  if (!payload || !payload.treeId || !payload.toAdd || !payload.toMarkSynced || !payload.toMarkDeleted || !payload.toRemove) {
    return "Error saving data!\nInvalid data sent to DB:\n" + JSON.stringify(payload);
  }

  return null;
}

/**
 * Apply one save.
 *
 * @param {Object}   payload  the `SaveCardBased` port payload:
 *   `{treeId, toAdd, toMarkSynced, toMarkDeleted, toRemove}` — or `{errors}`
 *   when Elm could not build a save at all.
 * @param {Object}   deps
 * @param {Object}   deps.db             the Dexie database (`cards`, `trees`,
 *                                       `tree_snapshots`, `transaction`).
 * @param {Function} deps.nextStamp      mints an HLC stamp for a new row.
 * @param {Function} deps.newDeleteHash  mints the hash a deletion batch shares.
 * @param {Function} deps.now            wall-clock ms, for the tree row.
 * @param {Function} deps.markClean      the document is no longer dirty.
 * @param {Function} deps.onError        tell the user a save failed.
 */
async function applyCardBasedSave(payload, deps) {
  const { db, nextStamp, newDeleteHash, now, markClean, onError } = deps;

  const error = cardBasedSaveError(payload);
  if (error !== null) {
    onError(error);
    return;
  }

  // Which document this save is for is the payload's to say, not the port
  // layer's to remember: `TREE_ID` is the document on screen, and an import
  // saves into one that is not.
  const treeId = payload.treeId;

  const newData = payload.toAdd.map((c) => { return { ...c, updatedAt: nextStamp() }});
  const toMarkSynced = payload.toMarkSynced.map((c) => { return { ...c, synced: true }});
  const timestamp = now();

  let toMarkDeleted = [];
  if (payload.toMarkDeleted.length > 0) {
    const deleteHash = newDeleteHash();
    toMarkDeleted = payload.toMarkDeleted.map((c, i) => ({ ...c, updatedAt: `${timestamp}:${i}:${deleteHash}` }));
  }

  try {
    await db.transaction('rw', db.cards, async () => {
        db.cards.bulkPut(newData.concat(toMarkSynced).concat(toMarkDeleted));
        db.cards.bulkDelete(payload.toRemove);
        markClean();
    });

    if (payload.toAdd.length > 0 || toMarkDeleted.length > 0) {
      if (payload.toAdd.length == 1 && payload.toAdd[0].content == "") {
        // Don't add new empty cards to history.
        return;
      }

      // Every version row this document has, deletions included: what a
      // snapshot holds is the *card set*, and which row is a card is a fact
      // about the whole log, not about one row. The `[treeId+deleted]` index
      // cannot answer it -- filtering per row (`{treeId, deleted: 0}`, which
      // this did) hides a deleted card's newest row behind its own stale
      // pre-deletion row, so the snapshot kept a card the document had lost
      // and restoring it brought the card back (`doc.js` hands Elm every
      // snapshot row as `deleted: 0`). Cost: one sort of the document's rows
      // per content save, over a log fast-forward keeps near one row per card.
      const rows = await db.cards.where({ treeId: treeId }).toArray();

      // Dedupe first, then drop the deleted -- the other order resurrects a
      // deleted card from one of its older rows (ADR-0005 §1, and
      // `newestVisible` in `Doc/Data.elm`).
      const cards = newestVersionPerId(rows).filter((c) => !c.deleted);

      // The snapshot is stamped with the moment it was taken: the newest row
      // in the log, which for a save that deletes is the deletion row itself.
      // Reading it off the snapshot's own rows instead would stamp a
      // post-deletion snapshot with an older timestamp and, `tree_snapshots`
      // being keyed by that id, overwrite the history entry that still had the
      // card.
      const lastUpdatedTime = maxStamp(rows.map((c) => c.updatedAt)).split(':')[0];
      const snapshotId = `${lastUpdatedTime}:${treeId}`;
      const snapshotData = cards.map((c) => ({ ...c, snapshot: snapshotId, delta: 0}));
      const snapshot = { snapshot: snapshotId, treeId: treeId, data: snapshotData, local: true, ts: Number(lastUpdatedTime)};
      await db.tree_snapshots.put(snapshot);
    }
    // An import's two port messages are unordered, so this can run before
    // `SaveCardBasedTree` has added the row. Dexie's `update` on a key that is
    // not there writes nothing, and there is nothing to write: the row that
    // message adds carries its own `updatedAt` and is unsynced from birth.
    await db.trees.update(treeId, {updatedAt: timestamp, synced: false});
  } catch (e) {
    onError("Error saving data!" + e);
  }
}

module.exports = {
  applyCardBasedSave: applyCardBasedSave,
};
