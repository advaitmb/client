#!/bin/bash
# Populate the Elm package cache from git clones.
#
# Elm 0.19.1 downloads package source as GitHub zipballs over HTTPS
# (github.com/<pkg>/zipball/<version>/), which the cloud session's
# network proxy rejects -- only repositories attached to the session get
# HTTP access. Plain `git clone` of public GitHub repos IS allowed, so
# this pre-installs every package pinned in elm.json straight into the
# cache that the build uses (ELM_HOME=elm-home/elm-stuff, see the
# newbuild script). With every package present, `elm make` never tries
# to download source. The registry index (registry.dat) still comes from
# package.elm-lang.org, which the proxy allows.
#
# Idempotent: a package whose src/ directory already exists is skipped.

cd "$(dirname "$0")/.." || exit 1

CACHE="elm-home/elm-stuff/0.19.1/packages"
mkdir -p "$CACHE"

fetch_pkg() {
  pkg="$1"
  ver="$2"
  dest="$CACHE/$pkg/$ver"
  [ -d "$dest/src" ] && return 0
  tmp="$(mktemp -d)" || return 1
  if git clone --quiet --depth 1 --branch "$ver" \
      "https://github.com/$pkg.git" "$tmp" 2>/dev/null; then
    rm -rf "$tmp/.git"
    mkdir -p "$dest"
    cp -a "$tmp/." "$dest/"
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  echo "install_elm_pkgs: failed to fetch $pkg $ver" >&2
  return 1
}
export -f fetch_pkg
export CACHE

# elm.json for an application pins the full transitive set: direct,
# indirect, and test dependencies.
node -e '
  const e = require("./elm.json");
  const all = Object.assign({},
    e.dependencies.direct, e.dependencies.indirect,
    e["test-dependencies"].direct, e["test-dependencies"].indirect);
  for (const [pkg, ver] of Object.entries(all)) console.log(pkg, ver);
' | xargs -P 8 -n 2 bash -c 'fetch_pkg "$@"' _

exit 0
