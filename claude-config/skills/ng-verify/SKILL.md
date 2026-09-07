---
name: ng-verify
description: >
  Use when asked to typecheck, build-check, or run unit tests for an Angular
  frontend. Runs `tsc --noEmit` plus `ng test` headless in one pass.
---
# Angular Verify

Run one of:
  bash ~/.claude/skills/ng-verify/verify.sh                              # current dir
  bash ~/.claude/skills/ng-verify/verify.sh ui-angular                   # named app dir
  bash ~/.claude/skills/ng-verify/verify.sh ui-angular --include=**/cart.*.spec.ts

Notes:
- Requires `tsconfig.app.json` in the target dir — errors out early if missing
  rather than running a misleading typecheck against the wrong config.
- Resolves `CHROME_BIN` automatically from the puppeteer/Playwright cache if not
  already set — avoids the recurring "Chrome failed to start" headless-launch
  failure. Set `CHROME_BIN` yourself first if a specific binary is needed.
- Runs typecheck first, then tests, even if typecheck fails, so both failure
  classes are reported together instead of stopping at the first.

Report:
- Typecheck: OK / FAILED, with `error TS` lines verbatim if failed
- Tests: PASSED / FAILED, with failing spec names if failed
- Total time
