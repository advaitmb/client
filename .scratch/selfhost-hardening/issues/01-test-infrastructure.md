# 01: Stand up test infrastructure and working CI

Part of `../map.md`. **Type:** task · **Status:** resolved

**Blocked by:** None (can start immediately).

**Covers:** CODE_REVIEW.md B1, B2, B3, B6 · Decisions: ADR-0001, ADR-0004.

**What to build:** A contributor (or agent) can run one command per layer and
get a real pass/fail signal, and every push to `selfhost` gets the same signal
from CI. This gates every other ticket: until it lands, fixes fly blind.

## Acceptance criteria

- [x] `elm-test` is set up with at least one meaningful test against the
      `Doc.Data` public API (ADR-0001 seam 1) that would fail if the behavior
      broke — not a placeholder assertion.
- [x] `bun test` is set up with a DOM environment and at least one meaningful
      test of a custom element's attribute→DOM contract (seam 3).
- [x] `package.json` has `test` (both layers) plus per-layer scripts.
- [x] `config-check.js` exits non-zero when config keys mismatch (B1), with a
      test or demonstrable repro in the ticket's Comments.
- [x] `.github/workflows/ci.yml` runs on push/PR to `selfhost`: install via
      Bun, build (`bun run newbuild` with `config.js` created from
      `config-example.js`), `elm-test`, `bun test`, config-check, and an npm
      lockfile consistency check (ADR-0004).
- [x] `build.yml` and `web-deploy.yml` are deleted (B2, B3); README badge
      updated or removed.
- [x] CI is green on `selfhost`.

## Answer

Landed in commit `cdd0901` on `selfhost`.

- **Elm** — `tests/DataTest.elm`: 3 tests at ADR-0001 seam 1, run with
  `bun run test:elm` (`elm-test` 0.19.1-revision12, pinned **exact** because
  bun resolves the `^0.19.1-revisionX` prerelease range to the ancient
  `0.19.1` stable). Tests: `localSave` of a `CTIns` stages one unsynced row
  with the position computed from its sibling; `localSave` of a `CTUpd` is
  based on the newest version row per card id (stale parentId/position must
  not leak); tree materialization via `publicDataDecoder` keeps only the
  newest version per id. Each asserts the decoded `DBChangeLists`/`Tree`
  against independent literals; failure verified by mutating an expected
  value (1 fail) and reverting (green).
- **TS/JS** — `bun test` (4+3 = 7 tests) with happy-dom registered globally
  via `tests/happydom.ts`, preloaded through `bunfig.toml`.
  `tests/markdown.test.ts` covers the `gw-markdown` attribute→DOM contract
  (seam 3): markdown rendering, re-render on `src` change, CriticMarkup
  `ins/del.diff`, and task checkboxes enabled + reporting
  `(card-id, 1-based index)` through `window.checkboxClicked`.
  `tests/config-check.test.ts` pins the B1 gate (see Comments).
- **Scripts** — `test` (both layers), `test:elm`, `test:ts`, `config-check`.
  `test:elm` uses `ELM_HOME=$PWD/elm-home/elm-stuff` (absolute — elm-test
  invokes the compiler from a generated project dir, so the relative form
  the build uses breaks there).
- **B1** — `config-check.js` now `process.exit(1)`s on any key diff.
- **CI** — `.github/workflows/ci.yml` (workflow name: **CI**, job: “Build
  and test”), on push + pull_request to `selfhost`: `bun install
  --frozen-lockfile`, npm-lockfile consistency check
  (`npm install --package-lock-only` + `git diff --exit-code`, ADR-0004),
  `config.js` from `config-example.js`, config-check, `bun run newbuild`,
  `elm-test`, `bun test`. `build.yml` and `web-deploy.yml` deleted (B2/B3);
  README badge now points at CI on `advaitmb/client` (branch `selfhost`).
  First run green: <https://github.com/advaitmb/client/actions/runs/33055786479>.
- Both lockfiles regenerated in sync (`bun.lockb` + `package-lock.json`);
  `trustedDependencies: ["elm"]` so the elm binary's postinstall runs under
  bun's script blocking.

Local totals: elm-test 3/3, bun test 7/7 across 2 files.

## Comments

- **B1 repro** (config-check must fail on mismatch), run at repo root:

  ```
  $ cp config-example.js config.js && node config-check.js; echo $?
  0
  $ sed 's/SUPPORT_URGENT_EMAIL/RENAMED_KEY/' config-example.js > config.js
  $ node config-check.js; echo $?
  Difference in config keys: ["SUPPORT_URGENT_EMAIL","RENAMED_KEY"]
  1
  ```

  Before the fix the second command printed the diff but exited 0.
  `tests/config-check.test.ts` keeps all three cases (match / missing key /
  extra key) under `bun test`.
- happy-dom drove `gw-markdown` fully (including checkbox `click()`
  dispatch), so no element needed the “most valuable contract only”
  fallback.
- TS tests live under `tests/` rather than next to the elements because
  `src/ui/tsconfig.json` includes `./**/*.ts` and its strict typecheck
  (via the server checkout) has no `bun:test` types.
