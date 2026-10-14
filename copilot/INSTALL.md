# Copilot config install

Derived from `claude-config/`. Per-repo is the reliable path.

## Per repo
Copy `copilot/.github/` into the repo root (merge with any existing `.github/`).
Includes: `copilot-instructions.md`, `instructions/*.instructions.md`, `skills/`, `agents/*.agent.md`, `memory/`.
Skill scripts are referenced as `.github/skills/<n>/<f>` (repo-root relative); keep exec bits (`chmod +x .github/skills/*/*.sh`).

## User-level (global) — verify against your IDE version
No single global location is read by every Copilot IDE plugin.

| Tool | User-level location |
|---|---|
| VS Code | Profile `prompts/` folder (macOS: `~/Library/Application Support/Code/User/prompts/`) for `*.instructions.md`, `*.prompt.md`, `*.agent.md`. Settings that accept any folder: `chat.instructionsFilesLocations`, `chat.promptFilesLocations`, `chat.agentFilesLocations`, `chat.agentSkillsLocations` |
| JetBrains | `~/.config/github-copilot/intellij/global-copilot-instructions.md` or the Copilot settings UI. Instructions and prompts only |
| Copilot CLI | `~/.copilot/` (instructions, agents, skills) |
| Per repo (all IDEs) | `.github/copilot-instructions.md`, `AGENTS.md` |

Recommended setup: keep one canonical dir, `~/.copilot/`, as a copy of `copilot/.github/` contents.
1. VS Code: point the four `chat.*FilesLocations` / `chat.agentSkillsLocations` settings at `~/.copilot/{instructions,prompts,agents,skills}`.
2. JetBrains: symlink `global-copilot-instructions.md` to `~/.copilot/copilot-instructions.md`.
3. Copy or symlink `.github/` into a repo only for project-specific rules.

Global install: script and memory paths in the text (`.github/skills/...`, `.github/memory/...`) must be rewritten to `~/.copilot/skills/...` and `~/.copilot/memory/...`.
The terminal auto-approve regex in `vscode-settings.snippet.json` only matches repo-relative `bash .github/skills/...`; for a global install change it to match `bash ~/.copilot/skills/...` too. No `prompts/` directory is shipped (VS Code's `prompts/` folder is only for your own prompt files).

## VS Code settings
Merge `vscode-settings.snippet.json` into user `settings.json` (terminal auto-approve: allow = true, deny = false; everything else prompts).
Regex keys need a recent VS Code with `chat.tools.terminal.autoApprove` — verify against your IDE version.

## JetBrains
Supports instructions (`copilot-instructions.md`, `*.instructions.md`) and prompt files only; skills, custom agents and auto-approve settings may not apply — verify against your IDE version.

## Model pinning
The read-only/triage agents pin `model: GPT-5.6 Luna` (a cheap GPT model; the Copilot equivalent of the haiku pin in Claude). The value must match the exact model name in your Copilot model picker, otherwise edit or remove it. An unavailable model falls back to the picker's default.

- The `model` property is VS Code-only. Remove it from agent files used by the GitHub.com coding agent, which errors on it.
- Business/Enterprise admins must enable the GPT-5.6 policy before the pinned model is available.

## Not ported (intentional)
- Claude hooks (write guard, merged-PR guard, push guard, delegate nudge) and the admin/sandbox permission profiles: hook payloads differ, and a port would fail open silently.
  `pr-squash-sync` and `git-pr.instructions.md` carry the merged-PR check as a manual step.
- Delegation/subagent rules, `delegation-audit`, Claude-only skills (bce, web-*, z*, etc.), `Read`/`Edit` path deny rules (use `.github/copilot-instructions.md` rules + `.copilotignore`-style exclusions if your setup has them).
