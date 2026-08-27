/**
 * <gw-save-indicator> (ADR-0001 seam 3): what the document header and the
 * fullscreen view both say about whether the work is safe.
 *
 * There used to be two of these — `Doc.UI.viewSaveIndicator` in Elm (fullscreen)
 * and a copy inside `header.ts` — and they had already drifted: the copy had no
 * "Database Error..." branch at all, and it called the first moments of a
 * document load "Saved Offline" rather than "Loading..." (CODE_REVIEW.md S1).
 * One element renders both surfaces now, and these pin every branch of it so a
 * future fix cannot be needed twice.
 */
import { afterEach, expect, test } from "bun:test";
import "../src/ui/save-indicator";

const NOW = 1_700_000_100_000;
const A_MINUTE_AGO = NOW - 60_000;

type Save = {
  dirty: boolean;
  lastLocalSave: number | null;
  lastRemoteSave: number | null;
  now: number;
};

function mount(save: Partial<Save> | null): HTMLElement {
  const el = document.createElement("gw-save-indicator");
  el.id = "save-indicator";
  if (save !== null) {
    el.setAttribute(
      "save",
      JSON.stringify({
        dirty: false,
        lastLocalSave: null,
        lastRemoteSave: null,
        now: NOW,
        ...save,
      }),
    );
  }
  document.body.appendChild(el);
  return el;
}

const label = (el: HTMLElement) => el.querySelector("span")!.textContent;
const tip = (el: HTMLElement) => el.querySelector("span")!.getAttribute("title");

afterEach(() => {
  document.body.replaceChildren();
});

test("a document being edited says its changes are unsaved", () => {
  const el = mount({ dirty: true, lastLocalSave: A_MINUTE_AGO, lastRemoteSave: A_MINUTE_AGO });

  expect(label(el)).toBe("Unsaved Changes...");
  expect(el.className).toContain("unsaved");
  expect(el.className).toContain("saving");
  expect(tip(el)).toBe("Last saved 1 minute ago");
});

test("a document with nothing saved anywhere is still loading", () => {
  const el = mount({ lastLocalSave: null, lastRemoteSave: null });

  expect(label(el)).toBe("Loading...");
  expect(el.className).toContain("never-saved");
});

test("the zero timestamp of a document still loading is not an offline save", () => {
  // The initial-load case the TS copy dropped: Elm reads a `lastLocalSave` of
  // epoch 0 as "no save has happened yet", because that is what an unset
  // timestamp decodes to. Calling it "Saved Offline" told the user their work
  // was somewhere it was not.
  const el = mount({ lastLocalSave: 0, lastRemoteSave: null });

  expect(label(el)).toBe("Loading...");
  expect(el.className).toContain("never-saved");
});

test("a real local save with nothing synced is saved offline", () => {
  const el = mount({ lastLocalSave: A_MINUTE_AGO, lastRemoteSave: null });

  expect(label(el)).toBe("Saved Offline");
  expect(el.className).toContain("saved-offline");
  expect(tip(el)).toBe("Last synced 1 minute ago");
});

test("a local save the server has already acknowledged is synced", () => {
  const el = mount({ lastLocalSave: A_MINUTE_AGO, lastRemoteSave: NOW });

  expect(label(el)).toBe("Synced");
  expect(el.className).toContain("synced");
  expect(tip(el)).toBe("Last edit 1 minute ago");
});

test("a local save newer than the last sync is saved offline", () => {
  const el = mount({ lastLocalSave: NOW, lastRemoteSave: A_MINUTE_AGO });

  expect(label(el)).toBe("Saved Offline");
  expect(el.className).toContain("saved-offline");
  expect(tip(el)).toBe("Last synced 1 minute ago");
});

test("a sync with no local save at all is a database error", () => {
  // The branch the TS copy dropped entirely: the server has the document but
  // this browser's own database has no record of saving it.
  const el = mount({ lastLocalSave: null, lastRemoteSave: A_MINUTE_AGO });

  expect(label(el)).toBe("Database Error...");
  expect(el.className).toContain("database-error");
  expect(tip(el)).toBe("Last synced 1 minute ago");
});

test("no save state yet renders nothing rather than a wrong state", () => {
  const el = mount(null);

  expect(el.querySelector("span")).toBeNull();
  expect(el.className).toBe("");
});

test("the state is replaced, not appended to, on every tick", () => {
  const el = mount({ dirty: true, lastLocalSave: A_MINUTE_AGO, lastRemoteSave: A_MINUTE_AGO });

  el.setAttribute(
    "save",
    JSON.stringify({
      dirty: false,
      lastLocalSave: A_MINUTE_AGO,
      lastRemoteSave: NOW,
      now: NOW,
    }),
  );

  expect(el.querySelectorAll("span").length).toBe(1);
  expect(label(el)).toBe("Synced");
  expect(el.className).not.toContain("saving");
});
