/**
 * Adopting the server's account on boot (ADR-0001 seam 4), extracted from
 * doc.js's auto-login into src/shared/session.js so it can be exercised
 * without a server or a browser session.
 *
 * Self-host has no login screen: doc.js asks `/me` on boot and merges the
 * answer into the stored session blob that Elm's flags are decoded from. The
 * preferences in that blob are written by the client alone (Elm's
 * `SaveUserSetting` / `SetSidebarState` reach localStorage and stop there —
 * nothing pushes them to the server), so `/me` answering with whatever
 * defaults the account was created with must not reset them. This is the Elm
 * login decoder's E3 problem on the path self-host actually takes.
 */
import { expect, test } from "bun:test";

import { mergeUserIntoSession } from "../src/shared/session";

/** What the client has stored: a user who closed the shortcut tray, sorts
 * alphabetically, closed the sidebar and had a document open. */
const stored = {
  email: "user@example.com",
  shortcutTrayOpen: false,
  sortBy: "Alphabetical",
  sidebarOpen: false,
  lastDocId: "tree-abc",
};

test("a /me answer does not reset preferences the client has already stored", () => {
  const merged = mergeUserIntoSession(stored, {
    email: "user@example.com",
    shortcutTrayOpen: true,
    sortBy: "ModifiedAt",
    sidebarOpen: true,
    lastDocId: null,
  });

  expect(merged).toEqual(stored);
});

test("a /me answer fills in preferences the client has never stored", () => {
  const merged = mergeUserIntoSession(
    { email: "user@example.com" },
    { email: "user@example.com", shortcutTrayOpen: true, sortBy: "CreatedAt" },
  );

  expect(merged.shortcutTrayOpen).toBe(true);
  expect(merged.sortBy).toBe("CreatedAt");
});

test("everything else the server says is adopted", () => {
  const merged = mergeUserIntoSession(
    { email: "old@example.com", confirmedAt: null },
    { email: "user@example.com", confirmedAt: 1700000000000 },
  );

  expect(merged.email).toBe("user@example.com");
  expect(merged.confirmedAt).toBe(1700000000000);
});

test("a first boot with nothing stored keeps what the server sent", () => {
  const merged = mergeUserIntoSession(null, { email: "user@example.com" });

  expect(merged).toEqual({ email: "user@example.com" });
});
