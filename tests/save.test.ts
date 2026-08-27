/**
 * The local half of a save (ADR-0001 seam 4), extracted from doc.js's dispatch
 * table into src/shared/save.js so it can be exercised without IndexedDB.
 *
 * Elm sends the `SaveCardBased` port message; this is everything that happens
 * next locally. Observed through the boundary it actually crosses — the Dexie
 * database, faked in memory below — plus the callback doc.js supplies for
 * telling the user a save failed.
 *
 * The case that matters here is a JSON import (CODE_REVIEW.md D5): the save it
 * hands over is for a document that is *not* the one on screen, and it travels
 * alongside a second port message (`SaveImportedTree`) whose order relative to
 * this one `Cmd.batch` does not specify. So a save has to say which document it
 * is for, and touch nothing else.
 */
import { beforeEach, expect, test } from "bun:test";

import { applyCardBasedSave } from "../src/shared/save";

interface CardRow {
  updatedAt: string;
  id: string;
  treeId: string;
  content: string;
  deleted: number;
  synced: boolean;
}

interface TreeRow {
  id: string;
  name: string | null;
  updatedAt: number;
  synced?: boolean;
}

interface SnapshotRow {
  snapshot: string;
  treeId: string;
  data: unknown[];
  local: boolean;
  ts: number;
}

/**
 * The slice of Dexie that `applyCardBasedSave` uses, in memory. Primary keys
 * are the real ones (docs/ARCHITECTURE.md §5.1): `cards.updatedAt`,
 * `trees.id`, `tree_snapshots.snapshot`.
 *
 * Two Dexie behaviors the tests depend on are modelled deliberately:
 * `Table.update` on a key that is not there changes nothing and reports 0
 * rows, and a query or update with an undefined key is an error, not a match
 * on everything.
 */
function fakeDexie(seed: { cards?: CardRow[]; trees?: TreeRow[]; snapshots?: SnapshotRow[] } = {}) {
  const cards: CardRow[] = (seed.cards ?? []).map((row) => ({ ...row }));
  const trees: TreeRow[] = (seed.trees ?? []).map((row) => ({ ...row }));
  const snapshots: SnapshotRow[] = (seed.snapshots ?? []).map((row) => ({ ...row }));

  const asKey = (key: unknown): string => {
    if (key === undefined || key === null) {
      throw new Error("DataError: Invalid key provided");
    }
    return String(key);
  };

  const upsert = <T>(rows: T[], row: T, key: (r: T) => string) => {
    const at = rows.findIndex((existing) => key(existing) === key(row));
    if (at === -1) rows.push(row);
    else rows[at] = row;
  };

  return {
    cards: {
      bulkPut(rows: CardRow[]) {
        rows.forEach((row) => upsert(cards, { ...row }, (r) => r.updatedAt));
      },
      bulkDelete(keys: string[]) {
        keys.forEach((key) => {
          const at = cards.findIndex((row) => row.updatedAt === key);
          if (at !== -1) cards.splice(at, 1);
        });
      },
      /**
       * Dexie answers a `where({...})` only through a declared index, and
       * `cards` declares `treeId` and `[treeId+deleted]`
       * (docs/ARCHITECTURE.md §5.1): a query for the whole log of one document
       * and a query pre-filtered per row on `deleted` are both indexed, and
       * anything else is a schema error rather than a slow scan.
       */
      where(criteria: { treeId: string; deleted?: number }) {
        const index = Object.keys(criteria).sort().join("+");
        if (index !== "treeId" && index !== "deleted+treeId") {
          throw new Error(`SchemaError: KeyPath ${index} is not indexed on object store cards`);
        }
        const treeId = asKey(criteria.treeId);
        return {
          toArray: async () =>
            cards.filter(
              (row) =>
                row.treeId === treeId && (criteria.deleted === undefined || row.deleted === criteria.deleted)
            ),
        };
      },
    },
    trees: {
      async update(id: string, changes: Partial<TreeRow>) {
        const key = asKey(id);
        const row = trees.find((tree) => tree.id === key);
        if (!row) return 0;
        Object.assign(row, changes);
        return 1;
      },
    },
    tree_snapshots: {
      async put(row: SnapshotRow) {
        upsert(snapshots, { ...row }, (r) => r.snapshot);
      },
    },
    async transaction(_mode: string, _tables: unknown, body: () => Promise<void>) {
      await body();
    },
    contents: { cards, trees, snapshots },
  };
}

const OPEN_DOC = "open-doc";
const IMPORTED_DOC = "imported-doc";

/** The document already on screen: two synced cards, a snapshot, a timestamp. */
function openDocumentRows() {
  return {
    cards: [
      { updatedAt: "1000:0:a", id: "a", treeId: OPEN_DOC, content: "Root", deleted: 0, synced: true },
      { updatedAt: "1000:1:b", id: "b", treeId: OPEN_DOC, content: "Child", deleted: 0, synced: true },
    ],
    trees: [{ id: OPEN_DOC, name: "The document I was working on", updatedAt: 1000 }],
    snapshots: [
      { snapshot: "1000:open-doc", treeId: OPEN_DOC, data: [], local: true, ts: 1000 },
    ],
  };
}

