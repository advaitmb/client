# Gingko Writer Client — selfhost fork

A tree-structured writing app: an Elm core (`src/elm/`), a JS port layer
(`src/shared/doc.js`) owning persistence (Dexie/IndexedDB) and WebSocket sync,
and a TypeScript custom-element interface layer (`src/ui/`). Companion server:
[gingko/server](https://github.com/gingko/server).

Read `CONTEXT.md` for domain vocabulary and `docs/ARCHITECTURE.md` for the full
system description before making non-trivial changes. `docs/CODE_REVIEW.md` is
the verified catalog of known bugs and dead code; the tickets under
`.scratch/selfhost-hardening/issues/` are derived from it.

## Development

- Development branch: `selfhost`. Do not push to `master`.
- Build: `bun i && bun run newbuild`. Output goes to `web/`. Bun is canonical
  (ADR-0004), but the build scripts avoid Bun-only APIs.
- `config.js` is gitignored; create it from `config-example.js` before building.
- Any `package.json` change: regenerate **both** lockfiles (`bun install` and
  `npm install --package-lock-only`) — CI fails if they drift (ADR-0004).
- Tests: `bun run test` (`test:elm` = elm-test for `src/elm`, `test:ts` =
  `bun test` for `src/ui` + `src/shared` + the build seams).

## Agent skills

### Issue tracker

Local markdown tracker: tickets live under `.scratch/<feature>/issues/`
(GitHub Issues are disabled on this repo). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the repo root, ADRs in `docs/adr/`. See
`docs/agents/domain.md`.
