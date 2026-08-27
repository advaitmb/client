/**
 * <gw-help-modal>'s chrome (ADR-0001 seam 3) — CODE_REVIEW.md S13.
 *
 * The element hand-rolled the overlay, header and close button that
 * `modal.ts`'s `mountModal` exists to provide, down to its own copy of the
 * close icon's path data. What that costs is drift: the shared chrome is what
 * keeps every modal closing the same way, and Elm listens for exactly one
 * event. So this pins the chrome rather than the shortcut tables: the modal
 * renders inside the shared wrapper, and both ways of dismissing it reach Elm
 * as one `gw-close`.
 */
import { afterEach, expect, test } from "bun:test";
import "../src/ui/help-modal";

function mount(platform = "other"): [HTMLElement, string[]] {
  const el = document.createElement("gw-help-modal");
  el.setAttribute("platform", platform);
  document.body.append(el);

  const closed: string[] = [];
  el.addEventListener("gw-close", () => closed.push("gw-close"));
  return [el, closed];
}

afterEach(() => {
  document.body.replaceChildren();
});

test("the shortcuts sit inside the shared modal chrome", () => {
  const [el] = mount();

  expect(el.querySelector(".modal-overlay")).not.toBeNull();
  expect(el.querySelector(".modal.help-modal")).not.toBeNull();
  expect(el.querySelector(".modal-header h2")?.textContent).toBe("Help");
  expect(el.querySelector(".modal-guts #shortcut-main-title")).not.toBeNull();
});

test("the close button reports one gw-close", () => {
  const [el, closed] = mount();

  el.querySelector<HTMLElement>(".close-button")!.click();

  expect(closed).toEqual(["gw-close"]);
});

test("clicking the overlay reports one gw-close", () => {
  const [el, closed] = mount();

  el.querySelector<HTMLElement>(".modal-overlay")!.click();

  expect(closed).toEqual(["gw-close"]);
});

test("the platform decides which modifier keys are shown", () => {
  const [mac] = mount("mac");
  expect(mac.textContent).toContain("⌘");
  expect(mac.textContent).not.toContain("Ctrl");

  document.body.replaceChildren();

  const [other] = mount("other");
  expect(other.textContent).toContain("Ctrl");
  expect(other.textContent).not.toContain("⌘");
});
