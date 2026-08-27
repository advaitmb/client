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
import { computeCheckpoint, maxStamp } from './stamps.js'


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
const { SESSION_STORAGE_KEY, logoutUser, mergeUserIntoSession, readSessionData } = require("./session");
// The local half of a save, extracted for the same reason as session.js:
// nothing in this file is importable by a test (ADR-0001 seam 4).
const { applyCardBasedSave } = require("./save");
// Same reason: which drag is in progress, and everything that follows from it.
const { installDragHandlers } = require("./drag");
// Same reason: which document rows the server has not acknowledged, and when
// they go out -- including on reconnect, which nothing used to do (D6).
const { createMetadataSync } = require("./metadata");
// Which failed websocket messages the user has to hear about, and which stay in
// the console. See ws-errors.js for the policy and why it is an allowlist (E16).
const { wsMessageFailure } = require("./ws-errors");
// Clipboard failures, the same in all three places they can happen (E16).
const { clipboardErrorMessage, copyText } = require("./clipboard");
// Which failed messages *from Elm* the user has to hear about, and the
// browser-extension net below. The ws-errors.js policy, on the other channel
// (S7).
const { isExtensionInterference, portMessageFailure } = require("./port-errors");
// Reading the card log: one row per id, the newest, deletions dropped
// (ADR-0005 §1).
const { backupSnapshotText, rootCardId } = require("./cards");
// Renaming a document, once, however many times Elm asks (S5).
const { renameDocument } = require("./documents");
//import { Elm } from "../elm/Main";

/* === Global Variables === */

window.elmMessages = [];

