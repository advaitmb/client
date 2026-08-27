// @format
//import '../static/style.css'

import hlc from '@tpp/hybrid-logical-clock'
import uuid from '@tpp/simple-uuid'
// Self-host: Sentry, LogRocket and PouchDB removed. LogRocket contacted
// cdn.lr-ingest.io on *import*, so gating its .init() never stopped the
// request. PouchDB only backed legacy CouchDB documents.
import { ImmortalStorage, IndexedDbStore, LocalStorageStore, SessionStorageStore } from 'immortal-db'
// Stamp ordering lives in its own module so it can be unit-tested without
// Dexie or a WebSocket (ADR-0001 seam 2). Stamps are never string-ordered.
import { computeCheckpoint, maxStamp, newestVersionPerId } from './stamps.js'


const _ = require("lodash");
const Mousetrap = require("mousetrap");
const screenfull = require("screenfull");
const container = require("Container");
const platform = require("platform");
const config = require("../../config.js");
const PersistentWebSocket = require("pws");

const Dexie = require("dexie").default;
let ImmortalDB;
async function initImmortalDB() {
  const immortalStores = [await new IndexedDbStore(), await new LocalStorageStore(), await new SessionStorageStore()];
  ImmortalDB = new ImmortalStorage(immortalStores);
}
initImmortalDB();

const dexie = new Dexie("db");
dexie.version(4).stores({
  trees: "id,updatedAt",
  cards: "updatedAt, treeId, [treeId+deleted]",
  tree_snapshots: "snapshot, treeId"
});

const helpers = require("./doc-helpers");
const { SESSION_STORAGE_KEY, logoutUser, mergeUserIntoSession } = require("./session");
// The local half of a save, extracted for the same reason as session.js:
// nothing in this file is importable by a test (ADR-0001 seam 4).
const { applyCardBasedSave } = require("./save");
// Same reason: which drag is in progress, and everything that follows from it.
const { installDragHandlers } = require("./drag");
//import { Elm } from "../elm/Main";

/* === Global Variables === */

let renaming = false;
window.elmMessages = [];

let remoteDB;
let db;
let gingko;
let TREE_ID;
const CLIENT_ID = uuid(12);
let COLLAB_STATE;
let DATA_TYPE;
const CARD_DATA = Symbol.for("cardbased");
let userDbName;
let email = null;
let ws;
let wsQueue = [];
let PULL_LOCK = false;
let pushErrorCount = 0;
let loadingDocs = false;
let viewportWidth = document.documentElement.clientWidth;
let viewportHeight = document.documentElement.clientHeight;

// Debounced so a resize drag doesn't thrash layout reads.
const updateViewportSize = _.debounce(() => {
  viewportWidth = document.documentElement.clientWidth;
  viewportHeight = document.documentElement.clientHeight;
}, 150);
let sidebarWidth;
let savedObjectIds = new Set();
let treeListSubscription = null;
let cardDataSubscription = null;
let historyDataSubscription = null;
let wsErrorCount = 0;
const localStore = container.localStore;

// Shared mutable state passed to doc-helpers. This MUST be a single long-lived
// object: it used to be rebuilt from local variables on every message from Elm,
// so doc-helpers' writes into it were silently discarded.
const params = {
  localStore,
  lastColumnScrolled: null,
  lastActivesScrolled: null,
  ticking: false,
  DIRTY: false,
};
function getDataType() {
  return DATA_TYPE;
}

/* === Initializing App === */

initElmAndPorts();

async function initElmAndPorts() {
  let flags = getFlags();

  // Self-host: there is no login screen. The client keeps its session in
  // localStorage and its document list in Dexie, so a fresh browser has
  // neither. Adopt the single local account and seed the document cache before
  // Elm starts.
  //
  // Seeding matters because `gingko <project>` opens /<treeId> directly: with an
  // empty cache the router resolves the id against nothing and renders
  // "document not found" before the websocket tree sync arrives.
  let treeCount = 0;
  try { treeCount = await dexie.trees.count(); } catch (e) { console.error(e); }

  if (!flags.email || treeCount === 0) {
    try {
      const res = await fetch("/me");
      if (res.ok) {
        const me = await res.json();
        setSessionData(mergeUserIntoSession(getSessionData(), me), "AutoLogin");
        if (Array.isArray(me.documents) && me.documents.length > 0) {
          await dexie.trees.bulkPut(me.documents.map((t) => ({ ...t, synced: true })));
        }
        flags = getFlags();
      } else {
        console.error("auto-login: /me returned", res.status);
      }
    } catch (e) {
      console.error("auto-login failed", e);
    }
  }

  if (flags.email) {
    await setUserDbs(flags.email);
  }

  gingko = Elm.Main.init({
    node: document.getElementById("elm"),
    flags: flags,
  });

  // All messages from Elm
  gingko.ports.infoForOutside.subscribe(function (elmdata) {
    fromElm(elmdata.tag, elmdata.data);
  });


  initEventListeners();
}


