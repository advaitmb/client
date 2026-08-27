/**
 * The per-document settings store, reached through the build's `Container`
 * alias (esbuild.mjs).
 *
 * The alias, and this file's name, are what is left of an Electron/web split:
 * there were two containers, and the build chose one. Everything else the web
 * one exported was PouchDB- or Electron-era and had no caller left --
 * `userStore` (a PouchDB `settings` document; user settings ride in the session
 * blob now, see src/shared/session.js), `getInitialDocState` (an Electron
 * window's `dbPath`/`lastSavedToFile` state), `showMessageBox` (Electron's
 * dialog, aliased to `alert`), and seven `justLog` no-ops standing in for
 * main-process IPC and the file exports. Removed by ticket 22, along with the
 * lodash import none of them used.
 */

var localStoreId;
var treeId;

/**
 * The per-document settings blob (theme, last actives), or an empty one.
 *
 * Both accessors below used to parse localStorage inline, so a corrupted value
 * threw in each of them (CODE_REVIEW.md S8). There is nothing to recover here
 * (these are conveniences, the document itself is in Dexie), so anything
 * unusable reads as "no settings yet" and the next `set` replaces it.
 *
 * There was a third accessor, `get(key, fallback)`, which additionally indexed
 * the parse result before checking it -- so a `get` before anything had ever
 * been written for this document threw on `null`. It was the S8 bug and it had
 * no caller: `load` hands the whole blob to Elm (`loadedCards.localStore`),
 * which decodes the keys it wants, and nothing on this side ever asks for one.
 * Removed by ticket 22.
 */
const readLocalStore = () => {
  try {
    const parsed = JSON.parse(localStorage.getItem(localStoreId));
    if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed;
    }
  } catch (err) {
    console.error("localStore: ignoring an unreadable store for", localStoreId, err);
  }
  return {};
};

const localStore = {
  db: (tree_id) => {
    treeId = tree_id;
    localStoreId = `gingko-local-store/${tree_id}/settings`;
  },
  isReady: () => {
    return (typeof treeId != "undefined");
  },
  load: () => {
    return readLocalStore();
  },
  set: (key, value) => {
    let store = readLocalStore();
    store[key] = value;
    try {
      localStorage.setItem(localStoreId, JSON.stringify(store));
    } catch (err) {
      console.error("localStore: could not store", key, err);
    }
  },
};

export { localStore };
