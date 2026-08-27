# 20: Build scripts and docs match reality

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** 01

**Covers:** CODE_REVIEW.md B4, B5, B7, B8, B9, B10, B11, B12, B13 ·
Decision: ADR-0004.

**What to build:** A newcomer following the README can build and run the fork,
and the repo carries no upstream-SaaS/Electron residue: README/CONTRIBUTING
describe real commands (no `newwatch`, no CouchDB, no `npm run electron`);
`esbuild.mjs` fails legibly (or works) under Node and drops its dead
error branch; the encrypted `client.config.js.gpg` + `config_decrypt.sh` go;
`database-download.html` stops loading unpinned unpkg scripts (vendor or pin
+ SRI); dead Electron-era static files no longer ship to the deploy root;
phantom `@playwright/test` and stale `.gitignore` entries go, tracked
`.DS_Store` files are removed and ignored; the electron-builder block,
orphaned scripts, and stale `.vscode` configs go; Tailwind `content` scans
`src/ui/**/*.ts`; `elm-watch.json` target is named, and dev builds don't show
raw `{%SUPPORT_EMAIL%}` placeholders.

**Added scope (from ticket 03's resolution):** `src/static/style.css` still
carries the dead payments-modal selectors (`#upgrade-*`, `#pwyw*`,
`#price-*`, `.payment-button`, the `flash-2` keyframes — ~170 lines,
interleaved with live `#migrate-modal` rules). Remove them with the other
static residue; the producers were deleted in ticket 03.

**Added scope (from ticket 04's resolution):** `#account-menu` CSS in
`src/static/style.css` is dead (the menu was removed; logout now lives in the
sidebar rail) — remove with the payments CSS.

## Acceptance criteria

- [x] `bun run newbuild` still produces a working `web/` (CI proves it).
- [x] README quickstart verified end-to-end in a clean clone.
- [x] Each B-item above done or explicitly deferred with a reason in
      Comments.
- [x] CI green.

## Answer

CI green on selfhost: run 33067220874 (`0dbed69`, the B4–B13 code and docs)
and run 33069054218 (`671ac3c`, the review follow-ups + tracker).

Every B-item is **done**; nothing deferred. The build is no longer Bun-only,
no page reaches for a CDN, and the docs describe commands that exist.

**B4 — docs.** README rewritten around a quickstart that was re-run from
`git clean -xdf`: `git clone -b selfhost`, `cp config-example.js config.js`,
`bun i`, `bun run newbuild`, then serve `web/` as the **document root** of
gingko/server (the client is same-origin — `/login`, `/signup`, `/logout`,
`/me`, `/sync`, `/ws`, images, docx export, templates — so a separate static
host does not work). Gone: `bun run newwatch` (never existed), the CouchDB and
SQLite prerequisites, the upstream desktop-branch download, the poeditor
translation project (Translation.elm is English-only). CONTRIBUTING rewritten
for this fork: the four layers, Bun + regenerate-both-lockfiles, the
`.scratch/` tracker, branch off and target `selfhost`, ADR-0001's seams, and
the standing invariants a PR gets sent back for. ARCHITECTURE §2/§3/§8 and
CLAUDE.md re-synced with what this ticket changed — §8 still claimed the
branch had no CI and no tests.

**B5 — Bun-only build.** `esbuild.mjs` derives its root from
`path.dirname(fileURLToPath(import.meta.url))`; `node esbuild.mjs` now exits 0
where it used to die with an opaque AliasPlugin error. Bun stays canonical
(ADR-0004). The `result.errors` branch is deleted rather than fixed —
`esbuild.build()` rejects on failure, so it was unreachable.

**B7** — `client.config.js.gpg` + `config_decrypt.sh` deleted; the only
reference was inside the script itself.

**B8 — unpkg.** Vendored, not pinned+SRI: the page's whole point is that it
handles the user's entire local database, and `index.html`'s "no external
request" property should hold for it too. `dexie-export-import@^1.0.3` (the
line that peers with our dexie 3) joins `dependencies`, the page logic moves
to `src/web/database-download.js`, and esbuild gained a third entry point
→ `web/database-download.js`. Verified: the minified bundle carries
`prototype.export=`, `Dexie.prototype.export` is a function once the addon
loads, and zero `unpkg` strings remain in the built page.

**B9** — the 13 Electron-era static files deleted after confirming each is
unreferenced from `src/` and from the remaining static HTML (`modal.css`'s
only referrer was `license.html`, deleted in the same commit). `web/` now
contains only live assets.

**B10** — `@playwright/test` removed (both lockfiles regenerated; CI's
sync check passes on the committed state). Stale ignores pruned: cypress,
`app/*` + its two negations, `src/migration/*`, `src/legacy-import/*`, the
playwright report/results dirs, and `hidden-config.js` (its only reader,
`web-deploy.yml`, went in ticket 01). The three tracked `.DS_Store` files are
untracked and `.DS_Store` is ignored.

**B11** — the electron-builder `"build"` block and the orphaned `minifyjs`
script are out of `package.json`; `.vscode/launch.json` is deleted (both its
configurations were dead — `app\electron.js` and `${workspaceFolder}\--watch`)
and `elm.makeCommand` (Elm 0.18-era `elm-make`) is out of `settings.json`,
keeping the still-valid `elm.compiler` and format-on-save.

**B12** — tailwind `content` adds `./src/ui/**/*.ts`. Verified the delta: it
generates three extra utilities (`.inline`, `.flex-row`, `.shadow`, +366
bytes) from words appearing in TS comments. None changes rendering — the app's
own `.flex-row` and `.shadow` rules come later in the sheet and win, and the
only `.shadow` element is `visibility: hidden` anyway.

**B13** — `elm-watch.json`'s target is `app`; `elm-postprocess.mjs`
substitutes in every compilation mode. Live placeholders that were affected:
`{%HOMEPAGE_URL%}` in Login.elm/Signup.elm. Covered by 7 tests.

**Added scope (ticket 03)** — the payments CSS is gone from
`src/static/style.css`: `#upgrade-*`, `#pwyw*`, `#price-*`, `.payment-button`,
the `flash-2` keyframes, the `#upgrade-button` rule inside the mobile media
query, and — same removed ring, same zero references — `span.trial`/
`span.trial-light|medium|dark` and `.toggle-caret` (pwyw's caret). ~230 lines.
The interleaved `#migrate-modal` rules are untouched.

**Added scope (ticket 04)** — `#account-menu`, `#account-menu::after` and
`#account-dropdown` removed (also zero references).

## Comments

**On `#migrate-modal`.** The ticket describes it as live; it is not — it has no
producer in `src/` either (nor does `#migrate-bugs-modal`). Left in place: it
is outside this ticket's enumerated scope and the migration UI is a separate
question from the payments ring. A dead-CSS sweep should take it, along with
`#fullscreen-button` (the live element is `#fullscreen-buttons`, plural),
`#help-dropdown`, `#language-menu*`, and `src/static/styles/github.css` (an
unreferenced highlight.js theme; no `hljs` call sites remain). All verified
zero-reference, none deleted here.

**`build/` is left in place.** After B11 removed the electron-builder block,
nothing references `build/entitlements.mac.plist`, `build/scripts/notarize.js`,
`build/icon.ic{ns,o}` or `build/sources/*` — it is pure Electron-packaging
residue. Not deleted: CODE_REVIEW.md is meticulous about naming dead files and
does not list these, so the omission reads as deliberate. Only
`build/.DS_Store` went, under B10. Worth a follow-up decision.

**`?keyPrefix=` dropped from database-download.** Its branch passed
`filter: filterFn` and `filterFn` was never defined — anywhere, in any commit
of this repo's history. The path always threw `ReferenceError`, so moving the
code into a module meant either preserving a guaranteed crash or removing it;
removed. The final progress line also claimed the file was named
`gingko-writer-<db>-export.json` when it is `gingko-writer-db-<db>-export.json`;
corrected. The page is browser-only (needs real IndexedDB), so it was verified
by bundle inspection rather than end-to-end.

**New test seam, ADR-0001 amended.** `tests/postprocess.test.ts` does not sit
at any of the four pre-agreed seams — and neither does ticket 01's
`tests/config-check.test.ts`. ADR-0001 says a test outside the list requires
amending it, so seam 6 (build-time gates) is now recorded (seam 5 went to
ticket 13 while this ticket was in flight), and
`elm-postprocess.mjs` follows that seam's rule: the decision is a pure
`substitutePlaceholders(code, conf)` and the elm-watch entry point is a
one-liner over it, so substitution is tested against a fabricated config
rather than whatever `config.js` holds.

**The clean-clone quickstart needs one more step in a cloud session.**
From `git clean -xdf`, `bun i` + `bun run newbuild` gets as far as `elm make`
and then hangs forever: Elm 0.19 fetches package source as GitHub *zipballs*
and this proxy rejects them (`scripts/install_elm_pkgs.sh` exists precisely
for that, cloning instead). Nothing outside the SessionStart hook mentioned
it, so the quickstart looked broken rather than blocked — the README now says
so. After running that script once, the same `bun run newbuild` completed and
produced a `web/` whose `index.html` references all resolve
(`elm.js` 228 KB, `doc.js` 288 KB, `ui.js` 97 KB, `style.css` 88 KB, plus
`theme.css`, `desktop-fonts.css`, fonts, templates, `database-download.*`);
all four bundles parse under `node --check`. `bun run config-check` exits 0,
15 elm-test and 47 bun test pass.

**Not in scope, noticed.** `package.json`'s `repository`/`bugs`/`homepage`
still point at `gingko/client` and `productName` is an electron-builder-era
field; `docs/images/how-to-clone-address.png` lost its last referrer when
CONTRIBUTING was rewritten. `src/shared/doc.js` still carries a
"send encrypted unsynced local cards to Sentry" comment above code that only
`console.warn`s (Sentry itself is gone) — a §6 dead-code item, ticket 22's.
