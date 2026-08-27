/**
 * elm-postprocess.mjs substitutes the build-time config placeholders into the
 * compiled elm.js. Upstream did it only under `--optimize`, so any
 * non-optimize build shipped raw `{%SUPPORT_EMAIL%}` / `{%HOMEPAGE_URL%}`
 * strings into the UI (CODE_REVIEW.md B13).
 *
 * Needs a `config.js` in the repo root, like the build itself
 * (`cp config-example.js config.js`).
 */
import { expect, test } from "bun:test";
import postprocess from "../elm-postprocess.mjs";
import config from "../config.js";

const sample = [
  `var support = '{%SUPPORT_EMAIL%}';`,
  `var urgent = '{%SUPPORT_URGENT_EMAIL%}';`,
  `var home = '{%HOMEPAGE_URL%}';`,
].join("\n");

const modes = ["optimize", "standard", "debug"] as const;

for (const compilationMode of modes) {
  test(`substitutes every placeholder in ${compilationMode} builds`, () => {
    const out = postprocess({ code: sample, compilationMode });

    expect(out).not.toContain("{%");
    expect(out).toContain(config.SUPPORT_EMAIL);
    expect(out).toContain(config.SUPPORT_URGENT_EMAIL);
    expect(out).toContain(config.HOMEPAGE_URL);
  });
}

test("substitutes every occurrence, not just the first", () => {
  const out = postprocess({
    code: `'{%HOMEPAGE_URL%}' + '{%HOMEPAGE_URL%}'`,
    compilationMode: "standard",
  });

  expect(out).toBe(`'${config.HOMEPAGE_URL}' + '${config.HOMEPAGE_URL}'`);
});

test("leaves code without placeholders untouched", () => {
  const code = `var x = 1;`;

  expect(postprocess({ code, compilationMode: "standard" })).toBe(code);
});