function getFlags() {
  let sessionMaybe = getSessionData();
  let sessionData = sessionMaybe == null ? {} : sessionMaybe;
  console.log("sessionData found", JSON.stringify(sessionData));
  if (sessionData.email) {
    email = sessionData.email;
    sessionData.sidebarOpen = (sessionData.hasOwnProperty('sidebarOpen')) ?  sessionData.sidebarOpen : false;
    sidebarWidth = sessionData.sidebarOpen ? 215 : 40;
  }

  // Dynamic and global session info
  let timestamp = Date.now();
  sessionData.seed = timestamp;
  sessionData.isMac = platform.os.family === 'OS X';
  sessionData.currentTime = timestamp;
  sessionData.fromLegacy = document.referrer.startsWith(config.LEGACY_URL);
  return sessionData;
}


async function setUserDbs(eml) {
  email = eml;

  userDbName = `userdb-${helpers.toHex(email)}`;
  // remoteDB was the CouchDB replica for legacy documents; there is no CouchDB.
  remoteDB = null;
  db = null;  // local PouchDB replica: legacy documents only
  initWebSocket();

  // Sync document list with server

  let firstLoad = true;

  treeListSubscription = Dexie.liveQuery(() => dexie.trees.toArray()).subscribe((trees) => {
    const docMetadatas = trees.filter(t => t.deletedAt == null).map(treeDocToMetadata);
    if (!loadingDocs && !firstLoad) {
      toElm(docMetadatas, "documentListChanged");
    }

    const unsyncedTrees = trees.filter(t => !t.synced).map(t => _.omit(t, ['synced', 'collaborators']));
    if (unsyncedTrees.length > 0) {
      wsSend('trees', unsyncedTrees, false);
    }
    firstLoad = false;
  });

}


/**
 * The counterpart of setUserDbs: stop syncing as the user who just logged
 * out. pws reconnects on its own until it is closed explicitly, and the
 * liveQueries would keep feeding a document that is no longer on screen.
 * Local data itself is untouched (see session.js).
 */
function stopSyncing() {
  if (ws) {
    ws.close();
    ws = null;
  }
  wsQueue = [];
  if (treeListSubscription != null) { treeListSubscription.unsubscribe(); treeListSubscription = null; }
  if (cardDataSubscription != null) { cardDataSubscription.unsubscribe(); cardDataSubscription = null; }
  if (historyDataSubscription != null) { historyDataSubscription.unsubscribe(); historyDataSubscription = null; }
  TREE_ID = null;
  email = null;
}


