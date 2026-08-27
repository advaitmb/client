/**
 * Document-level writes the port layer performs (ADR-0001 seam 4).
 *
 * The `trees` table holds a document's name, its location and its `deletedAt`.
 * Cards travel as deltas the Elm core pushes; these rows travel as the `trees`
 * message `metadata.js` sends, and every write here stamps the row
 * `synced: false` so that it does.
 *
 * Extracted from `doc.js` for the reason `save.js` and `session.js` were:
 * `doc.js` boots the app at module load, so nothing in it can be imported by a
 * test.
 */

/**
 * Rename a document, once.
 *
 * Committing a title sends `RenameDocument` and then blurs the title field, and
 * the blur commits it a second time — `Page.App.TitleEdited` compares the typed
 * name against the *stored* one, which does not change until this write has
 * been round-tripped through Dexie's liveQuery, so the guard there does not
 * catch it. `doc.js` used to hold a module-level `renaming` boolean and drop
 * whichever message arrived while the other was in flight (CODE_REVIEW.md S5).
 * That is a timing window: what it dropped depended on how fast IndexedDB was,
 * and a genuinely *different* second name — typed and committed while the first
 * write was still going — was dropped just the same.
 *
 * So the duplicate is recognized by what it is rather than by when it arrives:
 * a name the row already has is not written again. Not even its timestamp,
 * because bumping that marks the row unsynced and pushes a no-op rename.
 *
 * The read and the write share one transaction, so two messages in flight
 * cannot both read the old name: IndexedDB serializes `readwrite` transactions
 * over the same store, which is why this is a transaction and not a plain
 * `get` followed by an `update`.
 *
 * @param {Object}   deps
 * @param {Object}   deps.db      the Dexie database (`trees`, `transaction`).
 * @param {string}   deps.treeId  the document to rename.
 * @param {string}   deps.name    the name Elm committed.
 * @param {Function} deps.now     wall-clock ms for the row's `updatedAt`.
 * @returns {Promise<boolean>} whether anything was written.
 */
async function renameDocument({ db, treeId, name, now }) {
  return db.transaction('rw', db.trees, async () => {
    const treeDoc = await db.trees.get(treeId);

    // No row: the document is not this client's to rename (an unopened import,
    // a document removed by a collaborator). Dexie's `update` would write
    // nothing anyway; this says so instead of relying on that.
    if (!treeDoc || treeDoc.name === name) {
      return false;
    }

    await db.trees.update(treeId, { name: name, updatedAt: now(), synced: false });
    return true;
  });
}

module.exports = {
  renameDocument: renameDocument,
};
