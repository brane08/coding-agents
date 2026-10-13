# Copilot config install

Derived from `claude-config/`. Per-repo is the reliable path.

## Per repo
Copy `copilot/.github/` into the repo root (merge with any existing `.github/`).
Includes: `copilot-instructions.md`, `instructions/*.instructions.md`, `skills/`, `agents/*.agent.md`, `memory/`.
Skill scripts are referenced as `.github/skills/<n>/<f>` (repo-root relative); keep exec bits (`chmod +x .github/skills/*/*.sh`).

## User-level (global) — verify against your IDE version
- Instructions: VS Code user prompts folder (Command Palette: "Chat: Configure Instructions"); `copilot-instructions.md` has no confirmed user-level file.
- Skills: `~/.copilot/skills/`. Agents: `~/.copilot/agents/` (or user prompts folder). Locations vary by version.
- If installed globally, script and memory paths in the text (`.github/skills/...`, `.github/memory/...`) must be rewritten to the absolute install path.

## VS Code settings
Merge `vscode-settings.snippet.json` into user `settings.json` (terminal auto-approve: allow = true, deny = false; everything else prompts).
Regex keys need a recent VS Code with `chat.tools.terminal.autoApprove` — verify against your IDE version.

## JetBrains
Supports instructions (`copilot-instructions.md`, `*.instructions.md`) and prompt files only; skills, custom agents and auto-approve settings may not apply — verify against your IDE version.

## Not ported (intentional)
- Claude hooks (write guard, merged-PR guard, push guard, delegate nudge) and the admin/sandbox permission profiles: hook payloads differ, and a port would fail open silently.
  `pr-squash-sync` and `git-pr.instructions.md` carry the merged-PR check as a manual step.
- Delegation/subagent rules, `delegation-audit`, Claude-only skills (bce, web-*, z*, etc.), `Read`/`Edit` path deny rules (use `.github/copilot-instructions.md` rules + `.copilotignore`-style exclusions if your setup has them).
- `memory/delegation-audit-log.md` was copied verbatim but is Claude-specific; delete it if unwanted.