function initWebSocket () {
  const wsUrl = window.location.origin.replace('http', 'ws')+'/ws'
  ws = new PersistentWebSocket(wsUrl, {pingTimeout: 30000 + 2000})

  let interval;
  ws.onopen = () => {
    // Send each item from wsQueue and clear it
    wsQueue.forEach(([msgTag, msgData]) => {
      wsSend(msgTag, msgData, false)
    })
    wsQueue = [];

    if (TREE_ID) {
      wsSend('rt:join', { tr: TREE_ID, uid: CLIENT_ID, m: COLLAB_STATE || null }, false);
    }

    interval = setInterval(() => ws.send('ping'), 30000)
    setTimeout(() => toElm(null, 'appMsgs', 'SocketConnected') , 1000)
  }

  ws.onmessage = async (e) => {
    if (e.data == 'pong') {
      return
    }

    const data = JSON.parse(e.data)
    try {
      switch (data.t) {
        case 'user':
          console.log('user', JSON.stringify(data.d))
          let currentSessionData = getSessionData()
          if (currentSessionData && currentSessionData.email === data.d.id) {
            // Merge properties
            let newSessionData = Object.assign({}, currentSessionData, _.omit(data.d, ['id', 'createdAt']))
            if (!_.isEqual(currentSessionData, newSessionData)) {
              setSessionData(newSessionData, 'user ws msg')
              setTimeout(() => gingko.ports.userSettingsChange.send(newSessionData), 0)
            }
          }
          break

        case 'cards':
          if (data.d.length > 0) {
            await dexie.cards.bulkPut(data.d.map(c => ({ ...c, synced: true })))
          }
          break

        case 'cardsConflict':
          if (data.d.length > 0) {
            await dexie.cards.bulkPut(data.d.map(c => ({ ...c, synced: true })))

            // send encrypted unsynced local cards to Sentry
            const unsyncedCards = await dexie.cards.where('treeId').equals(TREE_ID).and(c => !c.synced).toArray();
            console.warn('cardsConflict: cards conflict ' + TREE_ID, { unsyncedCards, error: data.e })
          } else {
            console.warn('cardsConflict: no cards ' + TREE_ID, { error: data.e })
            const numberUnsynced = await dexie.cards.where('treeId').equals(TREE_ID).and(c => !c.synced).count();
            const msg = `Error syncing ${numberUnsynced} change${numberUnsynced == 1 ? "" : "s"}. Try refreshing the page.\n\nIf this error persists, please contact support!`;
            toElm(msg, 'appMsgs', 'ErrorAlert');
          }
          break

        case 'pushOk':
          pushErrorCount = 0;
          hlc.recv(maxStamp(data.d))
          toElm(data, 'appMsgs', 'PushOk')
          break

        case 'pushError':
          pushErrorCount++;
          if (pushErrorCount >= 4) {
            let numberUnsynced = await dexie.cards.where('treeId').equals(TREE_ID).and(c => !c.synced).count();
            const msg = `Error syncing ${numberUnsynced} change${numberUnsynced == 1 ? "" : "s"}. Try refreshing the page.\n\nIf this error persists, please contact support!`;
            toElm(msg, 'appMsgs', 'ErrorAlert');
          }
          console.log(pushErrorCount)
          toElm(data, 'appMsgs', 'PushError')
          break

        case 'doPull':
          // Server says this tree has changes
          if (data.d === TREE_ID) {
            let cards = await dexie.cards.where('treeId').equals(TREE_ID).toArray()
            pull(TREE_ID, computeCheckpoint(cards))
          }
          break


        case 'trees':
          await dexie.trees.bulkPut(data.d.map(t => ({ ...t, synced: true })))
          break

        case 'treesOk':
          await dexie.trees.where('updatedAt').belowOrEqual(data.d).modify({ synced: true })
          break

        case 'historyMeta': {
          const { tr, d } = data
          const snapshotData = d.map(hmd => ({ snapshot: hmd.id, treeId: tr, data: null }))
          try {
            await dexie.tree_snapshots.bulkAdd(snapshotData)
          } catch (e) {
            const errorNames = e.failures.map(f => f.name)
            if (errorNames.every(n => n === 'ConstraintError')) {
              // Ignore
            } else {
              throw e
            }
          }
          break
        }

        case 'history': {
          const { tr, d } = data
          const snapshotData = d.map(hd => ({
            snapshot: hd.id,
            treeId: tr,
            data: hd.d.map(d => ({ ...d, synced: true }))
          }))
          await dexie.tree_snapshots.bulkPut(snapshotData)
          break
        }

        case 'rt':
          if (Array.isArray(data.d.m) && data.d.m[0] == "d") {
            toElm(data.d.uid, 'docMsgs', 'CollaboratorDisconnected')
          } else {
            toElm(data.d, 'docMsgs', 'RecvCollabState');
          }
          break;

        case 'rt:users':
          toElm(data.d, 'docMsgs', 'RecvCollabUsers');
          break;

        case 'removedFrom':
          await dexie.trees.delete(data.d);
          if (data.d === TREE_ID) {
            location.assign('/');
          }
          break;
      }
    } catch (e) {
      console.log(e)
    }
  }

  ws.onerror = (e) => {
    console.error('websocket error', e);
    if (wsErrorCount == 3 || wsErrorCount == 10 || wsErrorCount >= 20) {
      let msg = `Error with the current session.\nTry refreshing.\n\nIf it persists, export a JSON backup of recent work, and log out and back in.`
      toElm(msg, 'appMsgs', 'ErrorAlert');
    }
    wsErrorCount++;
    console.error('ws error', e);
  }

  ws.onclose = (e) => {
    // Clear list of collaborators
    toElm([], 'docMsgs', 'RecvCollabUsers');

    clearInterval(interval)
  }
}


function initEventListeners () {
  window.checkboxClicked = (cardId, number) => {
    toElm([cardId, number], 'docMsgs', 'CheckboxClicked')
  }

  // Prevent closing if unsaved changes exist.
  window.addEventListener('beforeunload', (event) => {
    if (params.DIRTY) {
      event.preventDefault()
      event.returnValue = ''
    }
  })

  // Fullscreen change event
  // This is so that we can use "Esc" once to leave fullscreen mode.
  if (screenfull.isEnabled) {
    screenfull.on('change', () => {
      toElm(screenfull.isFullscreen, 'docMsgs', 'FullscreenChanged')
    })
  }

  window.addEventListener('beforeprint', () => {
    toElm(null, 'docMsgs', 'WillPrint')
  })
}


/* === Elm / JS Interop === */

function toElm(data, portName, tagName) {
  if (!gingko) { return; }
  let portExists = gingko.ports.hasOwnProperty(portName);
  let tagGiven = typeof tagName == "string";

  if (portExists) {
    var dataToSend;

    if (tagGiven) {
      dataToSend = { tag: tagName, data: data };
    } else {
      dataToSend = data;
    }
    gingko.ports[portName].send(dataToSend);
  } else {
    console.error("Unknown port", portName, data);
  }
}

