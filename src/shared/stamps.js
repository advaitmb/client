// Stamp ordering — the JS mirror of Elm's `UpdatedAt` (src/elm/UpdatedAt.elm),
// and the pure sync helpers built on it (ADR-0001 seam 2).
//
// A stamp is a hybrid-logical-clock value `"timestamp:counter:hash"` whose
// counter is UNPADDED, so string order is NOT clock order: one multi-card save
// mints many stamps inside a single millisecond, and `…:10:x` sorts before
// `…:9:y` as a string. Order stamps through `compareStamps`, never with `<`,
// a bare `.sort()` or `_.max` (CODE_REVIEW.md D7, ADR-0005 §3).

// Elm encodes `UpdatedAt.zero` as the bare "0", which is also the checkpoint
// for a document with nothing synced yet.
const ZERO_STAMP = "0";

// Total order over stamps: numeric timestamp, then numeric counter, then hash.
// Negative if `a` is older than `b`, positive if it is newer, 0 if they are
// the same stamp.
export function compareStamps(a, b) {
  const pa = parseStamp(a);
  const pb = parseStamp(b);
  // A stamp that cannot be parsed is not a clock reading at all: order it
  // below every real stamp (so it never wins a max) while keeping the
  // comparator a total order, which Array.prototype.sort requires.
  if (pa === null || pb === null) {
    if (pa === null && pb === null) return compareRawStrings(a, b);
    return pa === null ? -1 : 1;
  }
  if (pa.timestamp !== pb.timestamp) return pa.timestamp - pb.timestamp;
  if (pa.counter !== pb.counter) return pa.counter - pb.counter;
  // Elm breaks the tie with `compare : String -> String -> Order`, which is
  // code-unit order — the same order JS `<` gives.
  return pa.hash < pb.hash ? -1 : pa.hash > pb.hash ? 1 : 0;
}

// The newest of `stamps`, or undefined for an empty list (Elm:
// `UpdatedAt.maximum : List UpdatedAt -> Maybe UpdatedAt`).
export function maxStamp(stamps) {
  return stamps.reduce(
    (newest, stamp) => (newest === undefined || compareStamps(stamp, newest) > 0 ? stamp : newest),
    undefined
  );
}

// The pull checkpoint (`chk`) for a document's version rows: the newest stamp
// the server has already acked, or the zero stamp when nothing is synced yet.
// Too low a checkpoint makes the server re-send rows we already have.
export function computeCheckpoint(rows) {
  const syncedStamps = rows.filter(row => row.synced).map(row => row.updatedAt);
  return maxStamp(syncedStamps) ?? ZERO_STAMP;
}

// One version row per card id — the newest one — newest card first. The
// `cards` table is an append-mostly log, so this is the only legal view of it
// (CONTEXT.md, ADR-0005 §1).
export function newestVersionPerId(rows) {
  const newestFirst = [...rows].sort((a, b) => compareStamps(b.updatedAt, a.updatedAt));
  const seen = new Set();
  return newestFirst.filter(row => {
    if (seen.has(row.id)) return false;
    seen.add(row.id);
    return true;
  });
}

/* === Private === */

function parseStamp(stamp) {
  const raw = String(stamp);
  if (raw === ZERO_STAMP) return { timestamp: 0, counter: 0, hash: "" };
  const parts = raw.split(":");
  if (parts.length !== 3) return null;
  const [timestamp, counter, hash] = parts;
  // Elm's `String.toInt` is this strict: digits with an optional sign, no
  // decimals, no exponents, no surrounding whitespace.
  if (!/^[+-]?\d+$/.test(timestamp) || !/^[+-]?\d+$/.test(counter)) return null;
  return { timestamp: Number(timestamp), counter: Number(counter), hash };
}

function compareRawStrings(a, b) {
  const [ra, rb] = [String(a), String(b)];
  return ra < rb ? -1 : ra > rb ? 1 : 0;
}
