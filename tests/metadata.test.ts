/**
 * Document metadata going out to the server (ADR-0001 seam 4), extracted from
 * doc.js's trees liveQuery and socket lifecycle into src/shared/metadata.js.
 *
 * The case that matters here is CODE_REVIEW.md D6: a rename or a delete made
 * while the socket is down. The liveQuery notices it immediately -- Dexie is
 * local -- but the message it sends is dropped, and nothing used to re-send it
 * when the connection came back, so the change sat unsynced until an unrelated
 * tree-table change or a reload happened to retrigger the liveQuery.
 *
 * Driven through the two events the port layer reports (the trees table
 * changed, the socket opened) against a fake socket, and observed through the
 * messages it asks to be sent.
 */
import { beforeEach, expect, test } from "bun:test";

import { createMetadataSync } from "../src/shared/metadata";

/** A `trees` row, as Dexie holds it (docs/ARCHITECTURE.md §5.1). */
interface TreeRow {
  id: string;
  name: string | null;
  location: string;
  collaborators: string[];
  deletedAt: number | null;
  owner: string;
  createdAt: number;
  updatedAt: number;
  synced: boolean;
}

function treeRow(overrides: Partial<TreeRow> = {}): TreeRow {
  return {
    id: "doc-1",
    name: "As the server has it",
    location: "cardbased",
    collaborators: [],
    deletedAt: null,
    owner: "me@example.com",
    createdAt: 1000,
    updatedAt: 1000,
    synced: true,
    ...overrides,
  };
}

/** The whole trees table, all of it acknowledged by the server. */
function everythingSynced(): TreeRow[] {
  return [treeRow(), treeRow({ id: "doc-2", name: "Another document" })];
}

/** The same table after the open document was renamed: that row is unsynced. */
function renamedOffline(name = "The name I typed offline"): TreeRow[] {
  return [treeRow({ name, updatedAt: 2000, synced: false }), treeRow({ id: "doc-2", name: "Another document" })];
}

let sent: [string, unknown][] = [];
let socketOpen = false;

/**
 * The collaborators doc.js passes in: sending a message, and whether the
 * socket will take one right now (`ws.readyState === ws.OPEN`).
 */
function deps() {
  return {
    send: (tag: string, data: unknown) => sent.push([tag, data]),
    isOpen: () => socketOpen,
  };
}

beforeEach(() => {
  sent = [];
  socketOpen = false;
});

test("a rename made while the socket was down is sent when the socket comes back", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged(renamedOffline());
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([["trees", [expect.objectContaining({ id: "doc-1", name: "The name I typed offline" })]]]);
});

// The two columns of a `trees` row that are local bookkeeping rather than
// something to tell the server: `synced` is this client's own record of what it
// has pushed, and `collaborators` is the server's answer, not the client's to
// state. The resend has to send the same projection the liveQuery does, or a
// reconnect would push a shape the server never sees during normal work.

test("the message carries the unsynced rows without this client's own bookkeeping", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged(renamedOffline());
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([
    [
      "trees",
      [
        {
          id: "doc-1",
          name: "The name I typed offline",
          location: "cardbased",
          deletedAt: null,
          owner: "me@example.com",
          createdAt: 1000,
          updatedAt: 2000,
        },
      ],
    ],
  ]);
});

// Logout tears down the socket and the liveQueries (`stopSyncing`, ticket 04).
// A reconnect resend is one more thing that must not outlive it: pws only
// stops reconnecting once it has been closed explicitly, so an `onopen` can
// still be in flight, and the rows it would push belong to the account that
// just left.

test("a reconnect after logout sends nothing", () => {
  const sync = createMetadataSync(deps());
  sync.treesChanged(renamedOffline());

  sync.stop();
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([]);
});

test("a trees change after logout sends nothing", () => {
  const sync = createMetadataSync(deps());
  socketOpen = true;

  sync.stop();
  sync.treesChanged(renamedOffline());

  expect(sent).toEqual([]);
});

// The other half of D6: a document deleted offline is a `deletedAt` on its
// row, so it travels as unsynced metadata exactly like a rename does. Nothing
// else tells the server about it -- there is no card in a delete.

test("a document deleted while the socket was down is sent when the socket comes back", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged([treeRow(), treeRow({ id: "doc-2", deletedAt: 2000, updatedAt: 2000, synced: false })]);
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([["trees", [expect.objectContaining({ id: "doc-2", deletedAt: 2000 })]]]);
});

// What the reconnect resend sends is the newest state of the table, not a
// backlog of the states it passed through: two renames offline are one row with
// the second name, and the first name is not news the server needs. Sending the
// intermediate states instead -- which is what queueing each liveQuery emission
// would do -- means pushing stale rows, and a row the server takes at face value
// would then come back and overwrite the newer name in Dexie.

test("changes made one after another while the socket was down go out as one message, carrying the newer state", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged(renamedOffline("First name I typed"));
  sync.treesChanged(renamedOffline("Second name I typed"));
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([["trees", [expect.objectContaining({ name: "Second name I typed" })]]]);
});

test("nothing goes out while the socket is down", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged(renamedOffline());

  expect(sent).toEqual([]);
});

test("a reconnect sends nothing when the server has acknowledged every row", () => {
  const sync = createMetadataSync(deps());

  sync.treesChanged(everythingSynced());
  socketOpen = true;
  sync.socketOpened();

  expect(sent).toEqual([]);
});

// The socket can open before the liveQuery has emitted anything at all -- both
// are set up in `setUserDbs`, and neither waits for the other.

test("a connection that opens before the first trees emission sends nothing, and the emission still goes out", () => {
  const sync = createMetadataSync(deps());

  socketOpen = true;
  sync.socketOpened();
  const onOpen = sent.length;
  sync.treesChanged(renamedOffline());

  expect({ onOpen, sent }).toEqual({
    onOpen: 0,
    sent: [["trees", [expect.objectContaining({ name: "The name I typed offline" })]]],
  });
});

test("a change made while the socket is up is sent straight away", () => {
  const sync = createMetadataSync(deps());
  socketOpen = true;

  sync.treesChanged(renamedOffline());

  expect(sent).toEqual([["trees", [expect.objectContaining({ name: "The name I typed offline" })]]]);
});