const fromElm = (msg, elmData) => {
  window.elmMessages.push({tag: msg, data: elmData});
  window.elmMessages = window.elmMessages.slice(-10);

  let casesWeb = {
    // === SPA ===

    StoreUser: async () => {
      setSessionData(elmData, "StoreUser");
      await setUserDbs(elmData.email);
      const timestamp = Date.now();
      elmData.seed = timestamp;
      elmData.currentTime = timestamp;
      setTimeout(() => gingko.ports.userLoggedInMsg.send(null), 0);
    },

    LogoutUser: async () => {
      await logoutUser({
        teardown: stopSyncing,
        // Hand back to Elm rather than reloading /login: Main.elm's
        // userLoggedOut subscription swaps the page in place, while a reload
        // would run boot auto-login again (getFlags finds no email, so /me is
        // asked) -- and any server session that outlived the POST above would
        // silently log the user back in.
        onLoggedOut: () => gingko.ports.userLoggedOutMsg.send(null),
      });
    },


    // === Dialogs, Menus, Window State ===

    Alert: () => {
      alert(elmData);
    },

    SetDirty: () => {
      params.DIRTY = elmData;
    },

    DragDone: () => {
      drag.dragDone();
    },

    // === Database ===

    InitDocument: async () => {
      TREE_ID = elmData;

      const now = Date.now();
      const treeDoc = {...treeDocDefaults, id: TREE_ID, location: "cardbased", owner: email, createdAt: now, updatedAt: now};
      const cardDoc = {...cardDefaults, id: my_uuid(24), treeId: TREE_ID, updatedAt: hlc.nxt()};

      await dexie.trees.add(treeDoc);
      await dexie.cards.add(cardDoc);

      // Set localStore db
      localStore.db(elmData);

      try {
        loadCardBasedDocument(TREE_ID);
      } catch (e) {
        console.log(e);
      }
    },

    LoadDocument : async () => {
      TREE_ID = elmData;

      wsSend('rt:join', { tr: TREE_ID, uid: CLIENT_ID, m: COLLAB_STATE || null}, true);
      // Load title
      const treeDoc = await dexie.trees.get(elmData);
      if (treeDoc) {
        toElm(treeDocToMetadata(treeDoc), "appMsgs", "MetadataUpdate")
      } else {
        toElm(TREE_ID, "appMsgs", "NotFound")
        return;
      }

      try {
        if (treeDoc.location === "cardbased") {
          loadCardBasedDocument(elmData);
        } else {
          console.error("Unknown document location:", treeDoc.location);
          toElm(TREE_ID, "appMsgs", "NotFound");
        }
      } catch (e) {
        console.log(e);
      }
    },

    GetDocumentList: () => {
      loadDocListAndSend();
    },

    RequestDelete: async () => {
      if (confirm(`Are you sure you want to delete the document '${elmData[1]}'?`)) {
        await dexie.trees.update(elmData[0], {deletedAt: Date.now(), synced: false});
      }
    },

    RenameDocument: async () => {
      if (!renaming) { // Hack to prevent double rename attempt due to Browser.Dom.blur
        renaming = true;
        await dexie.trees.update(TREE_ID, {name: elmData, updatedAt: Date.now(), synced: false});
        renaming = false;
      }
    },

    PushDeltas : () => {
      if (elmData.dlts.length > 0) {
        wsSend('push', elmData, false);
      }
    },

    SaveCardBased : async () => {
      await applyCardBasedSave(elmData, {
        db: dexie,
        nextStamp: () => hlc.nxt(),
        newDeleteHash: uuid,
        now: Date.now,
        markClean: () => { params.DIRTY = false; },
        onError: (message) => alert(message),
      });
    },

    // The other half of an import: the row that makes the imported cards a
    // document. It does NOT become the current document here -- `TREE_ID` is
    // the document on screen, and this one is not on screen until Elm has
    // navigated to it and sent `LoadDocument`. Setting it here was how the
    // import's save found its document on the orders where this message
    // happened to land first (CODE_REVIEW.md D5); the save names its own
    // document now, and claiming the global early only pointed the socket
    // handlers at a document with no subscriptions while the one still on
    // screen kept receiving rows.
    SaveCardBasedTree: async () => {
      const now = Date.now();
      const [importedTreeId, treeName] = elmData;
      const treeDoc = {...treeDocDefaults, name: treeName, id: importedTreeId, location: "cardbased", owner: email, createdAt: now, updatedAt: now};
      await dexie.trees.add(treeDoc);
      toElm(importedTreeId, "importComplete")
    },

    SaveCardBasedMigration : async () => {
      await dexie.trees.update(TREE_ID, {location: "cardbased", synced: false});
      await dexie.cards.bulkPut(elmData);
      loadCardBasedDocument(TREE_ID);
    },



    // === Collaboration ===


    SendCollabState: () => {
      COLLAB_STATE = elmData;
      wsSend('rt'
        , {uid: CLIENT_ID, tr: TREE_ID, m: elmData}, true);
    },


    // === DOM ===

    ScrollFullscreenCards: () => {
      helpers.scrollFullscreen(elmData);
    },

    // Dead on both sides: the elm-dnd view attributes that sent this are never
    // rendered (CODE_REVIEW.md §6, removed by ticket 22). A card drag is
    // <gw-tree>'s to report now -- see drag.js -- so this no longer claims one
    // is in progress.
    DragStart: () => {
      let cardElement = elmData.target.parentElement;
      let cardId = cardElement.id.replace(/^card-/, "");
      elmData.dataTransfer.setDragImage(cardElement, 0 , 0);
      elmData.dataTransfer.setData("text", "");
      toElm(cardId, "docMsgs", "DragStarted");
    },

    CopyToClipboard: () => {
      navigator.clipboard.writeText(elmData.content);

      let addFlashClass = function () {
        document.querySelectorAll(elmData.element).forEach((e) => {e.classList.add("flash")});
      };

      let removeFlashClass = function () {
        document.querySelectorAll(elmData.element).forEach((e) => {e.classList.remove("flash")});
      };

      addFlashClass();
      setTimeout(removeFlashClass, 200);
    },

    SelectAll: () => {
      document.getElementById(elmData).select();
    },

    SetField: () => {
      let id = elmData[0];
      let field = elmData[1];
      window.requestAnimationFrame(() => {
        let tarea = document.getElementById("card-edit-" + id);
        tarea.value = field;
      })
    },

    SetFullscreen: () => {
      if(screenfull.isEnabled) {
        if(elmData) {
          screenfull.request().catch((e)=> console.log(e));
        } else {
          screenfull.exit();
        }
      }
    },


    // === UI ===
    UpdateCommits: () => {},

    HistorySlider: () => {
      const firstOpen = elmData[0];
      const delta = elmData[1];
      if (firstOpen) {
        wsSend('pullHistory', TREE_ID, false);
      }

      const timeout = document.getElementById('history-slider') ? 0 : 200;

      setTimeout(() => {
        let slider = document.getElementById('history-slider')
        if (slider != null) {
          slider.stepUp(delta);
          slider.dispatchEvent(new Event('input'));
        }
      }, timeout)
    },

    SaveUserSetting: () => {
      let key = elmData[0];
      let value = elmData[1];
      let currSessionData = getSessionData();
      currSessionData[key] = value;
      setSessionData(currSessionData, "SaveUserSetting");
    },

    SetSidebarState: () => {
      let currSessionData = getSessionData();
      currSessionData.sidebarOpen = elmData;
      setSessionData(currSessionData, "SetSidebarState");
      window.requestAnimationFrame(()=>{
        sidebarWidth = document.getElementById('sidebar').clientWidth;
      });
    },

    SaveThemeSetting: () => {
      localStore.set("theme", elmData);
    },

    RequestFullscreen: () => {
      if (!document.fullscreenElement) {
        document.body.requestFullscreen();
      } else {
        document.exitFullscreen();
      }
    },

    Print: () => {
      window.print();
    },

    // === Misc ===


    EmptyMessageShown: () => {},

    InitBeamer: () => {

    },

    SocketSend: () => {},
  };


  const cases = Object.assign(helpers.casesShared(elmData, params), casesWeb)

  try {
    cases[msg]();
  } catch (err) {
    console.error("Unexpected message from Elm : ", msg, elmData, err);
  }
};


