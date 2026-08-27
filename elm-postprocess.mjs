import config from "./config.js";

/*
 * Self-host: upstream loaded 25 i18n JSON files here and substituted
 * `%zh_hans:Key%`-style placeholders into the optimised elm.js at build time.
 * Translation.elm is English-only now, so those placeholders no longer exist
 * and the i18n/ directory is gone. Only the config substitutions remain.
 */

/** The `config.js` key behind each placeholder Elm embeds. */
const PLACEHOLDERS = {
  "{%SUPPORT_EMAIL%}": "SUPPORT_EMAIL",
  "{%SUPPORT_URGENT_EMAIL%}": "SUPPORT_URGENT_EMAIL",
  "{%HOMEPAGE_URL%}": "HOMEPAGE_URL",
};

/**
 * Replaces every build-time placeholder in `code` with its value from `conf`.
 * A placeholder whose key is missing (or not a string) is left as-is rather
 * than stringified into the bundle.
 *
 * @param {string} code
 * @param {Record<string, unknown>} conf
 * @returns {string}
 */
export function substitutePlaceholders(code, conf) {
  for (const [placeholder, key] of Object.entries(PLACEHOLDERS)) {
    const value = conf[key];
    if (typeof value === "string") {
      code = code.replaceAll(placeholder, value);
    }
  }
  return code;
}

/**
 * Substitutes in every compilation mode. Upstream did it only under
 * `--optimize`, so any non-optimize build showed raw `{%SUPPORT_EMAIL%}` /
 * `{%HOMEPAGE_URL%}` in the UI (CODE_REVIEW.md B13).
 *
 * @type {import("elm-watch/elm-watch-node").Postprocess}
 */
export default function postprocess({ code }) {
  return substitutePlaceholders(code, config);
}
