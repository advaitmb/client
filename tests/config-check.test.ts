/**
 * config-check.js must be a real gate: exit 0 when config.js has exactly
 * the keys of config-example.js, non-zero on any mismatch
 * (CODE_REVIEW.md B1: it used to print the diff but always exit 0).
 *
 * config-check.js resolves ./config.js relative to itself, so each case
 * copies it and config-example.js into a fresh temp dir next to the
 * config.js variant under test.
 */
import { expect, test } from "bun:test";
import { copyFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = join(import.meta.dir, "..");

function runConfigCheck(configJsSource: string): { exitCode: number; stderr: string } {
  const dir = mkdtempSync(join(tmpdir(), "gw-config-check-"));
  copyFileSync(join(repoRoot, "config-check.js"), join(dir, "config-check.js"));
  copyFileSync(join(repoRoot, "config-example.js"), join(dir, "config-example.js"));
  writeFileSync(join(dir, "config.js"), configJsSource);
  const result = Bun.spawnSync([process.execPath, join(dir, "config-check.js")], {
    cwd: dir,
    stderr: "pipe",
  });
  return { exitCode: result.exitCode, stderr: result.stderr.toString() };
}

test("passes when config.js has exactly the example's keys", () => {
  const ok = runConfigCheck(`module.exports = {
    HOMEPAGE_URL: "https://my-gingko.example.com",
    SUPPORT_EMAIL: "me@example.com",
    SUPPORT_URGENT_EMAIL: "urgent@example.com",
    LEGACY_URL: "https://legacy.example.com",
  };`);
  expect(ok.exitCode).toBe(0);
});

test("fails when config.js is missing a key from config-example.js", () => {
  const missing = runConfigCheck(`module.exports = {
    HOMEPAGE_URL: "https://my-gingko.example.com",
    SUPPORT_EMAIL: "me@example.com",
    LEGACY_URL: "https://legacy.example.com",
  };`);
  expect(missing.exitCode).not.toBe(0);
  expect(missing.stderr).toContain("SUPPORT_URGENT_EMAIL");
});

test("fails when config.js has a key config-example.js does not", () => {
  const extra = runConfigCheck(`module.exports = {
    HOMEPAGE_URL: "https://my-gingko.example.com",
    SUPPORT_EMAIL: "me@example.com",
    SUPPORT_URGENT_EMAIL: "urgent@example.com",
    LEGACY_URL: "https://legacy.example.com",
    TYPO_KEY: true,
  };`);
  expect(extra.exitCode).not.toBe(0);
  expect(extra.stderr).toContain("TYPO_KEY");
});
