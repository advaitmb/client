/*
 * Support utility behind `web/database-download.html`: dumps every IndexedDB
 * database this origin holds to a JSON file the user can attach to a bug
 * report.
 *
 * Self-host: this used to be an inline <script> in the HTML that pulled
 * `dexie` and `dexie-export-import` from unpkg with no version and no SRI
 * (CODE_REVIEW.md B8) — an external CDN request in the one page whose job is
 * exporting the user's entire local database. Both libraries are now
 * dependencies, bundled into `web/database-download.js` by `esbuild.mjs`, so
 * the page makes no external request (like `index.html`).
 */
import Dexie from "dexie";
// Side-effect import: the addon extends Dexie.prototype.export globally.
import "dexie-export-import";

function addInfo(infoText) {
  const li = document.createElement("li");
  li.innerText = infoText;
  document.getElementById("info").appendChild(li);
}

function progressCallback({ totalRows, completedRows }) {
  document.getElementById("downloadProgress").style.display = "block";
  document.getElementById("currentRows").innerText = completedRows;
  document.getElementById("totalRows").innerText = totalRows;
  const progressBar = document.getElementById("progress-bar");
  progressBar.setAttribute("max", totalRows);
  progressBar.setAttribute("value", completedRows);
}

async function singleDbDownload(dbName) {
  // Open once to learn the live schema, then reopen declaring it: the export
  // addon needs the tables registered on the Dexie instance it exports from.
  let db = new Dexie(dbName);
  const { verno, tables } = await db.open();
  db.close();

  db = new Dexie(dbName);
  db.version(verno).stores(
    tables.reduce((stores, table) => {
      stores[table.name] = table.schema.primKey.keyPath || "";
      return stores;
    }, {}),
  );

  addInfo("Downloading from " + dbName);
  const blob = await db.export({
    numRowsPerChunk: 2,
    prettyJson: true,
    progressCallback,
  });
  addInfo("Database export complete... starting download...");

  const a = document.createElement("a");
  document.body.appendChild(a);
  const url = window.URL.createObjectURL(blob);
  a.href = url;
  a.download = `gingko-writer-db-${dbName}-export.json`;
  a.click();
  window.URL.revokeObjectURL(url);
  addInfo(
    `Download should be complete. Look for "gingko-writer-db-${dbName}-export.json" in your file system`,
  );
}

async function downloadDb() {
  const dbs = await indexedDB.databases();
  const dbNames = dbs.map((x) => x.name).filter((name) => !!name);
  if (dbNames.length === 0) {
    addInfo("No databases found.");
    return;
  }
  addInfo("Databases: " + dbNames);
  for (const dbName of dbNames) {
    await singleDbDownload(dbName);
  }
}

downloadDb().catch((err) => {
  addInfo("Export failed: " + (err && err.message ? err.message : err));
});
