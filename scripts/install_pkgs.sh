#!/bin/bash
# Dependency install for Claude Code cloud sessions.
#
# This belongs in a SessionStart hook rather than the environment's setup
# script: the setup script runs BEFORE the repository is cloned, so an
# `npm i` there runs in the home directory and fails with ENOENT on
# package.json. The hook runs after the clone, from the repo root.
#
# Local sessions skip it -- CLAUDE_CODE_REMOTE is only ever "true" in a
# cloud VM -- so this never touches an existing local node_modules.

if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR" || exit 0

# npm, not bun: bun is present in cloud sessions but its package fetching
# goes through a proxy it does not handle. Bun is still the canonical
# runtime (ADR-0004), so use `bun run newbuild` and `bun test` once the
# dependencies are on disk -- and remember that a package.json change has
# to be mirrored into bun.lockb, which CI checks.
npm install --no-fund --no-audit || true

# Elm packages can't be downloaded by the elm compiler here (the proxy
# rejects GitHub zipball requests), so pre-install them from git clones.
bash scripts/install_elm_pkgs.sh || true

exit 0
