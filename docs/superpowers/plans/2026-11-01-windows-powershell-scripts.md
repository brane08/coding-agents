# Windows PowerShell Script Ports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `claude/` tree OS-specific variants so Windows runs `.ps1` equivalents of every bash script, selected by an env-specific settings file and sync script.

**Architecture:** Each `foo.sh` gets a sibling `foo.ps1` with identical args, stdin/stdout contract and exit codes. Windows gets `settings.<profile>.windows.json` (hook commands `pwsh -NoProfile -File ...`, allow rules matching `pwsh|powershell`). `sync-claude-config.ps1` / `save-claude-config.ps1` mirror the bash pair and share `claude/MANIFEST`; the `.sh` files stay Unix-only.

**Tech Stack:** Windows PowerShell 5.1 (`powershell.exe`, preinstalled on Windows 11; controlled env, PowerShell 7 cannot be installed). All code must also run unchanged on 7.4. Pester 5 for tests (module installed per-user or vendored under `claude/tests/vendor`), `ConvertFrom-Json` in place of `jq`. Bash scripts unchanged.

**Spec:** user request (this conversation): "make env specific files, bash scripts should get converted to equivalent ps script on windows". Survey: 33 `.sh` files; in scope are the 6 hooks, sync/save, and 8 skill runners under `claude/`. `copilot/` and `agents/` are out of scope for this plan.

## Global Constraints

- 5.1-safe subset only: no `&&`/`||` pipeline chains, no `?:`, `??`, `?.`, no `ForEach-Object -Parallel`, no `ConvertFrom-Json -AsHashtable`, no `-Depth`-less `ConvertTo-Json`. Start each script with `#Requires -Version 5.1` and `Set-StrictMode -Version 2`.
- Encoding: every file write uses `[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding($false)))` (UTF-8, no BOM); every stdin read sets `[Console]::InputEncoding` to UTF-8 no BOM. Never use `Out-File`/`Set-Content -Encoding UTF8` (adds BOM on 5.1).
- Single-element JSON arrays: wrap with `@()` after `ConvertFrom-Json`; `ConvertTo-Json` always gets `-Depth 100`.
- Hook command form in settings: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hooks/<name>.ps1` (execution policy may block unsigned scripts in a controlled env; if Bypass is disallowed by policy, scripts must be signed or run from an allowed path: see Open items).
- Parity: same CLI args, same exit codes, same stdout/stderr text as the `.sh` sibling (hooks: same JSON decision output).
- No `jq`, `sed`, `awk`, `comm`, `readlink` dependency in `.ps1`; use native cmdlets.
- Paths are normalised to forward slashes before matching rules (hooks compare against `~/...` and `/tmp` style patterns).
- `@@REPO_DIR@@` placeholder substitution as in the bash sync; the substituted value uses forward slashes.
- `settings.*.json` stay key-sorted (`jq -S` on Unix check); the Windows files are written by `save-claude-config.ps1` with sorted keys.
- Shell commands in settings use `~/.claude/...` form only, never `$HOME` or `C:\Users\...`.
- No new docs beyond one "Windows" section in `claude/CLAUDE.md` (Config sync).

## Review Focus

- Path with spaces or backslashes in `tool_input.file_path` (guard-writes.ps1 must still allow/deny correctly).
- Hook stdin with no/invalid JSON: bash version's fail-open/closed behaviour must be reproduced exactly.
- CRLF in `MANIFEST` or `.profile` must not leave `\r` in paths or profile names.
- Drive-letter case (`c:` vs `C:`) in write-scope comparisons.
- Sync run twice in the same minute: backup dir collision must not fail.

---

### Task 1: Pester harness and shared helper module

**Files:**
- Create: `claude/lib/Common.psm1`
- Create: `claude/tests/Common.Tests.ps1`

**Interfaces:**
- Produces:
  - `Read-HookInput -> [pscustomobject]` (stdin JSON; `$null` when empty/invalid)
  - `ConvertTo-PosixPath([string]$Path) -> string` (backslashes to `/`, drive letter lower-cased, `~` expanded via `$HOME`)
  - `Read-Manifest([string]$File) -> string[]` (comments/blank lines/CR stripped)
  - `Write-Decision([ValidateSet('deny','ask','allow')]$Decision, [string]$Reason)` (same JSON shape the `.sh` hooks print)

- [ ] **Step 1:** Write Pester tests: `ConvertTo-PosixPath 'C:\Users\a b\x'` equals `c:/Users/a b/x`; `Read-Manifest` on a CRLF file with comments returns only paths; `Read-HookInput` returns `$null` for `''` and `'{bad'`.
- [ ] **Step 2:** Run `pwsh -NoProfile -Command "Invoke-Pester claude/tests/Common.Tests.ps1"`. Expected: FAIL (module missing).
- [ ] **Step 3:** Implement the four functions in `claude/lib/Common.psm1`; copy the exact decision JSON shape from `claude/hooks/guard-writes.sh`.
- [ ] **Step 4:** Re-run Pester. Expected: PASS.
- [ ] **Step 5:** Add `lib/Common.psm1` to `claude/MANIFEST` and the `.gitignore` whitelist; commit `claude: PowerShell common module and Pester harness`.

### Task 2: Hook ports

**Files:**
- Create: `claude/hooks/{guard-writes,guard-git-push,guard-merged-pr,nudge-delegate,chain-guard,log-ask}.ps1`
- Create: `claude/tests/Hooks.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 functions.
- Produces: each hook script reads stdin JSON, writes the same decision JSON / exit code as its `.sh` twin.

