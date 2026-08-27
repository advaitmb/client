import * as esbuild from 'esbuild';
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Runtime-agnostic project root. This used to be Bun's `import.meta.dir`,
// which made the whole build Bun-only and failed under Node with an opaque
// AliasPlugin error (CODE_REVIEW.md B5). Bun stays canonical (ADR-0004);
// this form just costs nothing and fails legibly elsewhere.
const projectRoot = path.dirname(fileURLToPath(import.meta.url));

const myAliasPlugin = {
  name: "AliasPlugin",
  setup(build) {
    build.onResolve({ filter: /^Container$/ }, () => {
      return { path: path.join(projectRoot, "./src/web/container-web.js") };
    });
  },
};

// esbuild.build() rejects on failure, so there is nothing to inspect
// afterwards: reaching the log below means every bundle was written.
await esbuild.build({
  // named outputs: web/doc.js (Elm's port layer), web/ui.js (the interface
  // layer -- custom elements Elm renders by tag), and
  // web/database-download.js (the standalone IndexedDB export page)
  entryPoints: {
    doc: './src/shared/doc.js',
    ui: './src/ui/index.ts',
    'database-download': './src/web/database-download.js',
  },
  outdir: './web',
  plugins: [myAliasPlugin],
  minify: true,
  platform: 'browser',
  bundle: true,
  external: ['crypto'],
  define: {
    'global': 'self',
  },
});

console.log("\x1b[32m%s\x1b[0m", "Build succeeded");
