const _ = require("lodash");

var userStoreLocal;
var userStoreRemote;
const userSettingsId = "settings";
const userStore = {
  db: function(localDb, remoteDb) {
    userStoreLocal = localDb;
    userStoreRemote = remoteDb;
  },
  load: async function() {
    return userStoreLocal.get(userSettingsId);
  },
  set: function(key, val) {
    userStoreLocal.get(userSettingsId)
      .then(doc => {
        doc[key] = val;
        userStoreLocal.put(doc);
      })
      .catch(err => {
        if (err.status == 404) {
          let newSettings = {_id : userSettingsId};
          newSettings[key] = val;
          userStoreLocal.put(newSettings);
        }
      })
  }
};

var localStoreId;
var treeId;

/**
 * The per-document settings blob (theme, last actives), or an empty one.
 *
 * Every one of the three accessors below used to parse localStorage inline, and
 * `get` then indexed the result before checking it — so a `get` before anything
 * had ever been written for this document threw on `null` (CODE_REVIEW.md S8),
 * and a corrupted value threw in all three. There is nothing to recover here
 * (these are conveniences, the document itself is in Dexie), so anything
 * unusable reads as "no settings yet" and the next `set` replaces it.
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
  get: (key, fallback) => {
    let store = readLocalStore();
    if (typeof store[key] !== "undefined") {
      return store[key];
    } else {
      return fallback;
    }
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

const getInitialDocState = () => {
  const url = new URL(window.location);
  const treeName = url.searchParams.get("treeId") || "defaultTree";
  var docState = {
    dbPath: [treeName],
    lastSavedToFile: 0,
    changed: false,
    jsonImportData: false,
  };
  return docState;
};

const showMessageBox = (...args) => {
  if (args[0] && args[0].buttons && args[0].buttons.length == 1) {
    alert(`${args[0].title}\n${args[0].message}\n${args[0].detail}`);
  } else {
    console.log("showMessageBox", args);
  }
};

const justLog = (...args) => {
  //console.debug("container", ...args);
};

export {
  justLog as sendTo,
  justLog as msgWas,
  justLog as answerMain,
  getInitialDocState,
  localStore,
  userStore,
  justLog as openExternal,
  showMessageBox,
  justLog as exportDocx,
  justLog as exportJson,
  justLog as exportTxt,
};
