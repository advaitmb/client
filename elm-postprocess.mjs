import config from "./config.js";

/*
 * Self-host: upstream loaded 25 i18n JSON files here and substituted
 * `%zh_hans:Key%`-style placeholders into the optimised elm.js at build time.
 * Translation.elm is English-only now, so those placeholders no longer exist
 * and the i18n/ directory is gone. Only the config substitutions remain.
 */

const replacements = [
  { search: "{%SUPPORT_EMAIL%}", replace: config.SUPPORT_EMAIL },
  { search: "{%SUPPORT_URGENT_EMAIL%}", replace: config.SUPPORT_URGENT_EMAIL },
  { search: "{%HOMEPAGE_URL%}", replace: config.HOMEPAGE_URL },
].filter((r) => typeof r.replace === "string");

/**
 * Substitutes the build-time config placeholders in every compilation mode.
 * Upstream did this only under `--optimize`, so any non-optimize build showed
 * raw `{%SUPPORT_EMAIL%}` / `{%HOMEPAGE_URL%}` in the UI (CODE_REVIEW.md B13).
 *
 * @type {import("elm-watch/elm-watch-node").Postprocess}
 */
export default function postprocess({ code }) {
  for (const r of replacements) {
    code = code.replaceAll(r.search, r.replace);
  }
  return code;
}
