/**
 * <gw-sidebar>'s logout control (ADR-0001 seam 3).
 *
 * The rail is the only place a self-hosted user can end their session:
 * CODE_REVIEW.md C3 — the account menu that used to host logout was removed
 * and nothing replaced it, so `LogoutRequested` had no producer at all.
 *
 * Elm listens for `gw-logout` on the element and turns it into
 * LogoutRequested → Session.logout → the `LogoutUser` port message, so what
 * this pins is the element's half of that chain: a click on the control
 * reaches Elm as exactly one `gw-logout` and nothing else (the rail's own
 * click handler toggles the document list, so a control that lets the click
 * through would log out *and* open the list), it is reachable in the
 * collapsed rail (the default state), and the loading state leaves it inert
 * like every other sidebar button.
 */
import { afterEach, expect, test } from "bun:test";
import "../src/ui/sidebar";

/** Every event the element reported, in order. */
const SIDEBAR_EVENTS = [
  "gw-logout",
  "gw-sidebar-toggle",
  "gw-new",
  "gw-switcher",
  "gw-filter",
  "gw-sort",
  "gw-context",
];

function mount(attrs: Record<string, string> = {}): [HTMLElement, string[]] {
  const el = document.createElement("gw-sidebar");
  for (const [name, value] of Object.entries({ docs: "[]", ...attrs })) {
    el.setAttribute(name, value);
  }
  document.body.appendChild(el);

  const reported: string[] = [];
  for (const name of SIDEBAR_EVENTS) {
    el.addEventListener(name, () => reported.push(name));
  }
  return [el, reported];
}

const logoutControl = (el: HTMLElement) =>
  el.querySelector<HTMLElement>("#logout-icon");

afterEach(() => {
  document.body.replaceChildren();
});

test("the rail offers a logout control", () => {
  const [el] = mount({ open: "yes" });

  // #logout-icon is what style.css places at the bottom of the rail, where
  // the removed account menu used to sit.
  expect(logoutControl(el)?.getAttribute("title")).toBe("Log out");
});

test("clicking logout reports exactly one gw-logout and nothing else", () => {
  const [el, reported] = mount({ open: "yes" });

  logoutControl(el)?.click();

  expect(reported).toEqual(["gw-logout"]);
});

test("logout is reachable while the document list is collapsed", () => {
  const [el, reported] = mount();

  logoutControl(el)?.click();

  expect(reported).toEqual(["gw-logout"]);
});

test("the loading state leaves logout inert", () => {
  const [el, reported] = mount({ open: "yes", static: "" });

  logoutControl(el)?.click();

  expect(reported).toEqual([]);
});

test("the logo is addressed from the site root, not from the current route", () => {
  // `cp -r src/static/. web/` puts it at the root (package.json's newbuild), so
  // that is where it is asked for. A relative `../gingko-leaf-logo.svg`
  // resolves against whatever route the rail is rendered on
  // (CODE_REVIEW.md S13).
  const [el] = mount();

  expect(el.querySelector("#brand img")?.getAttribute("src")).toBe("/gingko-leaf-logo.svg");
});