function wsSend(msgTag, msgData, queueIfNotReady) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify({t: msgTag, d: msgData}));
  } else if (queueIfNotReady) {
    wsQueue.push([msgTag, msgData])
  }
}


/* === Database === */

const treeDocDefaults = {name: null, location: "cardbased", inviteUrl: null, collaborators: [], deletedAt: null};
const cardDefaults = {parentId: null, deleted: 0, content: "", position: 0, synced: false};

function treeDocToMetadata(tree) {
  return {docId: tree.id, name: tree.name, collaborators: tree.collaborators, createdAt: tree.createdAt, updatedAt: tree.updatedAt, _rev: null}
}

async function loadCardBasedDocument (treeId) {
  DATA_TYPE = CARD_DATA;
  if (cardDataSubscription != null) { cardDataSubscription.unsubscribe(); }
  if (historyDataSubscription != null) { historyDataSubscription.unsubscribe(); }

  // Load document-specific settings.
  localStore.db(treeId);
  let store = localStore.load();

  // Load local document data.
  let loadedCards = await dexie.cards.where("treeId").equals(treeId).toArray();
  const chk = computeCheckpoint(loadedCards);
  if (loadedCards.length > 0) {
    loadedCards.localStore = store;
    toElm(loadedCards, "appMsgs", "CardDataReceived");
  }

  let firstLoad = true;

  // Setup Dexie liveQuery for local document data.
  cardDataSubscription = Dexie.liveQuery(() => dexie.cards.where("treeId").equals(treeId).toArray()).subscribe((cards) => {
    //console.log("LiveQuery update", cards);
    if (cards.length > 0) {
      // Preserve textarea field and cursor position.
      let currActive = document.activeElement;
      let currActiveId = currActive ? currActive.id : null;
      let currActivePos = currActive ? currActive.selectionStart : null;
      let currActiveContent = currActive ? currActive.value : null;

      toElm(cards, "appMsgs", "CardDataReceived");

      if (currActiveId && currActiveId.startsWith("card-edit-")) {
        // Restore textarea field and cursor position.
        requestAnimationFrame(() => {
          let newActive = document.getElementById(currActiveId);
          if (newActive) {
            newActive.focus();
            newActive.value = currActiveContent;
            newActive.selectionStart = currActivePos;
            newActive.selectionEnd = currActivePos;
          }
        });
      }


      saveBackupToImmortalDB(treeId, cards);
      if (firstLoad) {
        firstLoad = false;
        const firstCard = cards.filter(c => c.parentId === null)[0];
        setTimeout(() => {toElm(firstCard.id, "docMsgs", "InitialActivation")} , 20);
      }
    }
  });

  // Setup Dexie liveQuery for local history data, after initial pull.
  historyDataSubscription = Dexie.liveQuery(() => dexie.tree_snapshots.where("treeId").equals(treeId).toArray()).subscribe((history) => {
    if (history.length > 0) {
      const historyWithTs = history.map(h => ({
        ...h,
        ts: Number(h.snapshot.split(':')[0]),
        data: h.data !== null ? h.data.map(d => ({ ...d, deleted: 0 })) : h.data
      }));
      toElm(historyWithTs, "appMsgs", "HistoryDataReceived");
    }
  });

  // Pull data from remote
  pull(treeId, chk);
}