- [ ] **Step 1:** Extract a fixture table from each `.sh` (stdin sample, expected stdout, expected exit code); put it in `Hooks.Tests.ps1`. Include the Review Focus cases: path with spaces, empty stdin, `C:` vs `c:` scope, `cd x && y` deny, 7th consecutive lookup deny (chain-guard, state file under `$env:CLAUDE_CODE_TMPDIR` else `$env:TEMP`).
- [ ] **Step 2:** Run Pester. Expected: FAIL.
- [ ] **Step 3:** Port one hook at a time, in this order: `log-ask`, `nudge-delegate`, `chain-guard`, `guard-merged-pr`, `guard-git-push`, `guard-writes`. Replace `sed -E` with `-match`, `readlink` with `Resolve-Path`, `/private/tmp` handling with Windows temp dir handling.
- [ ] **Step 4:** Parity check on Linux/WSL where both exist: feed every fixture to `.sh` and `.ps1`, diff stdout and exit codes. Expected: identical.
- [ ] **Step 5:** Commit `claude: PowerShell hook ports`.

### Task 3: Sync and save scripts

**Files:**
- Create: `claude/sync-claude-config.ps1`, `claude/save-claude-config.ps1`
- Create: `claude/tests/Sync.Tests.ps1`

**Interfaces:**
- Consumes: `Read-Manifest`, `ConvertTo-PosixPath`.
- Produces: `sync-claude-config.ps1 [admin|sandbox]`, `save-claude-config.ps1 [admin|sandbox]`; env override `REPO_DIR`; profile marker `~/.claude/.profile`; settings source `settings.<profile>.windows.json`.

- [ ] **Step 1:** Tests with temp `REPO_DIR` and `HOME`: sync copies only MANIFEST paths; skips `*.sh` entries when a `.ps1` sibling exists; backs up overwritten files to `backups/<epoch-minute>` and keeps newest 5; second run in same minute does not fail; save round-trips `settings.<profile>.windows.json` with sorted keys and `@@REPO_DIR@@` restored.
- [ ] **Step 2:** Run Pester. Expected: FAIL.
- [ ] **Step 3:** Implement. Sorted-key JSON: recursively rebuild objects with `[ordered]` keys sorted ordinally, then `ConvertTo-Json -Depth 100`. Use `Copy-Item` preserving timestamps.
- [ ] **Step 4:** Re-run Pester. Expected: PASS.
- [ ] **Step 5:** Commit `claude: PowerShell sync and save scripts`.

