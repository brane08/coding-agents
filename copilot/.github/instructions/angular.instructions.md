---
applyTo: "**/*.ts,**/*.html,**/*.scss"
---
# Angular
- Verify with `bash .github/skills/ng-verify/verify.sh <app-dir> --summary` (tsc `--noEmit` + headless `ng test` in one pass). Not ad hoc `tsc`/`ng test`.
- Scope to specs: `bash .github/skills/ng-verify/verify.sh <app-dir> --include=**/cart.*.spec.ts`.
- Don't pipe the script through `grep`/`tail`; full log is in `/tmp/ng-verify.log`.
- Needs `tsconfig.app.json` and installed `node_modules` in the app dir; run `npm install` first if missing.
- Follow existing file naming/placement (`*.service.ts`, `*.component.ts`); mirror an existing example before adding new stubs.
- esbuild/ESM: exported `let` is read-only to importers (TS2540) — see `.github/memory/libs/esbuild-esm.md`.
- Don't use `--legacy-peer-deps` for auth/crypto/http-client packages; pin a compatible version.