function pull(treeId, chk) {
  wsSend("pull", [treeId, chk], true);
  setTimeout(() => {
    wsSend('pullHistoryMeta', treeId, true);
  }, 500)
}

function saveBackupToImmortalDB (treeId, cards) {
  const snapshot = newestVersionPerId(cards);
  const trees = treeHelper(snapshot, null);
  const treeString = trees.map(treeToGkw).join('\n');
  if (ImmortalDB) {
    ImmortalDB.set('backup-snapshot:' + treeId, treeString);
  }
}

function treeToGkw (tree) {
  return "<gingko-card id=\""
    + tree.id
    + "\">\n\n"
    + tree.content
    + "\n\n"
    + tree.children.map(treeToGkw).join("\n\n")
    + "</gingko-card>";
}

function treeToHtml (tree) {
  return "<section>\n"
    + tree.content
    + "\n"
    + tree.children.map(treeToHtml).join("\n")
    + "</section>";
}

function treeHelper (cards, parentId) {
  let children = _.chain(cards).filter(c => c.parentId === parentId).sortBy('position').value();
  return children.map(c => {
    let children = treeHelper(cards, c.id);
    return {id: c.id, content: c.content, children}
  });
}

async function loadDocListAndSend() {
  loadingDocs = true;
  let docList = await dexie.trees.toArray().catch(e => {console.error(e); return []});
  toElm(docList.filter(d => d.deletedAt == null).map(treeDocToMetadata),  "documentListChanged");
  loadingDocs = false;
}


/* === Helper Functions === */

function my_uuid(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function getSessionData() {
  let sessionStringRaw = localStorage.getItem(SESSION_STORAGE_KEY);
  if (sessionStringRaw) {
    return JSON.parse(sessionStringRaw);
  } else {
    return null;
  }
}

function setSessionData(data, source) {
  console.log("Setting session data:",source, JSON.stringify(data))
  localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(data));
}


function pushSuccessHandler (info) {
  toElm(Date.parse(info.end_time), "appMsgs", "SavedRemotely")
}

/* === DOM Events and Handlers === */

// Both kinds of drag -- a card moved inside the tree, and text dragged in from
// outside the app -- live in their own module, for the reason session.js and
// save.js do: nothing in this file can be imported by a test (ADR-0001 seam
// 4). What it needs from here is the viewport doc.js measures on resize and
// the element the columns scroll inside.
const drag = installDragHandlers({
  root: document,
  toElm,
  viewport: () => ({ width: viewportWidth, height: viewportHeight, sidebarWidth }),
  scrollRoot: () => document.getElementById("document"),
});




window.onresize = () => {
  if (params.lastActivesScrolled) {
    debouncedScrollColumns(params.lastActivesScrolled);
  }
  if (params.lastColumnScrolled) {
    debouncedScrollHorizontal(params.lastColumnScrolled);
  }
  // This used to build a debounced function and throw it away, so the viewport
  // dimensions were never updated after the initial read -- drag auto-scroll
  // thresholds stayed measured against the original window size.
  updateViewportSize();
};

const debouncedScrollColumns = _.debounce(helpers.scrollColumns, 200);
const debouncedScrollHorizontal = _.debounce(helpers.scrollHorizontal, 200);


