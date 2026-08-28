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

/**
 * The probe itself: what the client concludes from the answer to `/me`.
 *
 * A self-hosted server need not implement it. gingko/server master does not:
 * its last route is `app.get('*')`, which serves the app's own index.html, so
 * `/me` answers 200 with HTML. The old code read `res.ok` as "this is an
 * account" and let `res.json()` throw, which put
 * `auto-login failed SyntaxError: Unexpected token '<'` on the console of
 * every boot of a working install (ticket 38). "OK" is not "JSON".
 */
import { fetchAccount } from "../src/shared/session";

/** A `fetch` that answers once with the given status, content type and body. */
function answering(
  status: number,
  contentType: string,
  body: string,
): (url: string) => Promise<Response> {
  return async () =>
    ({
      status,
      ok: status >= 200 && status < 300,
      headers: { get: (h: string) => (h.toLowerCase() === "content-type" ? contentType : null) },
      json: async () => JSON.parse(body),
    }) as unknown as Response;
}

test("a JSON account is adopted", async () => {
  const probe = await fetchAccount(
    answering(200, "application/json; charset=utf-8", '{"email":"user@example.com"}'),
  );
  expect(probe).toEqual({ status: "account", account: { email: "user@example.com" } });
});

test("a server without /me serves its index.html, which is not an account", async () => {
  const probe = await fetchAccount(
    answering(200, "text/html; charset=UTF-8", "<!DOCTYPE html><html></html>"),
  );
  expect(probe).toEqual({ status: "no-endpoint" });
});

test("404 is a server without /me too", async () => {
  expect(await fetchAccount(answering(404, "text/html", "Not Found"))).toEqual({
    status: "no-endpoint",
  });
});

test("401 is a server with /me that says nobody is logged in", async () => {
  expect(await fetchAccount(answering(401, "application/json", "{}"))).toEqual({
    status: "no-session",
  });
});

test("a 500 is worth reporting, with the status in the reason", async () => {
  const probe = await fetchAccount(answering(500, "text/html", "oops"));
  expect(probe.status).toBe("unavailable");
  expect(probe.reason).toContain("500");
});

test("JSON that does not parse is reported, not thrown", async () => {
  const probe = await fetchAccount(answering(200, "application/json", "{not json"));
  expect(probe.status).toBe("unavailable");
  expect(probe.reason).toBeTruthy();
});

test("a body that parses to something that is not an account is reported", async () => {
  const probe = await fetchAccount(answering(200, "application/json", '"a string"'));
  expect(probe.status).toBe("unavailable");
});

test("an unreachable server is reported, not thrown", async () => {
  const probe = await fetchAccount(async () => {
    throw new TypeError("Failed to fetch");
  });
  expect(probe.status).toBe("unavailable");
  expect(probe.reason).toContain("Failed to fetch");
});

test("a missing content-type is not read as JSON", async () => {
  const probe = await fetchAccount(async () =>
    ({ status: 200, ok: true, headers: { get: () => null }, json: async () => ({}) }) as unknown as Response,
  );
  expect(probe).toEqual({ status: "no-endpoint" });
});
