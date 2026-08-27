# 02: Sanitize all rendered card markdown (stored XSS)

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C1 · Decision: ADR-0003.

**What to build:** A card containing hostile markup (e.g.
`<img src=x onerror=alert(1)>`, `javascript:` links) renders inert everywhere
card content is displayed — tree cards, fullscreen, export preview — while
CriticMarkup (`<ins>`/`<del>`) and task-list checkboxes keep working.

## Acceptance criteria

- [x] DOMPurify (or equivalent) with the ADR-0003 allowlist wraps every
      `innerHTML` assignment of markdown-derived HTML, defined once and shared.
- [x] Tests: script/event-handler/`javascript:`-URL payloads are neutralized;
      `ins`/`del` and checkbox inputs survive; checkbox click plumbing still
      fires.
- [x] Export preview path uses the same sanitizer.
- [x] Bundle builds and CI is green.

## Answer

- **The sanitizer** — `src/ui/markdown.ts` gains `renderMarkdown(src)`:
  `preprocess` → `marked.parse` → `DOMPurify.sanitize(html, ALLOWLIST)`, and
  `<gw-markdown>`'s `holder.innerHTML = renderMarkdown(src)` is the only
  assignment of markdown-derived HTML in the tree. `grep -rn innerHTML src/`
  returns exactly that one line; `insertAdjacentHTML`, `outerHTML =` and
  `document.write` return nothing.
- **One allowlist, spelled out** — `ALLOWLIST` is an explicit
  `ALLOWED_TAGS`/`ALLOWED_ATTR` pair rather than DOMPurify's defaults, which
  keep `<style>`, the `style` attribute and the whole SVG/MathML profile.
  Tags: the prose/markdown set plus `ins`, `del`, `input`. Attributes:
  `href src alt title target rel` (DOMPurify's URI check rejects
  `javascript:` on all three URL attributes), `type checked disabled` for the
  task-list checkboxes, and `class align colspan rowspan span start width
  height lang dir` for presentation. Deliberately absent: `style` (CSS
  injection) and `id`/`name` (DOM clobbering). `class` is load-bearing —
  `preprocess()` emits `<ins class='diff'>` and marked emits
  `class="language-…"` on fenced code.
- **Export preview** — `Page/Doc/Export.elm:173` (the DOCX preview) and
  `Page/Doc.elm:2360` (the cards) both render `node "gw-markdown"`, so they
  share the sanitizer by construction; there is no second render path to
  wire up. The non-DOCX export branch uses Elm's `text`, which escapes.
- **Tests** — `tests/markdown.test.ts` grows from 4 to 9, still at ADR-0001
  seam 3 (attributes in → DOM out): script tags stripped, `onerror`/`onclick`
  stripped while the harmless `img`/`b` survive, `javascript:` neutralized in
  both a markdown link and a raw `<a href="jAvAsCrIpT:…">` while the link text
  survives, `style`/`iframe` removed, and "ordinary markdown output survives
  sanitizing" (h1, link href, img src, code) as the regression guard. Ticket
  01's 4 originals — including the `window.checkboxClicked` plumbing, which
  needs `input`, `type` and the enable step to all survive — stay green
  untouched.
- **Test DOM swapped happy-dom → jsdom** — happy-dom cannot run DOMPurify at
  all (details in Comments): it mangles legitimate markup and passes hostile
  markup, so the harness could not tell a working sanitizer from a missing
  one. `tests/happydom.ts` is replaced by `tests/dom.ts`
  (jsdom + a global registrator, with the reasoning in the file header),
  `bunfig.toml` points at it, and `@happy-dom/global-registrator` gives way
  to `jsdom` in devDependencies.
- **Dependency** — `dompurify: ^3.4.14` in `dependencies` (it ships in the
  browser bundle; `web/ui.js` contains it after `newbuild`). Both lockfiles
  regenerated in sync: `bun install --frozen-lockfile` is a no-op and
  `npm install --package-lock-only --ignore-scripts` leaves
  `package-lock.json` unchanged, so both CI gates pass.

