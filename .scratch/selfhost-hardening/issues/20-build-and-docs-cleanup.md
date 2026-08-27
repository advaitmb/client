# 20: Build scripts and docs match reality

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

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

## Acceptance criteria

- [ ] `bun run newbuild` still produces a working `web/` (CI proves it).
- [ ] README quickstart verified end-to-end in a clean clone.
- [ ] Each B-item above done or explicitly deferred with a reason in
      Comments.
- [ ] CI green.
