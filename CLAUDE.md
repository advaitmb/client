# Gingko Writer Client — selfhost fork

A tree-structured writing app: an Elm core (`src/elm/`), a JS port layer
(`src/shared/doc.js`) owning persistence (Dexie/IndexedDB) and WebSocket sync,
and a TypeScript custom-element interface layer (`src/ui/`). Companion server:
[gingko/server](https://github.com/gingko/server).

Read `CONTEXT.md` for domain vocabulary and `docs/ARCHITECTURE.md` for the full
system description before making non-trivial changes. `docs/CODE_REVIEW.md` is
the verified catalog of known bugs and dead code; the open GitHub issues are
derived from it.

## Development

- Development branch: `selfhost`. Do not push to `master`.
- Build: `bun i && bun run newbuild` (Bun-only; `esbuild.mjs` uses
  `import.meta.dir`). Output goes to `web/`.
- `config.js` is gitignored; create it from `config-example.js` before building.
- Tests: see `package.json` scripts (`elm-test` for `src/elm`, `bun test` for
  `src/ui` + `src/shared`). If these don't exist yet, issue #2 (test
  infrastructure) hasn't landed — land it before TDD work.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `advaitmb/client`. See
`docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the repo root, ADRs in `docs/adr/`. See
`docs/agents/domain.md`.
