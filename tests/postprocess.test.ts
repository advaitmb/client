/**
 * elm-postprocess.mjs substitutes the build-time config placeholders into the
 * compiled elm.js. Upstream did it only under `--optimize`, so any
 * non-optimize build shipped raw `{%SUPPORT_EMAIL%}` / `{%HOMEPAGE_URL%}`
 * strings into the UI (CODE_REVIEW.md B13).
 *
 * Substitution itself is tested through the pure `substitutePlaceholders(code,
 * conf)` export, against a fabricated config rather than whatever config.js
 * happens to hold. The last three cases exercise the elm-watch entry point
 * itself, since the compilationMode guard was the actual bug; those need a
 * config.js on disk, as the build does.
 */
import { expect, test } from "bun:test";
import postprocess, { substitutePlaceholders } from "../elm-postprocess.mjs";

const conf = {
  HOMEPAGE_URL: "https://my-gingko.example.com",
  SUPPORT_EMAIL: "me@example.com",
  SUPPORT_URGENT_EMAIL: "urgent@example.com",
  LEGACY_URL: "https://legacy.example.com",
};

const sample = [
  `var support = '{%SUPPORT_EMAIL%}';`,
  `var urgent = '{%SUPPORT_URGENT_EMAIL%}';`,
  `var home = '{%HOMEPAGE_URL%}';`,
].join("\n");

test("substitutes every placeholder Elm can embed", () => {
  const out = substitutePlaceholders(sample, conf);

  expect(out).not.toContain("{%");
  expect(out).toContain(conf.SUPPORT_EMAIL);
  expect(out).toContain(conf.SUPPORT_URGENT_EMAIL);
  expect(out).toContain(conf.HOMEPAGE_URL);
});

test("substitutes every occurrence, not just the first", () => {
  const out = substitutePlaceholders(`'{%HOMEPAGE_URL%}' + '{%HOMEPAGE_URL%}'`, conf);

  expect(out).toBe(`'${conf.HOMEPAGE_URL}' + '${conf.HOMEPAGE_URL}'`);
});

test("leaves a placeholder alone when its config key is missing", () => {
  const out = substitutePlaceholders(sample, { HOMEPAGE_URL: conf.HOMEPAGE_URL });

  expect(out).toContain("{%SUPPORT_EMAIL%}");
  expect(out).toContain(conf.HOMEPAGE_URL);
  expect(out).not.toContain("undefined");
});

test("leaves code without placeholders untouched", () => {
  const code = `var x = 1;`;

  expect(substitutePlaceholders(code, conf)).toBe(code);
});

// The regression itself: the elm-watch entry point used to skip substitution
// unless compilationMode was "optimize".
for (const compilationMode of ["optimize", "standard", "debug"] as const) {
  test(`the elm-watch postprocess substitutes in ${compilationMode} builds`, () => {
    expect(postprocess({ code: sample, compilationMode })).not.toContain("{%");
  });
}
