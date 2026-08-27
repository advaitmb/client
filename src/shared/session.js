/**
 * The browser session, on the JS side of the ports.
 *
 * doc.js owns reading and writing the session blob (getSessionData /
 * setSessionData); what lives here is the one sequence that has to be
 * testable on its own — logout. It is imported rather than inlined into
 * doc.js's dispatch table because doc.js starts the whole app at module load
 * (initElmAndPorts), so nothing in it can be imported by a test.
 *
 * Storage key: the session blob is the localStorage entry Elm's flags are
 * decoded from (docs/ARCHITECTURE.md §6.2). Defined here, once, so the
 * dispatch table and the logout path cannot drift apart.
 */

const SESSION_STORAGE_KEY = "gingko-session-storage";

/**
 * The keys in the session blob that belong to this client and no one else.
 * Elm writes them through the `SaveUserSetting` and `SetSidebarState` ports,
 * which reach localStorage and stop there — nothing pushes them to the
 * server — so a server answer that mentions them is not news, it is a reset.
 */
const CLIENT_PREF_KEYS = ["shortcutTrayOpen", "sortBy", "sidebarOpen", "lastDocId"];

/**
 * The session blob after adopting what the server says about the logged-in
 * user: `/me` on boot (self-host has no login screen, so this is how the
 * account is adopted).
 *
 * The server wins on everything it owns — the email, confirmation, features.
 * It does not win on the preferences above once this client has stored them:
 * those are only ever written here, so `/me` can offer them for a first boot
 * but never overwrite them afterwards. Same rule the Elm login decoder
 * follows for `shortcutTrayOpen` and `sortBy` (CODE_REVIEW E3).
 *
 * @param {Object|null} stored  the session blob as it is now, if any.
 * @param {Object|null} fromServer  the parsed `/me` body.
 * @returns {Object} the blob to store. Neither argument is mutated.
 */
function mergeUserIntoSession(stored, fromServer) {
  const current = stored || {};
  const merged = Object.assign({}, current);

  Object.keys(fromServer || {}).forEach((key) => {
    const isClientPref = CLIENT_PREF_KEYS.indexOf(key) !== -1;
    if (isClientPref && Object.prototype.hasOwnProperty.call(current, key)) {
      return;
    }
    merged[key] = fromServer[key];
  });

  return merged;
}

/**
 * End the session, everywhere: the server's, then the local one, then the
 * connections that were syncing as that user, and finally hand control back
 * to Elm (`userLoggedOutMsg` → Main.UserLoggedOut → the login page).
 *
 * Every step is best-effort, and in this order, because a self-host must
 * never be unable to log out. The server may be down, unreachable, or older
 * than gingko/server's POST /logout (which destroys the express session,
 * clears the connect.sid cookie and answers 200 with an empty body); a
 * failure there still leaves the user logged out on this machine, which is
 * the part they can see. Non-2xx and network errors are logged and stepped
 * over rather than aborting the sequence.
 *
 * Local document data (Dexie `cards`/`trees`/`tree_snapshots`, the
 * ImmortalDB backups, the per-document `gingko-local-store/…` settings) is
 * deliberately kept: unsynced card rows are the only copy of work done
 * offline, so logout must not be a delete. Only the session blob goes.
 *
 * @param {Object}   [handlers]
 * @param {Function} [handlers.teardown]     stop syncing as the departing
 *                                           user (socket, liveQueries) —
 *                                           doc.js owns those.
 * @param {Function} [handlers.onLoggedOut]  tell Elm; runs last, and runs
 *                                           even if an earlier step failed.
 */
async function logoutUser({ teardown, onLoggedOut } = {}) {
  try {
    const response = await fetch("/logout", { method: "POST" });
    if (!response.ok) {
      console.error("logout: POST /logout returned", response.status);
    }
  } catch (err) {
    console.error("logout: POST /logout failed", err);
  }

  try {
    localStorage.removeItem(SESSION_STORAGE_KEY);
  } catch (err) {
    console.error("logout: could not clear the stored session", err);
  }

  if (teardown) {
    try {
      teardown();
    } catch (err) {
      console.error("logout: could not stop syncing", err);
    }
  }

  if (onLoggedOut) {
    onLoggedOut();
  }
}

module.exports = {
  SESSION_STORAGE_KEY: SESSION_STORAGE_KEY,
  logoutUser: logoutUser,
  mergeUserIntoSession: mergeUserIntoSession,
};
