/**
 * The one invariant of `mountModal`'s markup that only a layout engine
 * enforces: a modal's own controls have to receive clicks.
 *
 * `mountModal` (src/ui/modal.ts) nests every modal inside `.max-width-grid`,
 * which is `pointer-events: none` so the document behind it stays clickable.
 * `pointer-events` inherits, so `.modal` has to opt back in — without that
 * rule every control in every modal is pointer-transparent and the click
 * lands on `.modal-overlay`, whose only handler closes the modal (ticket 37).
 *
 * jsdom resolves no cascade and hit-tests no point, so this reads the
 * stylesheet the app actually ships instead of the rendered DOM.
 */

import { test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const css = readFileSync(join(import.meta.dir, "..", "src", "static", "style.css"), "utf8")
  // Comments out, or a declaration quoted in one counts as a declaration —
  // and the comment on the rule under test quotes both other values.
  .replace(/\/\*[\s\S]*?\*\//g, "");

/** The declarations of the last rule whose selector list is exactly `selector`. */
function rule(selector: string): string {
  const blocks = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].filter(
    (m) => m[1].trim().replace(/\s+/g, " ") === selector,
  );
  expect(blocks.length, `no rule for "${selector}" in style.css`).toBeGreaterThan(0);
  return blocks[blocks.length - 1][2];
}

/** The value of `pointer-events` in a declaration block, or null if unset. */
function pointerEvents(declarations: string): string | null {
  const decls = [...declarations.matchAll(/pointer-events\s*:\s*([a-z-]+)/g)];
  return decls.length ? decls[decls.length - 1][1] : null;
}

test("the modal wrapper is pointer-transparent, so the app behind a modal stays clickable", () => {
  expect(pointerEvents(rule(".max-width-grid"))).toBe("none");
});

test("a modal opts back into pointer events, so its own controls are clickable", () => {
  const value = pointerEvents(rule(".modal"));
  expect(value, ".modal must re-enable pointer events its wrapper turned off").not.toBeNull();
  expect(["auto", "all"]).toContain(value!);
});

test("the overlay behind a modal receives clicks, so clicking outside closes it", () => {
  // Unset is fine here: the overlay is not inside .max-width-grid, so it
  // inherits the document's own `auto`.
  expect(pointerEvents(rule(".modal-overlay"))).not.toBe("none");
});
