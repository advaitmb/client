# 01: Stand up test infrastructure and working CI

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** None (can start immediately).

**Covers:** CODE_REVIEW.md B1, B2, B3, B6 · Decisions: ADR-0001, ADR-0004.

**What to build:** A contributor (or agent) can run one command per layer and
get a real pass/fail signal, and every push to `selfhost` gets the same signal
from CI. This gates every other ticket: until it lands, fixes fly blind.

## Acceptance criteria

- [ ] `elm-test` is set up with at least one meaningful test against the
      `Doc.Data` public API (ADR-0001 seam 1) that would fail if the behavior
      broke — not a placeholder assertion.
- [ ] `bun test` is set up with a DOM environment and at least one meaningful
      test of a custom element's attribute→DOM contract (seam 3).
- [ ] `package.json` has `test` (both layers) plus per-layer scripts.
- [ ] `config-check.js` exits non-zero when config keys mismatch (B1), with a
      test or demonstrable repro in the ticket's Comments.
- [ ] `.github/workflows/ci.yml` runs on push/PR to `selfhost`: install via
      Bun, build (`bun run newbuild` with `config.js` created from
      `config-example.js`), `elm-test`, `bun test`, config-check, and an npm
      lockfile consistency check (ADR-0004).
- [ ] `build.yml` and `web-deploy.yml` are deleted (B2, B3); README badge
      updated or removed.
- [ ] CI is green on `selfhost`.
