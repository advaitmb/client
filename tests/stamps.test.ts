import { describe, expect, test } from "bun:test";

import {
  compareStamps,
  computeCheckpoint,
  maxStamp,
  newestVersionPerId,
} from "../src/shared/stamps.js";

// Stamps ("timestamp:counter:hash", CONTEXT.md) are minted with an UNPADDED
// counter, so string order disagrees with clock order as soon as a counter
// reaches two digits — which a single multi-card save does.
describe("compareStamps", () => {
  test("a higher counter in the same millisecond is newer, even with fewer digits", () => {
    const ninth = "1755000000000:9:aaa";
    const tenth = "1755000000000:10:bbb";

    expect(compareStamps(tenth, ninth)).toBeGreaterThan(0);
    expect(compareStamps(ninth, tenth)).toBeLessThan(0);
  });

  test("stamps sharing a millisecond and a counter are ordered by hash", () => {
    const fromOneClient = "1755000000000:3:aaa";
    const fromAnother = "1755000000000:3:bbb";

    expect(compareStamps(fromAnother, fromOneClient)).toBeGreaterThan(0);
    expect(compareStamps(fromOneClient, fromAnother)).toBeLessThan(0);
  });

  test("the later millisecond wins however high the earlier counter got", () => {
    const lateInTheOldMillisecond = "1755000000000:99:zzz";
    const firstOfTheNewMillisecond = "1755000000001:0:aaa";

    expect(compareStamps(firstOfTheNewMillisecond, lateInTheOldMillisecond)).toBeGreaterThan(0);
    expect(compareStamps(lateInTheOldMillisecond, firstOfTheNewMillisecond)).toBeLessThan(0);
  });

  // Elm encodes `UpdatedAt.zero` as "0" (not "0:0:"), and that is also the
  // checkpoint sent for a document with nothing synced yet.
  test("the zero stamp '0' is older than any minted stamp", () => {
    expect(compareStamps("0", "1755000000000:0:aaa")).toBeLessThan(0);
    expect(compareStamps("1755000000000:0:aaa", "0")).toBeGreaterThan(0);
    expect(compareStamps("0", "0")).toBe(0);
  });

  // Rows come straight out of Dexie, so the comparator has to stay a total
  // order even for a stamp it cannot parse — and such a row must never be
  // mistaken for the newest one.
  test("an unparseable stamp is older than every real stamp", () => {
    expect(compareStamps("garbage", "0")).toBeLessThan(0);
    expect(compareStamps("0", "garbage")).toBeGreaterThan(0);
    expect(compareStamps("garbage", "garbage")).toBe(0);
  });
});

// doc.js feeds this the stamps the server acked (`pushOk`) back into the HLC.
describe("maxStamp", () => {
  test("picks the highest counter minted in a millisecond, not the highest string", () => {
    const oneSaveWorthOfStamps = [
      "1755000000000:8:aaa",
      "1755000000000:10:bbb",
      "1755000000000:9:ccc",
    ];

    expect(maxStamp(oneSaveWorthOfStamps)).toBe("1755000000000:10:bbb");
  });
});

// The checkpoint (`chk`) sent with a pull is the newest stamp this client has
// already got from the server. Too low and the server re-sends rows we have.
describe("computeCheckpoint", () => {
  const CLIENT_HASH = "ph6oyrqzgpbo";

  // One save of a 12-card document mints 12 stamps inside one millisecond,
  // counter 0..11 — the last three of them two digits wide.
  const twelveCardSave = Array.from({ length: 12 }, (_unused, i) => ({
    id: `card-${i}`,
    treeId: "tree-1",
    updatedAt: `1755000000123:${i}:${CLIENT_HASH}`,
    synced: true,
  }));

  const rows = [
    { id: "card-0", treeId: "tree-1", updatedAt: `1755000000000:0:${CLIENT_HASH}`, synced: true },
    { id: "card-1", treeId: "tree-1", updatedAt: `1755000000000:1:${CLIENT_HASH}`, synced: true },
    ...twelveCardSave,
    // Local edits since that save: not yet acked, so not part of the checkpoint.
    { id: "card-3", treeId: "tree-1", updatedAt: `1755000000456:0:${CLIENT_HASH}`, synced: false },
    { id: "card-4", treeId: "tree-1", updatedAt: `1755000000456:1:${CLIENT_HASH}`, synced: false },
  ];

  test("is the newest synced stamp of a multi-card save", () => {
    expect(computeCheckpoint(rows)).toBe(`1755000000123:11:${CLIENT_HASH}`);
  });

  test("is the zero stamp when the document has nothing synced yet", () => {
    expect(computeCheckpoint(rows.filter(row => !row.synced))).toBe("0");
    expect(computeCheckpoint([])).toBe("0");
  });
});

// The ImmortalDB backup is built from the newest version row per card id.
describe("newestVersionPerId", () => {
  test("keeps the newest row per card, counter width and all", () => {
    const versionRows = [
      { id: "card-a", updatedAt: "1755000000000:9:ph6oyrqzgpbo", content: "ninth edit" },
      { id: "card-a", updatedAt: "1755000000000:10:ph6oyrqzgpbo", content: "tenth edit" },
      { id: "card-b", updatedAt: "1755000000000:1:ph6oyrqzgpbo", content: "only edit" },
    ];

    const kept = Object.fromEntries(newestVersionPerId(versionRows).map(row => [row.id, row.content]));

    expect(kept).toEqual({ "card-a": "tenth edit", "card-b": "only edit" });
  });
});
