![](./docs/images/screenshot-alien-screenplay.png)

# Gingko Writer — selfhost fork [![CI](https://github.com/advaitmb/client/actions/workflows/ci.yml/badge.svg?branch=selfhost)](https://github.com/advaitmb/client/actions/workflows/ci.yml)

Writing software to help organize and draft complex documents: anything from
novels and screenplays to legal briefs and graduate theses. Documents are trees
of **cards**, rendered as columns.

This is the `selfhost` branch — a fork of
[gingko/client](https://github.com/gingko/client) stripped of the hosted-SaaS
machinery (no payments, no trial, no analytics, no external CDN requests) so it
can be run on your own server. The companion server is
[gingko/server](https://github.com/gingko/server); this repository builds only
the browser client.

## Quickstart

You need [Bun](https://bun.sh) (the canonical runtime for this repo — see
[ADR-0004](./docs/adr/0004-bun-canonical-runtime.md)) and a checkout of
[gingko/server](https://github.com/gingko/server) to serve the result.

```bash
git clone -b selfhost https://github.com/advaitmb/client.git
cd client

cp config-example.js config.js   # then edit the four values in it
bun i
bun run newbuild
```

(The repository's default branch is still upstream's abandoned `master`, hence
the `-b selfhost`.)

`config.js` is gitignored and holds four values (`HOMEPAGE_URL`,
`SUPPORT_EMAIL`, `SUPPORT_URGENT_EMAIL`, `LEGACY_URL`). It is baked into the
bundle at build time, so **edit it before building** — and rebuild after any
change. `bun run config-check` verifies your `config.js` has exactly the keys
`config-example.js` declares.

The build writes the whole deployable site to `web/` (gitignored):
`index.html`, `elm.js`, `doc.js`, `ui.js`, `style.css`, `theme.css`,
`database-download.{html,js}`, fonts, and `templates/`.

If `newbuild` stalls at `elm make`, your network is blocking Elm 0.19's package
downloads (it fetches GitHub *zipballs*, which some proxies reject). Run
`bash scripts/install_elm_pkgs.sh` once to populate the repo-local package
cache from plain `git clone`s, then re-run `bun run newbuild`.

### Serving it

`web/` is a static directory, but it is not standalone: the client makes
**same-origin** requests for authentication (`/login`, `/signup`, `/logout`),
the optional session probe (`/me`), document sync (`/sync` and the `/ws`
WebSocket),
image upload, docx export, and the starter templates. So `web/` has to be
served as the document root of
[gingko/server](https://github.com/gingko/server) (follow that repo's README
for the server itself) — not from a separate static host. The full port and
endpoint contract is in [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md).

Then open the address the server prints (`http://localhost:3000` by default).

There is no watch/dev script on this branch: re-run `bun run newbuild` after a
change.

## Tests

```bash
bun run test         # both suites
bun run test:elm     # elm-test, src/elm
bun run test:ts      # bun test, src/ui + src/shared
```

CI (`.github/workflows/ci.yml`) runs the build and both suites on every push to
`selfhost`.

## Documentation

| File | Contents |
|---|---|
| [CONTEXT.md](./CONTEXT.md) | Domain glossary — the vocabulary used in code, issues and tests |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | Full system description, including the build pipeline |
| [docs/adr/](./docs/adr/) | Architecture decision records |
| [docs/CODE_REVIEW.md](./docs/CODE_REVIEW.md) | Catalog of known bugs and dead code |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to work on this fork |

## License

MIT — see [LICENSE](./LICENSE). Original work by Gingko Inc.
