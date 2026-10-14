# esbuild / ESM bundler quirks

## Exported `let` is read-only for importers
Reassigning an exported `let` from another module (e.g. test setup doing
`module.oidcMode = 'x'`) throws `Cannot assign to import "..."` (TS2540) — ESM import
bindings are live but read-only from the importer's side.

Fix: never export a mutable `let` for cross-module state. Export a private value plus
`getX()`/`setX()` functions instead.
