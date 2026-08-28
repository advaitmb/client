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
 * The session blob as it is stored, or null if there isn't one this client can
 * use.
 *
 * This is the first thing boot does: `getFlags` reads it, decorates it and
 * hands it to Elm as its flags. It used to be a bare `JSON.parse`, so a
 * corrupted value threw before Elm existed — a blank page with no way back
 * except clearing site data by hand (CODE_REVIEW.md S8). Anything unusable is
 * a guest session instead, which is a working app.
 *
 * "Unusable" includes JSON that parses to something that is not a blob: a
 * number or a string takes `getFlags`' field assignments silently and then
 * fails Elm's flag decoder, which is the same blank page by a longer route.
 *
 * The corrupt value is removed rather than left in place. Nothing can be
 * recovered from it (the document data lives in Dexie; this holds the email
 * and a handful of preferences), the next write would overwrite it anyway, and
 * leaving it means logging the same failure on every reload.
 *
 * @returns {Object|null}
 */
function readSessionData() {
  let raw;
  try {
    raw = localStorage.getItem(SESSION_STORAGE_KEY);
  } catch (err) {
    // Storage can be denied outright (private modes, blocked cookies). A
    // session that cannot be read is a guest, not a crash.
    console.error("session: could not read the stored session", err);
    return null;
  }

  if (!raw) {
    return null;
  }

  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    console.error("session: the stored session is not valid JSON; ignoring it", err);
  }

  const usable =
    parsed !== null && typeof parsed === "object" && !Array.isArray(parsed);

  if (!usable) {
    try {
      localStorage.removeItem(SESSION_STORAGE_KEY);
    } catch (err) {
      console.error("session: could not clear the unusable stored session", err);
    }
    return null;
  }

  return parsed;
}

/**
 * Store the session blob.
 *
 * Best-effort, like the read: localStorage can be denied outright or full, and
 * what that costs is this session's preferences on the next reload — everything
 * that matters is in Dexie. Not worth failing the message that asked for it.
 *
 * @param {Object} data    the blob to store.
 * @param {string} source  which message asked, for the console line.
 */
function writeSessionData(data, source) {
  console.log("Setting session data:", source, JSON.stringify(data));
  try {
    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(data));
  } catch (err) {
    console.error("session: could not store the session", source, err);
  }
}

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
 * What the server says this browser is logged in as, on boot.
 *
 * `/me` is the self-host session probe (§6.1 step 3): with no login screen in
 * the way, its answer is what names the account whose database to open and
 * whose document list to seed. But it is an *optional* endpoint — gingko/server
 * master does not implement it, and its last route is `app.get('*')`, which
 * answers every unknown path with the app's own index.html and a 200. So
 * `res.ok` says nothing about whether there is an account in the body, and
 * calling `res.json()` on the strength of it put
 * `auto-login failed SyntaxError: Unexpected token '<'` on the console of every
 * boot of a perfectly working install (ticket 38).
 *
 * Hence: read the body as JSON only when the answer says it is JSON, and
 * classify everything else rather than throwing. A server without the endpoint
 * and a server with no session for this browser are both ordinary; only a
 * server that was supposed to answer and could not is worth telling anyone
 * about.
 *
 * @param {function(string): Promise<Response>} fetchFn  `fetch`, injected.
 * @returns {Promise<{status: string, account?: Object, reason?: string}>}
 *   `account`      — a JSON body: the account to adopt, in `account`.
 *   `no-endpoint`  — 404, or a 200 that is not JSON: this server has no `/me`.
 *   `no-session`   — 401/403: it has one, and nobody is logged in here.
 *   `unavailable`  — anything else, with a `reason` for the console.
 */
async function fetchAccount(fetchFn) {
  let res;
  try {
    res = await fetchFn("/me");
  } catch (err) {
    return { status: "unavailable", reason: errorText(err) };
  }

  if (res.status === 401 || res.status === 403) {
    return { status: "no-session" };
  }
  if (res.status === 404) {
    return { status: "no-endpoint" };
  }
  if (!res.ok) {
    return { status: "unavailable", reason: "the server answered " + res.status };
  }

  const contentType =
    (res.headers && typeof res.headers.get === "function"
      ? res.headers.get("content-type")
      : null) || "";
  if (contentType.toLowerCase().indexOf("json") === -1) {
    return { status: "no-endpoint" };
  }

  let account;
  try {
    account = await res.json();
  } catch (err) {
    return { status: "unavailable", reason: errorText(err) };
  }

  if (!account || typeof account !== "object" || Array.isArray(account)) {
    return { status: "unavailable", reason: "the answer was not an account object" };
  }

  return { status: "account", account: account };
}

/** A thrown value as one line, for a `reason`. */
function errorText(err) {
  if (err && typeof err.message === "string" && err.message) {
    return err.message;
  }
  return String(err);
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
  readSessionData: readSessionData,
  writeSessionData: writeSessionData,
  logoutUser: logoutUser,
  mergeUserIntoSession: mergeUserIntoSession,
  fetchAccount: fetchAccount,
};