Mousetrap.bind(helpers.shortcuts, function (e, s) {
  switch (s) {
    case "enter":
      if (document.activeElement.nodeName === "TEXTAREA") {
        return;
      } else {
        toElm("enter","docMsgs", "Keyboard");
      }
      break;

    case "mod+c":
      let exportPreview = document.getElementById("export-preview");
      if (exportPreview !== null) {
        return;
      } else {
        toElm("mod+c","docMsgs", "Keyboard");
      }
      break;

    case "mod+v":
    case "mod+shift+v":
      if (document.activeElement.nodeName === "TEXTAREA") {
        return;
      }

      let elmTag = s === "mod+v" ? "Paste" : "PasteInto";

      navigator.clipboard.readText()
        .then(clipString => {
          try {
            let clipObj = JSON.parse(clipString);
            toElm(clipObj, "docMsgs", elmTag)
          } catch {
            toElm(clipString, "docMsgs", elmTag)
          }
        }).catch(err => {
          if (err.message.includes("denied")) {
            alert("Clipboard access denied. Click on the padlock icon in the address bar and allow clipboard access.")
          }
        });
      break;

    case "alt+0":
    case "alt+1":
    case "alt+2":
    case "alt+3":
    case "alt+4":
    case "alt+5":
    case "alt+6":
      if (document.activeElement.nodeName === "TEXTAREA") {
        let num = Number(s[s.length - 1]);
        let currentText = document.activeElement.value;
        let newText = currentText.replace(/^(#{0,6}) ?(.*)/, num === 0 ? '$2' : '#'.repeat(num) + ' $2');
        document.activeElement.value = newText;
        params.DIRTY = true;
        toElm(newText, "docMsgs", "FieldChanged");

        let cardElementId = document.activeElement.id.replace(/^card-edit/, "card");
        let card = document.getElementById(cardElementId);
        if (card !== null) {
          card.dataset.clonedContent = newText;
        }
      }
      break;

    default:
      toElm(s, "docMsgs", "Keyboard");
  }

  if (helpers.needOverride.includes(s)) {
    return false;
  }
});

Mousetrap.bind(["tab"], function () {
  document.execCommand("insertText", false, "  ");
  return false;
});

Mousetrap.bind(["shift+tab"], function () {
  return true;
});

/* === DOM manipulation === */

helpers.defineCustomTextarea(toElm, getDataType);

window.addEventListener("error", (err) => {
  console.log(err);
  if (
    err.message.match(/Cannot read properties of undefined \(reading 'childNodes'\)/)
    ||
    err.message.match(/Failed to execute 'removeChild' on 'Node'/)
  ) {
    alert("There may be an extension interfering with Gingko Writer.\n\nDisable your extensions and try again, or contact support");
    cleanBodyHelp();
  }
});

const cleanBodyHelp = () => {
  console.log("cleanBodyHelp")
  document.body
    .querySelectorAll(
      "[data-grammarly-shadow-root], [data-lastpass-root], [data-lastpass-icon-root]"
    )
    .forEach((el) => document.body.after(el));
};


/* === Sync with GitHub =====================================================
 * A writing session should never need a terminal. This calls POST /sync, which
 * runs ~/gingko/bin/gingko-sync (pull, export to LaTeX, commit, push) for
 * whichever project this document maps to.
 *
 * Mounted on <body> rather than inside #document-header: Elm owns that subtree
 * and its virtual DOM drops foreign children on re-render, so a button injected
 * there disappears mid-session. Instead it is fixed-positioned and measured
 * against #history-icon each tick, so it sits flush in the top bar, to the left
 * of the header icons, without ever colliding with them (or with the search
 * button in the bottom-right corner, where it used to live).
 * ======================================================================== */

const syncUI = (() => {
  let btn, status, wrap, lastCheckedId = null, busy = false;

  function build() {
    wrap = document.createElement("div");
    wrap.id = "gh-sync";
    wrap.style.cssText =
      "position:fixed;z-index:60;display:none;align-items:center;gap:8px;" +
      "font:12px/1 'Open Sans',-apple-system,sans-serif;";

    status = document.createElement("span");
    status.id = "gh-sync-status";
    status.style.cssText = "color:#666;white-space:nowrap;display:none;";

    btn = document.createElement("button");
    btn.id = "gh-sync-button";
    btn.type = "button";
    btn.textContent = "Sync with GitHub";
    btn.style.cssText =
      "cursor:pointer;border:1px solid #cfd6cf;border-radius:5px;padding:5px 11px;" +
      "font:600 12px/1 'Open Sans',-apple-system,sans-serif;color:#33691e;" +
      "background:#f1f7ef;white-space:nowrap;";
    btn.addEventListener("mouseenter", () => { if (!busy) btn.style.background = "#e4efe0"; });
    btn.addEventListener("mouseleave", () => { if (!busy) btn.style.background = "#f1f7ef"; });
    btn.addEventListener("click", run);

    wrap.appendChild(status);
    wrap.appendChild(btn);
    document.body.appendChild(wrap);
  }

  // Sit in the header bar, just left of the first header icon.
  function place() {
    const anchor =
      document.getElementById("history-icon") ||
      document.getElementById("doc-settings-icon") ||
      document.getElementById("export-icon");
    const header = document.getElementById("document-header");
    if (!anchor || !header) { wrap.style.display = "none"; return false; }
    const a = anchor.getBoundingClientRect();
    const h = header.getBoundingClientRect();
    if (a.width === 0 || h.height === 0) return false;
    wrap.style.right = Math.round(window.innerWidth - a.left + 10) + "px";
    wrap.style.top = Math.round(h.top + (h.height - 26) / 2) + "px";
    return true;
  }

  function say(text, colour) {
    status.textContent = text;
    status.style.color = colour || "#666";
    status.style.display = text ? "inline" : "none";
  }

  async function run() {
    if (busy || !TREE_ID) return;
    busy = true;
    btn.disabled = true;
    btn.style.opacity = ".6";
    btn.textContent = "Syncing...";
    say("");
    try {
      const res = await fetch("/sync", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ docId: TREE_ID }),
      });
      const data = await res.json();
      const msg = data.message || "";
      if (data.ok) {
        // "no changes" matters as much as a push, so report which happened.
        const nothing = /no changes/.test(msg);
        const pushed = /pushed/.test(msg);
        say(nothing ? "Already up to date" : pushed ? "Pushed to GitHub" : "Committed locally", "#2c6e2c");
      } else {
        say("Sync failed - see console", "#b00020");
        console.error("gingko sync:", msg);
      }
      // Somebody edited the generated file upstream; it just got overwritten.
      if (/WARNING/.test(msg)) {
        say("Overwrote an upstream edit - see console", "#a15c00");
        console.warn("gingko sync:", (msg.match(/WARNING:[^\n]*/) || [""])[0]);
      }
    } catch (e) {
      say("Sync failed - see console", "#b00020");
      console.error("gingko sync:", e);
    } finally {
      busy = false;
      btn.disabled = false;
      btn.style.opacity = "1";
      btn.style.background = "#f1f7ef";
      btn.textContent = "Sync with GitHub";
      setTimeout(() => { if (!busy) say(""); }, 8000);
    }
  }

  // Show only for documents that map to a configured project.
  async function refresh() {
    if (!wrap) build();
    if (!TREE_ID) { wrap.style.display = "none"; lastCheckedId = null; return; }
    if (TREE_ID !== lastCheckedId) {
      lastCheckedId = TREE_ID;
      wrap.dataset.configured = "";
      try {
        const info = await (await fetch("/sync/info?docId=" + encodeURIComponent(TREE_ID))).json();
        wrap.dataset.configured = info.configured ? "yes" : "";
        if (info.configured) btn.title = "gingko-sync push " + info.project;
      } catch { wrap.dataset.configured = ""; }
    }
    if (wrap.dataset.configured !== "yes") { wrap.style.display = "none"; return; }
    wrap.style.display = place() ? "flex" : "none";
  }

  window.addEventListener("resize", () => { if (wrap) refresh(); });
  return { refresh };
})();

