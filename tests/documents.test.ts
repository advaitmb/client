/**
 * Renaming a document (ADR-0001 seam 4), extracted from doc.js's dispatch
 * table into src/shared/documents.js — CODE_REVIEW.md S5.
 *
 * Committing a title sends `RenameDocument` and then blurs the field, and the
 * blur commits it again (`Page.App.TitleEdited` cannot tell the two apart: the
 * name it compares against only changes once the write has been round-tripped
 * through Dexie's liveQuery). doc.js's answer was a module-level `renaming`
 * boolean that dropped whichever message arrived while the other was in
 * flight — a timing window, so what it dropped depended on how fast the
 * database was, and a *different* second name would have been dropped too.
 *
 * The rename is idempotent by value instead: a name that is already stored is
 * not written again. The database is injected and faked in memory, per seam 4.
 */
import { expect, test } from "bun:test";

import { renameDocument } from "../src/shared/documents";

interface TreeRow {
  id: string;
  name: string | null;
  updatedAt: number;
  synced?: boolean;
}

/**
 * The slice of Dexie `renameDocument` uses. `transaction` is modelled as what
 * IndexedDB guarantees and the rename depends on: two read-modify-writes over
 * the same table are serialized, so they cannot both read the old name.
 */
function fakeDexie(seed: TreeRow[]) {
  const rows: TreeRow[] = seed.map((row) => ({ ...row }));
  let queue: Promise<unknown> = Promise.resolve();
  let writes = 0;

  const db = {
    rows,
    writes: () => writes,
    trees: {
      get: async (id: string) => {
        const found = rows.find((row) => row.id === id);
        return found ? { ...found } : undefined;
      },
      update: async (id: string, changes: Partial<TreeRow>) => {
        const at = rows.findIndex((row) => row.id === id);
        if (at === -1) return 0;
        rows[at] = { ...rows[at]!, ...changes };
        writes += 1;
        return 1;
      },
    },
    transaction: (_mode: string, _table: unknown, body: () => Promise<unknown>) => {
      const run = queue.then(() => body());
      queue = run.catch(() => undefined);
      return run;
    },
  };

  return db;
}

const clock = (start = 1000) => {
  let t = start;
  return () => (t += 1);
};

test("a rename writes the new name and leaves the row unsynced", async () => {
  const db = fakeDexie([{ id: "doc1", name: "Old", updatedAt: 1, synced: true }]);

  const renamed = await renameDocument({ db, treeId: "doc1", name: "New", now: clock() });

  expect(renamed).toBe(true);
  expect(db.rows[0]).toEqual({ id: "doc1", name: "New", updatedAt: 1001, synced: false });
});

test("renaming to the name it already has writes nothing", async () => {
  const db = fakeDexie([{ id: "doc1", name: "Same", updatedAt: 1, synced: true }]);

  const renamed = await renameDocument({ db, treeId: "doc1", name: "Same", now: clock() });

  expect(renamed).toBe(false);
  // Not even the timestamp: bumping it marks the row unsynced and pushes a
  // no-op rename to the server.
  expect(db.rows[0]).toEqual({ id: "doc1", name: "Same", updatedAt: 1, synced: true });
});

test("the commit and the blur it causes rename once, in either order", async () => {
  const db = fakeDexie([{ id: "doc1", name: "Old", updatedAt: 1, synced: true }]);
  const now = clock();

  // Both messages in flight at once, which is exactly what `Cmd.batch`'s
  // `RenameDocument` + `Browser.Dom.blur` produces.
  await Promise.all([
    renameDocument({ db, treeId: "doc1", name: "New", now }),
    renameDocument({ db, treeId: "doc1", name: "New", now }),
  ]);

  expect(db.writes()).toBe(1);
  expect(db.rows[0]!.name).toBe("New");
});

test("a second, different name still lands", async () => {
  // What the `renaming` flag got wrong: it dropped the message, not the
  // duplicate, so a name typed while the first write was in flight was lost.
  const db = fakeDexie([{ id: "doc1", name: "Old", updatedAt: 1, synced: true }]);
  const now = clock();

  await Promise.all([
    renameDocument({ db, treeId: "doc1", name: "First", now }),
    renameDocument({ db, treeId: "doc1", name: "Second", now }),
  ]);

  expect(db.writes()).toBe(2);
  expect(db.rows[0]!.name).toBe("Second");
});

test("renaming a document that is not there writes nothing", async () => {
  const db = fakeDexie([]);

  const renamed = await renameDocument({ db, treeId: "gone", name: "New", now: clock() });

  expect(renamed).toBe(false);
  expect(db.rows).toEqual([]);
});