let remoteDB;
let db;
let gingko;
let TREE_ID;
const CLIENT_ID = uuid(12);
let COLLAB_STATE;
let DATA_TYPE;
// Defined in doc-helpers, which is the other half of the pair that has to agree
// about it: both files used to declare their own `Symbol.for("cardbased")`
// (S13).
const CARD_DATA = helpers.CARD_DATA;
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
let metadataSync = null;
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

  // One per session, and before the socket exists: `onopen` asks it for the
  // metadata the server has not acknowledged.
  metadataSync = createMetadataSync({
    send: (msgTag, msgData) => wsSend(msgTag, msgData, false),
    isOpen: () => !!ws && ws.readyState === ws.OPEN,
  });

  initWebSocket();

  // Sync document list with server

  let firstLoad = true;

  treeListSubscription = Dexie.liveQuery(() => dexie.trees.toArray()).subscribe((trees) => {
    const docMetadatas = trees.filter(t => t.deletedAt == null).map(treeDocToMetadata);
    if (!loadingDocs && !firstLoad) {
      toElm(docMetadatas, "documentListChanged");
    }

    metadataSync.treesChanged(trees);
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
  if (metadataSync != null) { metadataSync.stop(); }
  if (treeListSubscription != null) { treeListSubscription.unsubscribe(); treeListSubscription = null; }
  if (cardDataSubscription != null) { cardDataSubscription.unsubscribe(); cardDataSubscription = null; }
  if (historyDataSubscription != null) { historyDataSubscription.unsubscribe(); historyDataSubscription = null; }
  TREE_ID = null;
  email = null;
  socketIsOpen = false;
  documentIsLoaded = false;
  socketConnectedAnnounced = false;
}


/**
 * One failed websocket message: always a console line, and a visible error
 * state when the failure means data did not reach this device.
 *
 * `ws-errors.js` decides which of those it is, per message type. The user-facing
 * half goes through `ErrorAlert`, the same channel the `pushError` and
 * `cardsConflict` cases use, which shows a persistent toast and sets Elm's error
 * state.
 *
 * @param {string|null} messageType  the message's `t`, or null if the frame did
 *   not parse.
 */
function reportWsFailure(messageType, error) {
  const failure = wsMessageFailure(messageType, error);

  console.error(failure.consoleMessage, error);

  if (failure.userMessage !== null) {
    toElm(failure.userMessage, 'appMsgs', 'ErrorAlert');
  }
}


/**
 * Tell Elm the socket is up — once both halves of "up" are true.
 *
 * `SocketConnected` exists so that `Page.App` can push what this device has not
 * synced (`Data.triggeredPush`), and it can only do that for a document it has
 * loaded: on any other state the message does nothing at all. The socket,
 * meanwhile, is opened during boot, *before* Elm is initialized — so the
 * message used to be sent on a `setTimeout(…, 1000)`, a bet on Elm having
 * booted and loaded a document within the second (CODE_REVIEW.md S5). Lose the
 * bet on a slow start and the unsynced rows sat there until the next save.
 *
 * The two halves are both events this file already sees: the socket opening,
 * and Elm asking for a document (`loadCardBasedDocument`, which has just handed
 * Elm its cards). Whichever is second sends the message, and it is sent once
 * per open socket — a second one would push the same deltas again.
 */
let socketIsOpen = false;
let documentIsLoaded = false;
let socketConnectedAnnounced = false;

function announceSocketConnected() {
  if (!socketIsOpen || !documentIsLoaded || socketConnectedAnnounced) { return; }
  socketConnectedAnnounced = true;
  toElm(null, 'appMsgs', 'SocketConnected');
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

    // The queue holds messages that are events, so it can only hold what was
    // asked for while the socket was down. Document metadata is state: it is
    // re-derived here from the trees table as the liveQuery last emitted it, so
    // a rename or delete made offline reaches the server as soon as it can (D6).
    metadataSync.socketOpened();

    if (TREE_ID) {
      wsSend('rt:join', { tr: TREE_ID, uid: CLIENT_ID, m: COLLAB_STATE || null }, false);
    }

    interval = setInterval(() => ws.send('ping'), 30000)
    socketIsOpen = true;
    announceSocketConnected();
  }

  ws.onmessage = async (e) => {
    if (e.data == 'pong') {
      return
    }

    // Parsing used to sit outside the try, so a frame the server sent that was
    // not JSON rejected this async handler with nobody listening (E16).
    let data
    try {
      data = JSON.parse(e.data)
    } catch (err) {
      reportWsFailure(null, err)
      return
    }

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
            // A snapshot this client already has is the expected case: the
            // server re-announces the whole history, and `bulkAdd` reports one
            // ConstraintError per row that is already there.
            //
            // Anything else is rethrown for the handler-level report. The check
            // used to read `e.failures` unguarded, so an error that was not a
            // BulkError -- the database being closed, say -- threw a TypeError
            // from inside this catch and lost the real reason (E16). An empty
            // `failures` list is likewise not proof that every failure was
            // benign.
            const failures = Array.isArray(e.failures) ? e.failures : []
            const allAlreadyPresent =
              failures.length > 0 && failures.every(f => f.name === 'ConstraintError')

            if (!allAlreadyPresent) {
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
    } catch (err) {
      reportWsFailure(data.t, err)
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

    // pws reconnects on its own, and the next `onopen` has to be able to say so
    // again: what came back is a socket that has not pushed this session's
    // unsynced rows.
    socketIsOpen = false;
    socketConnectedAnnounced = false;

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

      // Awaited, not fire-and-forget in a try that could only ever catch a
      // synchronous throw: this is an async function, so its failure is a
      // rejection, and the dispatch table reports those now (S7).
      await loadCardBasedDocument(TREE_ID);
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

      if (treeDoc.location === "cardbased") {
        // Same as InitDocument: awaited, so a failure to load the document the
        // user just opened is reported rather than swallowed (S7).
        await loadCardBasedDocument(elmData);
      } else {
        console.error("Unknown document location:", treeDoc.location);
        toElm(TREE_ID, "appMsgs", "NotFound");
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

    // Committing a title sends this and then blurs the field, and the blur
    // commits it again -- so the rename is idempotent by value rather than
    // guarded by a "renaming" flag that dropped whichever message lost the race
    // (S5, and documents.js for why by-value is the difference).
    RenameDocument: async () => {
      await renameDocument({ db: dexie, treeId: TREE_ID, name: elmData, now: Date.now });
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
    //
    // The key is spelled exactly as Elm's `Outgoing.SaveImportedTree`, and must
    // stay that way: this handler was `SaveCardBasedTree` while Elm called it
    // `SaveImportedTree`, so a grep for either name found only one side of the
    // message (CODE_REVIEW.md S2). The name that survived says what the message
    // does rather than which storage format the document is in, and does not
    // read as a variant of `SaveCardBased`, which is a different message.
    SaveImportedTree: async () => {
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
      // Reported rather than an unhandled rejection (E16). The flash below is
      // still optimistic, which is fine: an alert lands on top of it.
      copyText(elmData.content);

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

      // Elm renders the slider as it opens the history menu, so on the first
      // open it is not there yet. Waiting for the element beats guessing at
      // 200ms for it (S5); the null check stays, because after `whenReady`'s
      // backstop it can still be missing.
      helpers.whenReady(() => document.getElementById('history-slider') !== null, () => {
        let slider = document.getElementById('history-slider')
        if (slider != null) {
          slider.stepUp(delta);
          slider.dispatchEvent(new Event('input'));
        }
      });
    },

    // `|| {}`: there is a session blob by the time either of these is
    // reachable, unless boot could not reach the server at all -- and a
    // preference is not worth failing over on a first run without one (S8).
    SaveUserSetting: () => {
      let key = elmData[0];
      let value = elmData[1];
      let currSessionData = getSessionData() || {};
      currSessionData[key] = value;
      setSessionData(currSessionData, "SaveUserSetting");
    },

    SetSidebarState: () => {
      let currSessionData = getSessionData() || {};
      currSessionData.sidebarOpen = elmData;
      setSessionData(currSessionData, "SetSidebarState");
      window.requestAnimationFrame(()=>{
        const sidebar = document.getElementById('sidebar');
        if (sidebar) { sidebarWidth = sidebar.clientWidth; }
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


    // `EmptyMessageShown` was here, doing nothing: the empty-documents screen
    // fired it from a broken <img>'s error event, and this handler was `() =>
    // {}`. Both ends are gone (S12) -- the honest mechanism for a message
    // nobody listens to is not to send it.

    InitBeamer: () => {

    },

    SocketSend: () => {},
  };


  const cases = Object.assign(helpers.casesShared(elmData, params), casesWeb)

  const handler = cases[msg];

  // A tag with no handler is the only thing that deserves this sentence, and
  // it used to be printed for a handler that threw as well -- which named the
  // message as the culprit and buried the real error behind a wrong
  // explanation (S7).
  if (typeof handler !== "function") {
    console.error("Unexpected message from Elm : ", msg, elmData);
    return;
  }

  try {
    const result = handler();
    // Most handlers are `async`, so their failures arrive as a rejected promise
    // that the `try` around the call never sees -- which was every Dexie write
    // in the table (S7).
    if (result != null && typeof result.then === "function") {
      result.then(undefined, (err) => reportPortFailure(msg, elmData, err));
    }
  } catch (err) {
    reportPortFailure(msg, elmData, err);
  }
};


/**
 * One failed message from Elm: always a console line naming the tag, and a
 * dialog when the failure means a change of the user's did not reach this
 * device. `port-errors.js` decides which, per tag, and says why.
 */
function reportPortFailure(tag, data, error) {
  const failure = portMessageFailure(tag, error);

  console.error(failure.consoleMessage, data, error);

  if (failure.userMessage !== null) {
    alert(failure.userMessage);
  }
}


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
        activateRootCard(cards);
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

  // Elm has its cards and the socket can now say it is up: whichever of the two
  // was second sends `SocketConnected`, which is what pushes what this device
  // has not synced.
  documentIsLoaded = true;
  announceSocketConnected();

  // Which document is open decides whether the GitHub sync button is shown at
  // all, and this is the one place that changes.
  syncUI.refresh();

  // Pull data from remote
  pull(treeId, chk);
}

/**
 * Activate the document's first root card, once its element exists.
 *
 * Elm answers this by scrolling to the card, so the card has to be on screen:
 * that was `setTimeout(…, 20)`, and 20ms is neither a guarantee nor a
 * requirement (S5). Which card it is comes from `rootCardId`, which reads the
 * log the only legal way -- the old `cards.filter(c => c.parentId === null)[0]`
 * took the newest *row* with no parent, deleted rows included, and threw
 * outright on a document whose root card was gone (S8).
 */
function activateRootCard(cards) {
  const cardId = rootCardId(cards);

  if (cardId === null) {
    console.error("This document has no root card to activate");
    return;
  }

  helpers.whenReady(
    () => document.querySelector('[id="card-' + cardId + '"]') !== null,
    () => toElm(cardId, "docMsgs", "InitialActivation")
  );
}

function pull(treeId, chk) {
  wsSend("pull", [treeId, chk], true);
  // Straight after the pull, not 500ms behind it: a websocket delivers in the
  // order it was written and `wsQueue` drains in the order it was filled, so
  // the delay was not waiting for anything -- it only meant that a document
  // opened and closed inside half a second never asked for its history at all
  // (S5).
  wsSend('pullHistoryMeta', treeId, true);
}

function saveBackupToImmortalDB (treeId, cards) {
  if (ImmortalDB) {
    ImmortalDB.set('backup-snapshot:' + treeId, backupSnapshotText(cards));
  }
}

function treeToHtml (tree) {
  return "<section>\n"
    + tree.content
    + "\n"
    + tree.children.map(treeToHtml).join("\n")
    + "</section>";
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

// The stored session, or null. What "or null" covers -- absent, unparseable,
// or parsed to something that is not a blob -- is session.js's to say: boot's
// very first step used to be an unguarded `JSON.parse` here, so one corrupted
// value was a blank page (S8).
function getSessionData() {
  return readSessionData();
}

function setSessionData(data, source) {
  console.log("Setting session data:",source, JSON.stringify(data))
  try {
    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(data));
  } catch (err) {
    // A denied or full localStorage costs this session its preferences on the
    // next reload, and nothing else: everything that matters is in Dexie. Not
    // worth failing the message that asked for it.
    console.error("session: could not store the session", source, err);
  }
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
            // Not a card subtree, so it is text: paste it as it is.
            toElm(clipString, "docMsgs", elmTag)
          }
        }).catch(err => {
          // Every failure is reported now, not only the ones whose message
          // happened to contain "denied" -- and reading the message is guarded,
          // because this used to throw a second time inside the catch for an
          // error that had none (E16).
          alert(clipboardErrorMessage("read", err))
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

// The last net: an error nothing else caught. Only one kind of them is
// actionable -- an extension rewriting the DOM under Elm's virtual DOM -- and
// `isExtensionInterference` is the guarded version of the test that used to be
// here: this listener also fires for failed *resource* loads, whose event
// carries no `message` at all, so `err.message.match(...)` threw a TypeError
// from inside the error handler and lost the original error with it (S7).
window.addEventListener("error", (err) => {
  console.error("uncaught error", err);

  if (isExtensionInterference(err && err.message)) {
    alert("There may be an extension interfering with Gingko Writer.\n\nDisable your extensions and try again, or contact support");
    cleanBodyHelp();
  }
});

// The same net for a promise nobody handled. Not silenced, and not alerted
// either: every path that can tell the user something already does (the port
// dispatch, `ws.onmessage`, the clipboard and the save), so anything reaching
// here is news for the console and a bug to fix.
window.addEventListener("unhandledrejection", (event) => {
  console.error("unhandled rejection", event && event.reason);
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
    watchHeader();
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
    reposition();
  }

  /** Put the button where the header currently is, or hide it if there is none. */
  function reposition() {
    if (!wrap || wrap.dataset.configured !== "yes") { return; }
    wrap.style.display = place() ? "flex" : "none";
  }

  /**
   * Follow the header's geometry, rather than re-reading it 75 times a minute
   * for the entire session (S5).
   *
   * `place()` needs to run again whenever the header's box changes, and the
   * header is a CSS grid whose icon columns are pinned to its right edge -- so
   * "the box changed" covers every way the anchor can move: the window
   * resizing, the sidebar opening, a header menu adding its row. A
   * ResizeObserver is exactly that event.
   *
   * Elm can also replace the header element itself (navigating between the
   * document page and every other one), which no observer on the old node
   * reports. That is what `gw-header-rendered` is for, below: the element says
   * when it has rendered, and this re-observes whatever is there now.
   */
  function watchHeader() {
    if (typeof ResizeObserver !== "function") { return; }
    const header = document.getElementById("document-header");
    if (header === observedHeader) { return; }
    if (headerObserver === null) {
      headerObserver = new ResizeObserver(reposition);
    }
    headerObserver.disconnect();
    observedHeader = header;
    if (header !== null) { headerObserver.observe(header); }
  }

  window.addEventListener("resize", () => { if (wrap) refresh(); });
  return { refresh };
})();

let headerObserver = null;
let observedHeader = null;

// The header telling us it has rendered, which is the one thing a
// ResizeObserver on it cannot: that there is a *new* header element, or that
// the icon the button is measured against has just appeared in it. Elm's own
// re-renders reach us this way too, so nothing here polls (S5).
document.addEventListener("gw-header-rendered", () => syncUI.refresh());
// And once now, for the header that may already be on screen by the time this
// module finishes loading. Which document is open is the other input, and
// `loadCardBasedDocument` asks for a refresh when that changes.
syncUI.refresh();


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