Local totals for this ticket alone: `bun test` 9 + 3 = **12/12** (was 7/7),
`bun run test:elm` **3/3**, `bun run newbuild` exit 0, `node config-check.js`
exit 0 with `config.js` copied from `config-example.js`. After rebasing onto
tickets 03 and 07: `bun test` **19/19** across 3 files (ticket 07's 7
`gw-textarea` tests pass unchanged under jsdom) and `bun run test:elm`
**7/7**.

Landed as `89a98bc` on `selfhost`. CI green:
<https://github.com/advaitmb/client/actions/runs/33064509422>.

## Comments

- **happy-dom cannot exercise DOMPurify**, which is why the harness moved to
  jsdom. Two independent fidelity gaps, both found by watching the new tests
  fail *after* the sanitizer was in place:
  1. `Node.prototype.nodeName` returns `''` in happy-dom
     (`nodes/node/Node.js:161`); the real name lives on an
     `Element.prototype` override (`nodes/element/Element.js:261`). DOMPurify
     reads `nodeName` through the `Node.prototype` getter deliberately, so a
     DOM-clobbering child named `nodeName` cannot shadow it — so every element
     looked nameless, hence disallowed. Observed:
     `DOMPurify.sanitize("<h1>A title</h1>")` → `"A title"`.
  2. happy-dom's `NodeIterator` is a thin `TreeWalker` wrapper with no
     pre-removing steps, so detaching the current node ends the iteration.
     DOMPurify removes as it walks, so sanitizing stopped at the first
     offending node. Observed with (1) patched:
     `"<p>ok</p><script>x</script><img src=x onerror=alert(1)>"` →
     `"<p></p><script>x</script><img src=\"x\" onerror=\"alert(1)\">"`.

  Neither is patchable from the outside without reimplementing browser
  pre-removal semantics, and 20.11.8 is the latest happy-dom. jsdom
  implements both to spec and runs the `gw-markdown` custom element and the
  checkbox `click()` dispatch identically. Cost: preload boots in ~0.7 s
  instead of ~0.2 s, and the global registration is hand-rolled (~15 lines)
  because jsdom ships no equivalent of `@happy-dom/global-registrator`.
- **Red-before-green was verified twice.** First against the pre-fix module
  (4 of the 5 new tests fail; "ordinary markdown survives" passes, as a
  guard should). Then again after the swap to jsdom, by replacing the
  `DOMPurify.sanitize` call with `return html` — the same 4 fail, the other 8
  stay green. So the hostile tests are driven by the sanitizer and not by the
  DOM engine.
- **Nothing legitimate is lost to the allowlist.** Checked
  `marked.parse(src)` against `renderMarkdown(src)` for GFM tables (the
  `align` attribute marked emits survives, so alignment is kept), `<ol
  start>`, fenced code, blockquotes, nested lists, task lists, images, links,
  `data:` image URIs, `<details>/<summary>`, `hr`, strikethrough and
  CriticMarkup. The only diffs were re-serialization (`&` → `&amp;` inside an
  autolink href) and the CriticMarkup rewrite itself.
- **`data:` URIs on `<img src>` are kept** — DOMPurify allows them for
  `DATA_URI_TAGS` and browsers do not execute script in an SVG loaded through
  `<img>`, so embedded images keep working.
- **`target`/`rel` stay allowed.** marked never emits them, but a card may
  hand-write `<a target="_blank">` and had it before this change; current
  browsers imply `noopener` for `target=_blank`, so the tabnabbing risk that
  would justify dropping it is gone.
- **`renderMarkdown` is exported with no external caller today.** Deliberate,
  per ADR-0003's "defined once and shared": a future path that needs the HTML
  without the element gets the allowlist by construction instead of having to
  remember a sanitize call.
- `docs/CODE_REVIEW.md` is left as the 2026-08-27 snapshot it says it is —
  same convention ticket 01 followed for B1/B2/B3/B6.
