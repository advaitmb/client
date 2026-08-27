/**
 * bun test preload (see bunfig.toml): registers a jsdom window, document,
 * customElements etc. as globals so custom elements can be exercised through
 * real DOM APIs (ADR-0001 seam 3).
 *
 * WHY JSDOM AND NOT HAPPY-DOM
 *
 * This started as happy-dom (`tests/happydom.ts`, ticket 01), which cannot run
 * DOMPurify — the sanitizer every card render goes through since ADR-0003. Two
 * independent fidelity gaps, both load-bearing:
 *
 *   1. `Node.prototype.nodeName` returns `''` in happy-dom; the real name
 *      lives on an `Element.prototype` override. DOMPurify reads nodeName
 *      through the `Node.prototype` getter on purpose (a DOM-clobbering child
 *      named "nodeName" must not be able to shadow it), so every element
 *      looked nameless and therefore disallowed — sanitizing `<h1>hi</h1>`
 *      returned `hi`.
 *   2. happy-dom's `NodeIterator` is a thin `TreeWalker` wrapper with no
 *      pre-removing steps, so detaching the current node ends the iteration.
 *      DOMPurify removes as it walks, so sanitizing stopped at the first
 *      offending node and left everything after it untouched.
 *
 * Together those mangle legitimate markup and pass hostile markup, so the
 * harness could not tell a working sanitizer from a missing one. jsdom
 * implements both to spec. It boots slower; correctness of the security gate
 * wins.
 *
 * ONE DOCUMENT, SHARED (sometimes)
 *
 * Whether this preload runs once for the whole run or once per test file is
 * the runner's business, and it has changed between Bun versions: bun 1.3.14
 * (CI) shares this document -- and its `customElements` registry -- across
 * every test file, while 1.3.11 does not. So a test must not assume it has the
 * DOM to itself: clear `document.body` in a `beforeEach`, take document-level
 * listeners off again, and never build a fixture out of a tag some other file
 * defines as a custom element. `<gw-tree>` replaces its children with its own
 * scaffolding when it connects, and a fixture that borrowed the tag name was
 * silently dismantled in CI and nowhere else (ticket 16).
 */
import { JSDOM } from "jsdom";

const { window } = new JSDOM("<!doctype html><html><body></body></html>", {
  url: "http://localhost/",
  pretendToBeVisual: true,
});

/**
 * Globals to leave as the runner's. Everything else is taken from jsdom,
 * because the DOM interfaces have to arrive as one set: jsdom brand-checks its
 * arguments, so a Bun `CustomEvent` handed to a jsdom `dispatchEvent` is
 * rejected.
 */
const RUNNER_OWNED = new Set([
  // Bun's, or the runner loses its output and its module loading.
  "console", "globalThis", "process", "require", "module", "exports", "Bun",
  // Platform primitives Bun already implements. jsdom's own internals reach
  // for these through the global, so replacing them can recurse.
  "performance", "crypto", "URL", "URLSearchParams", "TextEncoder",
  "TextDecoder", "queueMicrotask",
  // Timers: jsdom's are tied to its event loop. requestAnimationFrame still
  // comes from jsdom, via pretendToBeVisual above.
  "setTimeout", "clearTimeout", "setInterval", "clearInterval",
]);

for (const key of Object.getOwnPropertyNames(window)) {
  if (RUNNER_OWNED.has(key)) continue;
  const descriptor = Object.getOwnPropertyDescriptor(window, key);
  if (!descriptor) continue;
  try {
    Object.defineProperty(globalThis, key, { ...descriptor, configurable: true });
  } catch {
    // A handful of Bun globals are non-configurable; none of them are DOM.
  }
}
