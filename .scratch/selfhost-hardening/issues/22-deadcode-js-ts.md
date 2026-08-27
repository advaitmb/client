# 22: Dead code purge — JS/TS and port contract

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 03 · **Owner decided (2026-08-27):** full purge.

**Covers:** CODE_REVIEW.md §6 (JS/TS side): JS handlers with no Elm sender
(`InitBeamer`, `SocketSend`, `SaveCardBasedMigration`, `UpdateCommits`), dead
JS→Elm senders (`pushSuccessHandler` and the dead `SavedRemotely` Elm branch,
`userLoggedOutMsg` — mind ticket 04, which makes logout real), dead
custom-element contract ends (`gw-drag-start`/`gw-drag-end`, sidebar
`context-target`), dead JS (`PULL_LOCK`, `savedObjectIds`, `userDbName`,
`treeToHtml`, PouchDB-era `container-web.js` exports, elm-dnd `DragStart`
path both sides, `window.elmMessages`), and stale `src/ui/README.md` (S11).

**What to build:** The port dispatch table and custom-element contracts
contain only live ends; `src/ui/README.md` describes the actual state of the
migration.

**Added scope (from ticket 20's resolution):** the repo-root `build/`
directory (Electron packaging resources, zero references after B11);
producerless CSS in `src/static/style.css` — `#migrate-modal` /
`#migrate-bugs-modal` (no producers despite the old comment), `#fullscreen-button`
(live element is plural), `#help-dropdown`, `#language-menu*` — plus
`src/static/styles/github.css`; `package.json`'s `repository`/`bugs`/
`homepage` still pointing at `gingko/client`; `docs/images/
how-to-clone-address.png` (last referrer removed); the stale "send … to
Sentry" comment in doc.js. Verify zero references before each deletion, as
ticket 20 did.

**Added scope (from ticket 17's resolution):** `src/ui/README.md` documents
a `tsc` typecheck gate that does not exist (no tsconfig at root, nothing in
ci.yml) — when rewriting the README, either add a real `tsc --strict` check
to CI (it would have caught a field shadowing `HTMLElement.prototype.title`
that tests could not) or stop claiming it. Also: the theme write ring
(`ThemeChanged`, `SaveThemeSetting`, `Theme.toValue`) currently has no
producer — do NOT remove it without checking the owner's pending decision on
restoring the theme picker (see ticket 17's Comments).

**Added scope (from ticket 21's resolution):** the four doc.js handler
halves whose Elm senders ticket 21 just removed can no longer fire — and
matter more than usual because ticket 18's dispatch policy TOASTS an unknown
incoming tag rather than ignoring it. See ticket 21's Comments for the list.

## Acceptance criteria

- [ ] All §6 JS/TS items removed or justified in Comments; coordinate with
      04 and 16 (don't delete what they just wired up).
- [ ] `src/ui/README.md` rewritten to match reality.
- [ ] Bundle builds; full test suite green.
