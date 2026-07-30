# Bundled JSX preview libraries

These three files let the artifact panel *run* a React/JSX artifact instead of
only showing its source. They are vendored rather than fetched from a CDN, for
the same reason the fonts and `mermaid.min.js` are: the app is served from
static GitHub Pages and also ships as a downloadable desktop/mobile app, and a
preview that needs the network to work is a preview that fails offline and
behind filters.

| File | Version | License | Size |
|---|---|---|---|
| `react.min.js` | React 18.3.1 (UMD, production) | MIT | 11 KB |
| `react-dom.min.js` | ReactDOM 18.3.1 (UMD, production) | MIT | 129 KB |
| `sucrase.min.js` | Sucrase 3.35.0, bundled to an IIFE | MIT | 201 KB |

## Why Sucrase rather than Babel

`@babel/standalone` is the usual choice and is **2.8 MB** — larger than the
rest of this app's assets combined, to do one job. Sucrase does that job
(JSX/TypeScript → plain JS) in 201 KB because it is a transformer rather than a
full compiler: no full AST, no plugin system, no transforms this needs.

The trade is that Sucrase does not *check* anything. Invalid JSX produces a
runtime error in the sandbox rather than a compile error with a caret. For a
preview pane that is the right trade — the source is one tab away either way.

## Regenerating `sucrase.min.js`

It is bundled from npm, not shipped in this shape by the package:

```sh
npm install sucrase@3.35.0 esbuild@0.23.1
cat > entry.js <<'JS'
import { transform } from 'sucrase';
globalThis.ShiftJsx = {
  transform(code, { typescript = false } = {}) {
    return transform(code, {
      transforms: ['jsx', ...(typescript ? ['typescript'] : []), 'imports'],
      jsxRuntime: 'classic',
      production: true,
    }).code;
  },
};
JS
./node_modules/.bin/esbuild entry.js --bundle --minify --format=iife \
  --platform=browser --outfile=sucrase.min.js
```

The `imports` transform is deliberate: it turns `import React from "react"`
into CommonJS `require`, which the host page satisfies with a small shim
mapping module names onto the UMD globals. Without it the import statement
survives into a classic `<script>` and is a syntax error.

## Loading cost

These are Flutter assets, fetched over HTTP the first time something reads
them — so on the web they cost nothing until a JSX artifact is actually
previewed. In the packaged desktop/mobile apps they are part of the bundle and
add ~348 KB to a ~23 MB download.