/** A card row as Elm stages it: no stamp yet, the port layer mints that. */
function stagedCard(id: string, treeId: string, content: string) {
  return { id, treeId, content, parentId: null, position: 1, deleted: 0, synced: false, updatedAt: "" };
}

/** What `Data.importTree` hands over: every card of the new document, at once. */
function importPayload(treeId: string) {
  return {
    treeId,
    toAdd: [stagedCard("i1", treeId, "Imported root"), stagedCard("i2", treeId, "Imported child")],
    toMarkSynced: [],
    toMarkDeleted: [],
    toRemove: [],
  };
}

let errors: string[] = [];
let stampCounter = 0;

/** The clock and id sources doc.js passes in, made deterministic. */
function deps(db: ReturnType<typeof fakeDexie>) {
  return {
    db,
    nextStamp: () => `2000:${stampCounter++}:new`,
    newDeleteHash: () => "delete-hash",
    now: () => 5000,
    markClean: () => {},
    onError: (message: string) => errors.push(message),
  };
}

beforeEach(() => {
  errors = [];
  stampCounter = 0;
});

test("writes the local snapshot for the document the save names, and only that one", async () => {
  const db = fakeDexie(openDocumentRows());

  await applyCardBasedSave(importPayload(IMPORTED_DOC), deps(db));

  expect(db.contents.snapshots.map((s) => s.snapshot)).toEqual(["1000:open-doc", "2000:imported-doc"]);
});

test("the snapshot holds the named document's cards and nothing else", async () => {
  const db = fakeDexie(openDocumentRows());

  await applyCardBasedSave(importPayload(IMPORTED_DOC), deps(db));

  // Compared as a set: a snapshot's row order is not meaningful, since Elm
  // rebuilds the tree from `parentId` and sorts siblings by position.
  const imported = db.contents.snapshots.find((s) => s.treeId === IMPORTED_DOC);
  expect((imported?.data as CardRow[] | undefined)?.map((c) => c.id).sort()).toEqual(["i1", "i2"]);
});

test("stamps the named document's row unsynced and leaves every other one alone", async () => {
  const db = fakeDexie({
    ...openDocumentRows(),
    trees: [
      { id: OPEN_DOC, name: "The document I was working on", updatedAt: 1000 },
      { id: IMPORTED_DOC, name: "Imported.json", updatedAt: 4000 },
    ],
  });

  await applyCardBasedSave(importPayload(IMPORTED_DOC), deps(db));

  expect(db.contents.trees).toEqual([
    { id: OPEN_DOC, name: "The document I was working on", updatedAt: 1000 },
    { id: IMPORTED_DOC, name: "Imported.json", updatedAt: 5000, synced: false },
  ]);
});

// An import can be the first thing a session does: nothing has been opened, so
// there is no current document at all. It has to work anyway, and the tree row
// may not be there yet either -- `SaveImportedTree` writes that, and the two
// port messages arrive in whichever order `Cmd.batch` chose.

test("an import on a fresh session reports no error and snapshots the new document", async () => {
  const db = fakeDexie();

  await applyCardBasedSave(importPayload(IMPORTED_DOC), deps(db));

  expect({ errors, snapshots: db.contents.snapshots.map((s) => s.snapshot) }).toEqual({
    errors: [],
    snapshots: ["2000:imported-doc"],
  });
});

test("an import whose document row has not been written yet still saves its cards", async () => {
  const db = fakeDexie();

  await applyCardBasedSave(importPayload(IMPORTED_DOC), deps(db));

  expect({ errors, cards: db.contents.cards.map((c) => [c.id, c.updatedAt]) }).toEqual({
    errors: [],
    cards: [
      ["i1", "2000:0:new"],
      ["i2", "2000:1:new"],
    ],
  });
});

// The ordinary case: a save for the document on screen, which is what every
// other sender of `SaveCardBased` produces.

test("a save for the document on screen applies its cards, snapshot and timestamp", async () => {
  const db = fakeDexie(openDocumentRows());

  await applyCardBasedSave(
    {
      treeId: OPEN_DOC,
      toAdd: [stagedCard("c", OPEN_DOC, "A third card")],
      toMarkSynced: [],
      toMarkDeleted: [],
      toRemove: ["1000:1:b"],
    },
    deps(db)
  );

  expect({
    cards: db.contents.cards.map((c) => c.id),
    snapshots: db.contents.snapshots.map((s) => s.snapshot),
    updatedAt: db.contents.trees.map((t) => t.updatedAt),
  }).toEqual({ cards: ["a", "c"], snapshots: ["1000:open-doc", "2000:open-doc"], updatedAt: [5000] });
});

test("a save that names no document is refused rather than guessed at", async () => {
  const db = fakeDexie(openDocumentRows());

  await applyCardBasedSave(
    { toAdd: [stagedCard("c", OPEN_DOC, "A third card")], toMarkSynced: [], toMarkDeleted: [], toRemove: [] },
    deps(db)
  );

  expect({ errorCount: errors.length, cards: db.contents.cards.map((c) => c.id) }).toEqual({
    errorCount: 1,
    cards: ["a", "b"],
  });
});

