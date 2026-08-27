# 22: Dead code purge — JS/TS and port contract

Part of `../map.md`. **Type:** task · **Status:** needs-info

**Blocked by:** 03 · **Owner decision:** questionnaire Q "dead-code purge
scope". Default if unanswered: full purge.

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

## Acceptance criteria

- [ ] All §6 JS/TS items removed or justified in Comments; coordinate with
      04 and 16 (don't delete what they just wired up).
- [ ] `src/ui/README.md` rewritten to match reality.
- [ ] Bundle builds; full test suite green.
