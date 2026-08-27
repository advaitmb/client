# Contributing

This is the `selfhost` fork of [gingko/client](https://github.com/gingko/client):
the browser client with the hosted-SaaS machinery removed so it can be run on
your own server. Contributions are welcome — the notes below are what you need
to know that isn't obvious from the code.

If something here is wrong, confusing, or unclear, that's a bug in this file.
Please say so.

## Read first

| File | Why |
|---|---|
| [CONTEXT.md](./CONTEXT.md) | The domain glossary. Use these words — "card", "version row", "stamp", "tree" — in code, commits and issues |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | How the four layers fit together, and the build pipeline |
| [docs/adr/](./docs/adr/) | Decisions already made (and why). Don't re-litigate them in a PR; open an ADR |
| [docs/CODE_REVIEW.md](./docs/CODE_REVIEW.md) | The verified catalog of known bugs and dead code |

The app has four layers, and which one your change belongs in is usually the
first question:

- `src/elm/` — the Elm core. Owns all state and document logic.
- `src/shared/doc.js` — the JS port layer: Dexie/IndexedDB persistence, the
  WebSocket sync protocol, localStorage.
- `src/ui/` — framework-less TypeScript custom elements (`gw-tree`,
  `gw-header`, modals, …). Its own rules are in `src/ui/README.md`.
- `src/static/` — `index.html`, CSS, fonts, templates; copied verbatim to `web/`.

## Getting set up

You need [Bun](https://bun.sh). Bun is the canonical package manager, script
runner and test runner for this repo ([ADR-0004](./docs/adr/0004-bun-canonical-runtime.md));
`bun.lockb` is the lockfile of record. `package-lock.json` is kept in sync only
because some agent sessions install with npm, and CI enforces that it matches
`package.json` — so if you touch `package.json`, regenerate **both**:

```bash
bun install
npm install --package-lock-only
```

To build and test:

```bash
cp config-example.js config.js   # gitignored; four values, baked into the bundle
bun i
bun run newbuild                 # writes the deployable site to web/
bun run test                     # elm-test + bun test
```

See the [README](./README.md#serving-it) for how to actually serve `web/`
behind [gingko/server](https://github.com/gingko/server). There is no
watch/dev script on this branch — re-run `bun run newbuild`.

## The process

1. **Pick something.** Issues live as markdown files under `.scratch/`, not on
   GitHub — GitHub Issues are disabled on this repository. See
   [docs/agents/issue-tracker.md](./docs/agents/issue-tracker.md) for the
   conventions and [docs/agents/triage-labels.md](./docs/agents/triage-labels.md)
   for the status vocabulary.

2. **Fork and clone.** Click "Fork" at the top right, then:

   ![GitHub Fork Button](./docs/images/how-to-fork.png)

   ```bash
   git clone git@github.com:{YOUR_USERNAME}/client.git
   cd client
   git checkout selfhost
   git checkout -b name-of-your-feature-or-bugfix
   ```

   Branch off **`selfhost`**, and target `selfhost` with your pull request.
   `master` is upstream's abandoned line on this fork — don't push to it.

3. **Open a pull request early**, before the work is finished. It's the place
   to have the conversation about a proposed change, not just to deliver one.

4. **Write the test first** where there's a seam for one. The three pre-agreed
   testing seams are listed in
   [ADR-0001](./docs/adr/0001-testing-stack-and-seams.md): the `Doc.Data`
   public API (Elm, pure), extracted pure helpers of `doc.js`, and custom
   elements (attribute-in → DOM/`CustomEvent`-out). Elm tests go in `tests/*.elm`,
   TS/JS tests in `tests/*.test.ts`.

5. **Keep commits small and self-contained**, and make sure `bun run test` and
   `bun run newbuild` both pass before pushing. CI runs exactly those on every
   push to `selfhost`.

## Things that will get a PR sent back

- **Unsanitized HTML.** Every path from markdown to `innerHTML` goes through
  `renderMarkdown()` in `src/ui/markdown.ts`
  ([ADR-0003](./docs/adr/0003-sanitize-rendered-markdown.md)). There is exactly
  one allowlist; don't add a second route.
- **Scanning version rows without deduplicating by id.** The `cards` table is
  an append-mostly log: a card is the *newest version row per id*. Any scan
  that ignores that is a bug ([ADR-0005](./docs/adr/0005-sync-semantics-corrections.md)).
- **Comparing stamps as strings.** Stamps are `"timestamp:counter:hash"` and
  are ordered numerically — use `src/shared/stamps.js` / `UpdatedAt.elm`.
- **Re-introducing the payments/trial ring** or any external CDN request.
  Both were removed deliberately
  ([ADR-0002](./docs/adr/0002-remove-trial-and-payments.md)); `index.html`
  makes no external request by design.
- **Elm→JS tag drift.** Outgoing tag names in `Outgoing.elm` and the handler
  names in `doc.js`'s dispatch table must match exactly; a typo fails silently.