setInterval(() => syncUI.refresh(), 800);


/* === Images ===============================================================
 * Paste or drop an image while editing a card and it is written into the paper
 * repo, with `![](figures/gingko/name.png)` inserted at the cursor. That path
 * resolves both in the browser (served by GET /figures/*) and in LaTeX, where
 * pandoc turns it into \includegraphics relative to the repo root.
 * ======================================================================== */

const imageUI = (() => {
  function toast(text, colour) {
    let el = document.getElementById("img-toast");
    if (!el) {
      el = document.createElement("div");
      el.id = "img-toast";
      el.style.cssText =
        "position:fixed;left:50%;transform:translateX(-50%);bottom:24px;z-index:9999;" +
        "padding:7px 13px;border-radius:5px;background:rgba(30,30,30,.92);color:#fff;" +
        "font:13px/1.3 'Open Sans',-apple-system,sans-serif;pointer-events:none;";
      document.body.appendChild(el);
    }
    el.textContent = text;
    el.style.background = colour === "error" ? "rgba(150,0,25,.94)" : "rgba(30,30,30,.92)";
    el.style.display = "block";
    clearTimeout(el._t);
    el._t = setTimeout(() => { el.style.display = "none"; }, colour === "error" ? 7000 : 2500);
  }

  // Elm owns the textarea's value, so write through a real input event or the
  // model and the DOM drift apart and the edit is lost on save.
  function insertAtCursor(ta, text) {
    const start = ta.selectionStart, end = ta.selectionEnd;
    ta.value = ta.value.slice(0, start) + text + ta.value.slice(end);
    const pos = start + text.length;
    ta.selectionStart = ta.selectionEnd = pos;
    ta.dispatchEvent(new Event("input", { bubbles: true }));
  }

  function readAsDataUrl(file) {
    return new Promise((resolve, reject) => {
      const fr = new FileReader();
      fr.onload = () => resolve(fr.result);
      fr.onerror = () => reject(fr.error);
      fr.readAsDataURL(file);
    });
  }

  async function upload(file, ta) {
    if (!TREE_ID) return;
    toast("Uploading " + (file.name || "image") + "...");
    try {
      const dataUrl = await readAsDataUrl(file);
      const res = await fetch("/images", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ docId: TREE_ID, dataUrl, name: file.name || "image" }),
      });
      const data = await res.json();
      if (!res.ok) { toast(data.error || "Upload failed", "error"); return; }
      const alt = (file.name || "").replace(/\.[a-z0-9]+$/i, "");
      insertAtCursor(ta, "![" + alt + "](" + data.path + ")");
      toast("Added " + data.path);
    } catch (e) {
      toast("Upload failed: " + e.message, "error");
    }
  }

  function imageFrom(dt) {
    if (!dt) return null;
    const items = dt.files && dt.files.length ? Array.from(dt.files) : [];
    return items.find((f) => f.type && f.type.startsWith("image/")) || null;
  }

  document.addEventListener("paste", (e) => {
    const ta = e.target;
    if (!ta || ta.tagName !== "TEXTAREA") return;
    const file = imageFrom(e.clipboardData);
    if (!file) return;              // plain text paste: leave it alone
    e.preventDefault();
    upload(file, ta);
  }, true);

  document.addEventListener("drop", (e) => {
    const ta = e.target;
    if (!ta || ta.tagName !== "TEXTAREA") return;
    const file = imageFrom(e.dataTransfer);
    if (!file) return;
    e.preventDefault();
    upload(file, ta);
  }, true);

  // Without this the browser navigates away to the dropped file.
  document.addEventListener("dragover", (e) => {
    if (e.target && e.target.tagName === "TEXTAREA") e.preventDefault();
  }, true);

  return {};
})();
