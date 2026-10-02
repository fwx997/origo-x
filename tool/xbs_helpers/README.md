# XBS synchronous script helpers

The vendored `assets/xbs/native_helpers.js` bundle supplies the synchronous
`params.nativeTool` interface used by original 香色 sources. It contains a
tolerant HTML parser, XPath 1.0, MD5 and Unicode Base64 utilities, without
network, file, cookie or device access. Console and native logging are no-ops.

Rebuild with Node.js using `npm ci --ignore-scripts --no-audit --no-fund` and
`npm run build` in this directory. Versions and transitive integrity hashes
are pinned in `package-lock.json`; bundled licenses are generated alongside
the JavaScript asset. Node/npm are build tools only, not app dependencies.

XBS `//` queries on a selected list item include that item as the context root.
Node wrappers provide `queryWithXPath`, `content`, `raw`, and JSON serialization.
HTML is limited to 2 MiB and 50,000 nodes; the existing QuickJS memory and
execution-time limits still apply. Dart keeps cache entries per source and
runtime (32 source caches, 128 entries/256 KiB each); caches are not persisted.

Native regression coverage lives in `test/xbs_javascript_native_test.dart`.