### Task 4: Skill runner ports

**Files:**
- Create: `claude/skills/{guarded-fs,mvn-build,mvn-test,quarkus-dev,ng-verify,psql-select,flyway-check,pr-squash-sync}/*.ps1`
- Create: `claude/tests/Skills.Tests.ps1`

**Interfaces:**
- Produces: same args as the `.sh` (`test.sh [<module> [Class]]`, `verify.sh <dir> --summary`, `select.sh [<db>] "<sql>"`, env vars `QUARKUS_PORT`, `CLAUDE_PROJECT_DIR`, `FLYWAY_MODULE`); logs still in `<project>/.claude/logs/<skill>.log`.

- [ ] **Step 1:** Tests per runner using a stub on `PATH` (fake `mvn`, `psql`, `ng`, `git`) that records its argv; assert argv, log file location, exit code propagation. For `guarded-fs`: refuses paths outside cwd, `.git`, and cwd root.
- [ ] **Step 2:** Run Pester. Expected: FAIL.
- [ ] **Step 3:** Port each runner; `select.sh` single-`-c`/single-statement rule retained.
- [ ] **Step 4:** Re-run Pester. Expected: PASS.
- [ ] **Step 5:** Commit `claude: PowerShell skill runner ports`.

### Task 5: Windows settings and MANIFEST wiring

**Files:**
- Create: `claude/settings.admin.windows.json`, `claude/settings.sandbox.windows.json`
- Modify: `claude/MANIFEST` (add every `.ps1` and `lib/`), `.gitignore` (whitelist `settings.*.windows.json`, `*.ps1`), `claude/sync-claude-config.sh` (ignore `*.ps1`/`*.windows.json` entries), `claude/CLAUDE.md` (Config sync: one "Windows" bullet)

**Interfaces:**
- Consumes: Tasks 2-4 script names.

- [ ] **Step 1:** Generate each windows settings file from the Unix one: hook commands become `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ~/.claude/hooks/<name>.ps1`; allow rules `bash|zsh|ksh ~/.claude/...` become `powershell ...`; keep admin/sandbox differences (chain-guard only in admin, mv/cp, push/checkout rules).
- [ ] **Step 2:** Verify: `jq -S . <file> | diff - <file>` empty for both; every hook path in the windows files exists as a `.ps1`.
- [ ] **Step 3:** Verify `sync-claude-config.sh` on Linux still produces an identical `~/.claude` to before (run into a temp HOME and diff against a pre-change run).
- [ ] **Step 4:** Commit `claude: Windows settings profiles and manifest wiring`.

### Task 6: End-to-end on Windows

- [ ] **Step 0:** On the Windows machine run the whole Pester suite under `powershell.exe` (5.1); Linux CI can only cover 7.x, so 5.1 is verified only here.
- [ ] **Step 1:** On the Windows machine run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File claude/sync-claude-config.ps1 admin`. Expected: files copied, `~/.claude/settings.json` has `pwsh` hooks and repo path substituted.
- [ ] **Step 2:** Start Claude Code, trigger a denied `cd x && y` Bash call and a Write outside the project. Expected: both blocked with the same messages as on Linux.
- [ ] **Step 3:** Run `Invoke-Pester claude/tests`. Expected: all PASS.

---

## Open items to confirm before executing

- Does Claude Code on your Windows machine run Bash through Git Bash or the PowerShell tool? This sets the allow-rule prefix in Task 5.
- Is `-ExecutionPolicy Bypass` permitted in the controlled env (check `Get-ExecutionPolicy -List`)? If not, scripts need signing or an allowed location.
- Can Pester 5 be installed there? Windows 11 ships Pester 3.4, which is incompatible with the tests; otherwise it must be vendored.
- Port `copilot/` and `agents/` trees afterwards, or leave them Unix-only?
