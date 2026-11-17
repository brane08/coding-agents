---
name: ng-verify
description: Typecheck and unit-test an Angular app in one pass (tsc --noEmit plus headless ng test), with a --summary digest mode. Use when asked to typecheck, build-check, or run unit tests for an Angular frontend.
compatibility: Requires bash, Node with installed node_modules, tsconfig.app.json in the app directory, and a headless Chrome (CHROME_BIN is auto-detected from the puppeteer or Playwright cache).
metadata:
  version: "1.0"
---
# Angular Verify

Run one of:

```
bash ~/.agents/skills/ng-verify/verify.sh                              # current dir
bash ~/.agents/skills/ng-verify/verify.sh ui-angular                   # named app dir
bash ~/.agents/skills/ng-verify/verify.sh ui-angular --include=**/cart.*.spec.ts
bash ~/.agents/skills/ng-verify/verify.sh ui-angular --summary         # digest only
```

Prefer `--summary`: it prints just the verdict line, `error TS` lines and failing specs with their first error line.
Don't pipe the script through `grep` or `tail`; a piped command is not covered by command allowlists and prompts.
The full log is always in `<project>/.agents/logs/ng-verify.log` (self-ignoring dir); read it there, not from `/tmp`.

Notes:
- Requires `tsconfig.app.json` in the target dir; errors out early if missing rather than typechecking the wrong config.
- Resolves `CHROME_BIN` from the puppeteer/Playwright cache if not set, avoiding the recurring "Chrome failed to start"
  failure. Set `CHROME_BIN` first if a specific binary is needed.
- Runs typecheck first, then tests, even if typecheck fails, so both failure classes are reported together.

Report:
- Typecheck: OK / FAILED, with `error TS` lines verbatim if failed
- Tests: PASSED / FAILED, with failing spec names if failed
- Total time
