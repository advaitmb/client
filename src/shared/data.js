/*
 * Self-host stub — the legacy CouchDB/PouchDB document layer is removed.
 *
 * Upstream this file is a ~400-line git-style store (load / newSave / pull /
 * push / sync / commit / conflict resolution) backed by PouchDB, used only by
 * documents whose `location` is "couchdb". Everything written in this install
 * is `location: "cardbased"`: it lives in Dexie locally and syncs over the
 * websocket into SQLite, and never touches any of this.
 *
 * Keeping it was not merely dead weight. Documents created through the bulk
 * text / JSON / OPML importers and through Duplicate Document defaulted to
 * `location: "couchdb"`, so their content went into browser-local PouchDB and
 * *nowhere else* — invisible to the server, to `gingko-export`, and to the
 * hourly backup. A verified case: an imported document listed as "0 cards" and
 * backed up as an empty file. Clearing site data would have destroyed it
 * silently.
 *
 * These functions now throw, so those paths fail loudly instead. Callers in
 * doc.js surface the message in the UI. The original is kept at
 * ~/gingko/patches/data.js.upstream-backup.
 */

const MSG =
  "This document type (legacy CouchDB format) is no longer supported on this " +
  "self-hosted install. It would have been saved only inside this browser, " +
  "never synced to the server and never backed up.";

function unsupported() {
  throw new Error(MSG);
}

const getDocumentList = unsupported;
const load = unsupported;
const loadMetadata = unsupported;
const newSave = unsupported;
const renameDocument = unsupported;
const pull = unsupported;
const sync = unsupported;

export { getDocumentList, load, loadMetadata, newSave, renameDocument, pull, sync, MSG };
