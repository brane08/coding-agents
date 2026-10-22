# .agents install

Tool-agnostic base: no tool names, tool paths or tool-only frontmatter fields in the skills, rules or agent roles.
Follows two open formats: Agent Skills (agentskills.io, `SKILL.md`) and AGENTS.md (agents.md).

## Layout
`agents/` mirrors `~/.agents/`:
- `skills/<name>/SKILL.md` plus scripts, one directory per skill. Each `SKILL.md` has the spec frontmatter (`name` equal to the directory name, `description`, `compatibility`, `metadata`).
- `agents/<name>.md`: subagent roles (9). Frontmatter is only `name` and `description`, then the role text. No cross-tool standard exists for subagent files, so this is plain shared text that each tool wraps (see Tool versions).
- `AGENTS.md`: portable rules. Copy to a repo root as `AGENTS.md`, or import it from a tool-specific instructions file.
- `check-base.sh`: reports drift between the base agents and the tool versions.

## Where tools look (per the Agent Skills client guide)
| Scope | Path |
|---|---|
| User | `~/.agents/skills/` |
| Project | `<repo>/.agents/skills/` |

The spec does not mandate skill locations; `.agents/skills/` is the documented cross-client convention, and project skills override user skills with the same name. AGENTS.md has no user-level location in its spec: it is read from the repo (the closest file to the edited file wins). Whether a given tool scans `.agents/skills/` or reads `AGENTS.md` depends on its version; verify against your tool.

## Install
1. `mkdir -p ~/.agents && cp -R agents/skills ~/.agents/ && chmod +x ~/.agents/skills/*/*.sh`
2. Per repo that needs the rules: copy `agents/AGENTS.md` to `<repo>/AGENTS.md`.
3. Project-only skills: copy the skill directory into `<repo>/.agents/skills/` instead of the user dir.

Scripts resolve the project from `AGENT_PROJECT_DIR`, else the current directory, and write logs to `<project>/.agents/logs/`.
Command allowlists must match `~/.agents/skills/...` as written (with `~`). Add the rules your tool needs; none are shipped here.

## Tool versions
The base is only a baseline. Each tool tree keeps its own complete files, with the tool's frontmatter and details, and is maintained on its own; nothing is generated from the base and a tool file may differ from it.

| Tree | Per-agent file | Contains |
|---|---|---|
| `claude/agents/<name>.md` | frontmatter (`tools`, `model`, `autoCompactWindow`, `omitClaudeMd`, `permissionMode`), the full role text, then `## Claude Code specifics` | `CLAUDE.md` read hint, skill script paths under `~/.claude`, shell rules, memory and log locations |

`bash agents/check-base.sh` keeps the base tool-free (exit 1 if a base file names a tool) and reports where a tool file differs from the base; add `--strict` to make differences fail.
Models: the base only names tiers (fast, standard, strongest, in `AGENTS.md`); each tool tree pins its own models (Claude: `model:` in the agent frontmatter; Copilot: `copilot/INSTALL.md`, Model pinning).
For tools that read their own instructions file, import `AGENTS.md` from it (Claude Code: `@AGENTS.md` in `CLAUDE.md`). `copilot/agents/*.agent.md` is not compared yet.

## Validate
```
git clone https://github.com/agentskills/agentskills && pip install -e agentskills/skills-ref
for d in agents/skills/*/; do skills-ref validate "$d"; done
bash agents/check-base.sh
```

## Not included (intentional)
Tool-only skills (`caveman`, `delegation-audit`), hooks, model pins and permission profiles stay in the tool trees.