// What a snapshot holds is the card set, and the `cards` table is a log of
// version rows rather than a card set: rows a card has outgrown stay in it
// until fast-forward (CONTEXT.md), so only the newest row per id says what the
// document holds now. A snapshot built by filtering rows one at a time reads
// the log as though it were the card set, and the history slider then offers a
// state the document was never in -- restoring it undeletes a card, because
// doc.js hands every snapshot row to Elm as `deleted: 0`.

/**
 * A document whose version log has outlived the states it records: since the
 * server last saw it, `a` was edited and then deleted, `b` was edited, and `d`
 * was deleted and then brought back by a restore. Every one of those rows is
 * still in the table; the cards the document holds are `r`, `b` (edited) and
 * `d` (back), and `a` is gone.
 */
function documentEditedOffline() {
  return {
    cards: [
      { updatedAt: "1000:0:r", id: "r", treeId: OPEN_DOC, content: "Root", deleted: 0, synced: true },
      { updatedAt: "1000:1:d", id: "d", treeId: OPEN_DOC, content: "A card I deleted", deleted: 0, synced: true },
      { updatedAt: "1050:0:b", id: "b", treeId: OPEN_DOC, content: "B, as the server has it", deleted: 0, synced: true },
      { updatedAt: "1100:0:a", id: "a", treeId: OPEN_DOC, content: "A, edited just before I deleted it", deleted: 0, synced: false },
      { updatedAt: "1200:0:adel", id: "a", treeId: OPEN_DOC, content: "A, edited just before I deleted it", deleted: 1, synced: false },
      { updatedAt: "1300:0:b2", id: "b", treeId: OPEN_DOC, content: "B, edited since", deleted: 0, synced: false },
      { updatedAt: "1400:0:ddel", id: "d", treeId: OPEN_DOC, content: "A card I deleted", deleted: 1, synced: false },
      { updatedAt: "1500:0:dundel", id: "d", treeId: OPEN_DOC, content: "A card I deleted, then restored", deleted: 0, synced: false },
    ],
    trees: [{ id: OPEN_DOC, name: "The document I was working on", updatedAt: 1500 }],
    snapshots: [{ snapshot: "1500:open-doc", treeId: OPEN_DOC, data: [], local: true, ts: 1500 }],
  };
}

/** The save that types one more card into that document, and snapshots it. */
function typedOneMoreCard() {
  return {
    treeId: OPEN_DOC,
    toAdd: [stagedCard("e", OPEN_DOC, "A card I just typed")],
    toMarkSynced: [],
    toMarkDeleted: [],
    toRemove: [],
  };
}

/** A deletion row as Elm stages it (`{ card | deleted = True } |> asUnsynced`). */
function stagedDeletion(id: string, treeId: string, content: string) {
  return { id, treeId, content, parentId: null, position: 1, deleted: 1, synced: false, updatedAt: "" };
}

/** The rows of one snapshot, as `[id, content]` pairs: which version of what. */
function snapshotCards(db: ReturnType<typeof fakeDexie>, snapshot: string) {
  const written = db.contents.snapshots.find((s) => s.snapshot === snapshot);
  return ((written?.data ?? []) as CardRow[]).map((c) => [c.id, c.content]).sort();
}

test("a card whose newest row is a deletion is left out of the snapshot", async () => {
  const db = fakeDexie(documentEditedOffline());

  await applyCardBasedSave(typedOneMoreCard(), deps(db));

  expect(snapshotCards(db, "2000:open-doc").filter(([id]) => id === "a")).toEqual([]);
});

test("every card the document still holds contributes exactly its newest row", async () => {
  const db = fakeDexie(documentEditedOffline());

  await applyCardBasedSave(typedOneMoreCard(), deps(db));

  expect(snapshotCards(db, "2000:open-doc")).toEqual([
    ["b", "B, edited since"],
    ["d", "A card I deleted, then restored"],
    ["e", "A card I just typed"],
    ["r", "Root"],
  ]);
});

test("a card deleted and then brought back is in the snapshot, at the row that brought it back", async () => {
  const db = fakeDexie(documentEditedOffline());

  await applyCardBasedSave(typedOneMoreCard(), deps(db));

  expect(snapshotCards(db, "2000:open-doc").filter(([id]) => id === "d")).toEqual([
    ["d", "A card I deleted, then restored"],
  ]);
});

test("a save that deletes a card leaves the history entry that still had it", async () => {
  const db = fakeDexie(documentEditedOffline());

  await applyCardBasedSave(
    {
      treeId: OPEN_DOC,
      toAdd: [],
      toMarkSynced: [],
      toMarkDeleted: [stagedDeletion("b", OPEN_DOC, "B, edited since")],
      toRemove: [],
    },
    deps(db)
  );

  expect(db.contents.snapshots.map((s) => s.snapshot)).toEqual(["1500:open-doc", "5000:open-doc"]);
});
