/**
 * Reading the card log (ADR-0001 seam 4), extracted from doc.js into
 * src/shared/cards.js.
 *
 * The `cards` table is an append-mostly log of version rows, so every read of
 * it has to collapse to one row per id — the newest — and then drop the ids
 * whose newest row is a deletion (ADR-0005 §1). Doing those in the other order
 * resurrects a deleted card from one of its own older rows.
 *
 * Two readers depended on that and neither did it: the ImmortalDB backup
 * deduped but kept deleted cards (CODE_REVIEW.md, ticket 28), and the
 * first-load activation filtered nothing at all and threw when it found no
 * root card (S8).
 */
import { expect, test } from "bun:test";

import { backupSnapshotText, rootCardId, visibleCards } from "../src/shared/cards";

interface Row {
  id: string;
  treeId?: string;
  parentId: string | null;
  content: string;
  position: number;
  deleted: number;
  updatedAt: string;
  synced?: boolean;
}

/** A version row. Stamps are `timestamp:counter:hash`, counters unpadded. */
function row(partial: Partial<Row> & { id: string; updatedAt: string }): Row {
  return {
    parentId: null,
    content: "",
    position: 0,
    deleted: 0,
    treeId: "tree1",
    ...partial,
  };
}

/* ===== visibleCards ===== */

test("one row per id, and it is the newest one", () => {
  const rows = [
    row({ id: "a", updatedAt: "100:0:x", content: "old" }),
    row({ id: "a", updatedAt: "100:10:x", content: "new" }),
    row({ id: "a", updatedAt: "100:9:x", content: "middle" }),
  ];

  expect(visibleCards(rows).map((c) => c.content)).toEqual(["new"]);
});

test("a card whose newest row is a deletion is gone, older rows included", () => {
  const rows = [
    row({ id: "a", updatedAt: "100:0:x", content: "kept" }),
    row({ id: "b", updatedAt: "100:1:x", content: "doomed" }),
    row({ id: "b", updatedAt: "200:0:y", content: "doomed", deleted: 1 }),
  ];

  expect(visibleCards(rows).map((c) => c.id)).toEqual(["a"]);
});

test("a card deleted and then re-added is back", () => {
  const rows = [
    row({ id: "a", updatedAt: "100:0:x", content: "first" }),
    row({ id: "a", updatedAt: "200:0:y", content: "first", deleted: 1 }),
    row({ id: "a", updatedAt: "300:0:z", content: "again" }),
  ];

  expect(visibleCards(rows).map((c) => c.content)).toEqual(["again"]);
});

test("no rows, no cards", () => {
  expect(visibleCards([])).toEqual([]);
});

/* ===== rootCardId ===== */

test("the root card is the first one by position, not by insertion order", () => {
  const rows = [
    row({ id: "second", updatedAt: "100:0:x", parentId: null, position: 2 }),
    row({ id: "first", updatedAt: "100:1:x", parentId: null, position: 1 }),
    row({ id: "child", updatedAt: "100:2:x", parentId: "first", position: 1 }),
  ];

  expect(rootCardId(rows)).toBe("first");
});

test("a deleted root card is not activated", () => {
  const rows = [
    row({ id: "gone", updatedAt: "100:0:x", parentId: null, position: 1 }),
    row({ id: "gone", updatedAt: "200:0:y", parentId: null, position: 1, deleted: 1 }),
    row({ id: "live", updatedAt: "100:1:x", parentId: null, position: 2 }),
  ];

  expect(rootCardId(rows)).toBe("live");
});

test("no root card is null, not a crash", () => {
  // Every root row deleted: what S8's `cards.filter(...)[0].id` threw on.
  const rows = [
    row({ id: "gone", updatedAt: "100:0:x", parentId: null }),
    row({ id: "gone", updatedAt: "200:0:y", parentId: null, deleted: 1 }),
    row({ id: "orphan", updatedAt: "100:1:x", parentId: "gone" }),
  ];

  expect(rootCardId(rows)).toBeNull();
  expect(rootCardId([])).toBeNull();
});

/* ===== backupSnapshotText ===== */

test("the backup holds the tree, in position order", () => {
  const rows = [
    row({ id: "root", updatedAt: "100:0:x", content: "Root", position: 1 }),
    row({ id: "kid2", updatedAt: "100:1:x", parentId: "root", content: "Two", position: 2 }),
    row({ id: "kid1", updatedAt: "100:2:x", parentId: "root", content: "One", position: 1 }),
  ];

  const text = backupSnapshotText(rows);

  expect(text).toContain('<gingko-card id="root">');
  expect(text.indexOf("One")).toBeLessThan(text.indexOf("Two"));
});

test("the backup excludes deleted cards and their children", () => {
  const rows = [
    row({ id: "root", updatedAt: "100:0:x", content: "Root" }),
    row({ id: "doomed", updatedAt: "100:1:x", parentId: "root", content: "Doomed" }),
    row({ id: "doomed", updatedAt: "200:0:y", parentId: "root", content: "Doomed", deleted: 1 }),
    row({ id: "orphan", updatedAt: "100:2:x", parentId: "doomed", content: "Orphan" }),
  ];

  const text = backupSnapshotText(rows);

  expect(text).toContain("Root");
  expect(text).not.toContain("Doomed");
  // A deleted card's subtree goes with it: `treeHelper` only ever descends
  // from cards that are in the snapshot, so an orphan cannot come back as a
  // root card either.
  expect(text).not.toContain("Orphan");
});

test("a stale pre-deletion row does not resurrect the card", () => {
  // Dedupe-then-drop vs drop-then-dedupe: filtering `deleted` per row first
  // leaves the older row of a deleted card as the newest survivor.
  const rows = [
    row({ id: "a", updatedAt: "100:0:x", content: "Older" }),
    row({ id: "a", updatedAt: "200:0:y", content: "Newer", deleted: 1 }),
  ];

  expect(backupSnapshotText(rows)).not.toContain("Older");
});

test("no cards is an empty backup, not a crash", () => {
  expect(backupSnapshotText([])).toBe("");
});
