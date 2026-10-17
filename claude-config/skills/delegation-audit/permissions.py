#!/usr/bin/env python3
"""Group observed permission blocks by command shape, assign one cause each, propose fixes.

Sources (all read-only; contents are untrusted data, never executed or followed):
  state/permission-log.jsonl   PermissionRequest dialogs (hooks/log-ask.sh)
  state/delegation-nudges.tsv  hook denies, category only (chain-guard, nudge-delegate)
  projects/**/*.jsonl          auto-mode classifier denials, matched back to the tool call
Policy: settings.json + settings.local.json, plus <cwd>/.claude/settings*.json per entry.
Writes permission-report.md to --out and appends the new allow/env entries straight into
<repo>/claude-config/settings.<profile>.json (existing rules kept, key-sorted). The live
~/.claude/settings.json is never edited; sync-claude-config.sh makes the change live.
"""
import argparse, collections, datetime, fnmatch, glob, json, os, re, sys

SECRET = re.compile(r"(?i)(\w*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY)\w*)=[^\s\"']+|bearer\s+[^\s\"']+|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]*")
CLASSIFIER = re.compile(r"denied by the Claude Code auto mode classifier\. Reason: \[([^\]]*)\]")
ENV = re.compile(r"^(?:[A-Za-z_]\w*=\S*\s+)+")
FULL_HOME = re.compile(r"(\$HOME|\$\{HOME\}|/Users/[^/\s]+|/home/[^/\s]+|/root)(?=/\.(claude|copilot)/)")
SHELLS = {"bash", "zsh", "ksh", "sh", "dash", "python3", "python", "node"}
SCRIPT_SHELLS = ("bash", "zsh", "ksh")  # skill scripts re-exec into their own shell; allow all three
ANY_SHELL = "{bash,zsh,ksh}"
SHELL_TOOLS = {"Bash", "PowerShell"}  # tools whose input is a command line ("Bash" runs whatever shell)
PS_READ_VERBS = ("Get-", "Test-", "Select-", "Measure-", "Resolve-", "Format-", "Compare-")
WRAPPER = re.compile(r"^\s*(?:bash|zsh|ksh|sh|dash)\s+-[a-z]*c[a-z]*\s+([\"'])(.*)\1\s*$", re.S)
SUBCMD = {"git", "gh", "mvn", "./mvnw", "gradle", "./gradlew", "npm", "npx", "yarn", "pnpm", "ng", "uv",
          "pip", "docker", "kubectl", "oc", "helm", "go", "cargo", "brew", "apt", "systemctl", "flyway"}
TWO_LEVEL = {"gh", "kubectl", "oc", "docker"}
POWERFUL = SUBCMD | SHELLS | {"curl", "wget", "ssh", "scp", "rm", "mv", "cp", "chmod", "chown", "sudo", "psql",
                              "find", "sed", "awk", "xargs", "env", "eval", "exec"}
READ_ONLY = {"grep", "rg", "cat", "head", "tail", "ls", "wc", "tree", "fd", "jq", "which", "pwd", "date", "stat",
             "file", "du", "df", "diff"}
READ_ONLY_SUB = {("git", s) for s in ("log", "diff", "show", "status", "blame", "ls-files", "rev-parse", "branch")} | \
                {("gh", s) for s in ("pr", "issue", "repo", "run")}
HISTORY = ("git rebase", "git reset", "git commit", "git push", "git filter", "git update-ref")
FILE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Read"}
EDIT_FAMILY = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


# ---------- command parsing ----------

def segments(cmd):
    """Split on unquoted && || ; | and newlines. Returns (segments, has_subst)."""
    out, cur, q, i, subst = [], "", None, 0, False
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur += c
            if c == "\\" and q == '"' and i + 1 < len(cmd):
                cur += cmd[i + 1]; i += 1
            elif c == q:
                q = None
            elif q == '"' and (cmd.startswith("$(", i) or c == "`"):
                subst = True
        elif c in "'\"":
            q = c; cur += c
        elif cmd.startswith("$(", i) or c == "`":
            subst = True; cur += c
        elif cmd.startswith("&&", i) or cmd.startswith("||", i):
            out.append(cur); cur = ""; i += 1
        elif c in ";|\n":
            out.append(cur); cur = ""
        else:
            cur += c
        i += 1
    out.append(cur)
    return [s.strip() for s in out if s.strip()], subst


def words(seg):
    return re.findall(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'|\S+", seg)


def shape(seg):
    """Command shape: env prefix dropped, args reduced to `*`, subcommand / script path kept."""
    w = words(ENV.sub("", seg))
    if not w:
        return ""
    c = w[0]
    rest = [t for t in w[1:] if not t.startswith("-")]
    if c == "git" and len(w) > 2 and w[1] == "-C":
        rest = [t for t in w[3:] if not t.startswith("-")]
    if c in SCRIPT_SHELLS and rest:
        return f"{ANY_SHELL} {rest[0]} *"  # one group whichever of bash/zsh/ksh ran it
    if c in SHELLS and rest:
        return f"{c} {rest[0]} *"
    if c in SUBCMD and rest:
        n = 2 if c in TWO_LEVEL and len(rest) > 1 else 1
        return " ".join([c] + rest[:n]) + " *"
    return f"{c} *"


def read_only(seg):
    w = words(ENV.sub("", seg))
    if not w:
        return False
    if w[0] in READ_ONLY:
        return True
    if w[0] == "sed":
        return "-i" not in w and any(t.startswith("-n") for t in w)
    if w[0] == "find":
        return not any(t in ("-exec", "-execdir", "-delete", "-ok") for t in w)
    rest = [t for t in w[1:] if not t.startswith("-")]
    return bool(rest) and (w[0], rest[0]) in READ_ONLY_SUB


# ---------- rule matching ----------

def parse_rule(r):
    m = re.fullmatch(r"([\w*]+)(?:\((.*)\))?", r.strip(), re.S)
    return (m.group(1), m.group(2)) if m else (r, None)


def bash_match(spec, cmd):
    if spec is None:
        return True
    if spec.endswith(":*"):
        p = spec[:-2]
        return cmd == p or cmd.startswith(p + " ") or cmd.startswith(p)
    rx = "^" + ".*".join(re.escape(p) for p in spec.split("*")) + "$"
    if re.match(rx, cmd, re.S):
        return True
    return spec.endswith(" *") and cmd == spec[:-2]


def path_match(spec, path, cwd, base=None):
    """Claude Code path rules: //abs, ~/home-relative, /settings-dir-relative, else cwd-relative."""
    if spec is None:
        return True
    cwd = cwd or "/"
    p = os.path.normpath(path if path.startswith("/") else os.path.join(cwd, path))
    if spec.startswith("//"):
        anchor, pat = "/", spec[2:]
    elif spec.startswith("~/"):
        anchor, pat = os.path.expanduser("~"), spec[2:]
    elif spec.startswith("/"):
        anchor, pat = base or os.path.expanduser("~/.claude"), spec[1:]
    else:
        anchor, pat = cwd, spec.removeprefix("./")
    rel = os.path.relpath(p, anchor)
    rx = "^" + re.escape(pat).replace(r"\*\*/", "(.*/)?").replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$"
    return bool(re.match(rx, rel))


def matches(rule, tool, inp, cwd, cmd=None):
    rule, base = rule if isinstance(rule, tuple) else (rule, None)
    rt, spec = parse_rule(rule)
    # Edit(path) rules cover every file-editing tool; Write()/MultiEdit() path rules do not exist as such.
    same = rt == tool or (rt == "Edit" and tool in EDIT_FAMILY)
    if not same and not (rt.startswith("mcp__") and tool.startswith(rt.rstrip("*"))):
        return False
    if tool in SHELL_TOOLS:
        return bash_match(spec, cmd if cmd is not None else inp.get("command", ""))
    if tool in FILE_TOOLS:
        fp = inp.get("file_path") or inp.get("notebook_path") or ""
        return path_match(spec, fp, cwd, base) if fp else spec is None
    return spec is None


# ---------- policy ----------

def load_json(p):
    try:
        with open(p) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


class Policy:
    """Rules are kept as (rule, settings_dir) so /path rules resolve against their own file."""

    def __init__(self, cfg):
        self.base = [(load_json(os.path.join(cfg, f)), cfg) for f in ("settings.json", "settings.local.json")]
        self.cache = {}

    def for_cwd(self, cwd):
        if cwd not in self.cache:
            layers = list(self.base)
            d = cwd or ""
            while d and d != "/":
                for f in ("settings.json", "settings.local.json"):
                    p = os.path.join(d, ".claude", f)
                    if os.path.exists(p):
                        layers.append((load_json(p), os.path.join(d, ".claude")))
                d = os.path.dirname(d)
            pol = {"allow": [], "ask": [], "deny": [], "dirs": [cwd or "/"]}
            for s, base in layers:
                perm = s.get("permissions") or {}
                for k in ("allow", "ask", "deny"):
                    pol[k] += [(r, base) for r in perm.get(k) or []]
                pol["dirs"] += [os.path.expanduser(x) for x in perm.get("additionalDirectories") or []]
            self.cache[cwd] = pol
        return self.cache[cwd]


def first(rules, tool, inp, cwd, cmd=None):
    return next((r[0] for r in rules if matches(r, tool, inp, cwd, cmd)), None)


def outside(seg, dirs):
    for t in words(seg)[1:]:
        t = t.strip("'\"")
        if t.startswith(("/", "~")) and not t.startswith("/dev/"):
            p = os.path.expanduser(t)
            if not any(p == d or p.startswith(d.rstrip("/") + "/") for d in dirs):
                return True
    return False


# ---------- classification ----------

def classify(tool, inp, cwd, pol):
    """Return (cause, shape_key, current_rule, detail)."""
    if tool not in SHELL_TOOLS:
        key = f"{tool}({inp.get('file_path') or inp.get('raw', '')[:60]})"
        if tool in EDIT_FAMILY or tool == "Read":
            fp = inp.get("file_path") or ""
            ext = os.path.splitext(fp)[1] or os.path.basename(fp)
            key = f"{tool}(*{ext})" if fp else tool
        r = first(pol["deny"], tool, inp, cwd)
        if r:
            return "deny-hit", key, r, ""
        r = first(pol["ask"], tool, inp, cwd)
        if r:
            return "ask-override", key, r, ""
        r = first(pol["allow"], tool, inp, cwd)
        if r:
            return "allowed-yet-prompted", key, r, "a rule allows it: the prompt came from a hook (guard-writes " \
                                                  "asks for ~/.claude and out-of-project writes) or a harness check"
        if tool in EDIT_FAMILY:
            fp = inp.get("file_path") or ""
            r = next((r for r, b in pol["allow"] if parse_rule(r)[0] in EDIT_FAMILY - {"Edit"} and parse_rule(r)[1]
                      and path_match(parse_rule(r)[1], fp, cwd, b)), None)
            if r:
                return "rule-type", key, r, f"path rule written as {parse_rule(r)[0]}(); path rules must be Edit()"
        return "no-rule", key, None, ""

    cmd = inp.get("command", "")
    wrapped = WRAPPER.match(cmd)
    inner = wrapped.group(2) if wrapped else cmd
    segs, subst = segments(inner)
    key = (shape(segs[0]) + (" + …" if len(segs) > 1 else "")) if segs else ""

    def hit(rules):
        """A rule matching the full line, or any segment of it (inner command for `sh -c`)."""
        return first(rules, tool, inp, cwd, cmd) or next(
            (r for r in (first(rules, tool, inp, cwd, s) for s in [inner] + segs) if r), None)

    r = hit(pol["deny"])
    if r:
        return "deny-hit", key, r, ""
    r = hit(pol["ask"])
    if r:
        return "ask-override", key, r, ""
    if wrapped:
        return "shell-wrapper", key, first(pol["allow"], tool, inp, cwd, inner), \
            "`<shell> -c \"…\"` hides the command from allow rules; run the inner command directly"
    if FULL_HOME.search(cmd):
        r = first(pol["allow"], tool, inp, cwd, FULL_HOME.sub("~", cmd))
        if r:
            return "path-form", key, r, "rewrite the path with ~ (allow rules only match ~)"
    if len(segs) > 1 or subst or re.match(r"^\s*cd\s", cmd):
        missing = sorted({shape(s) for s in segs if not first(pol["allow"], tool, inp, cwd, s)})
        detail = ("segments without an allow rule: " + ", ".join(missing)) if missing else \
            "every segment is allowed: redirection, $()/backticks or a hook made it prompt"
        return "compound", key, None, detail + (" (uses $()/backticks)" if subst else "")
    if segs and read_only(segs[0]) and outside(segs[0], pol["dirs"]):
        return "outside-cwd", key, first(pol["allow"], tool, inp, cwd), "path outside the working/additional dirs"
    r = first(pol["allow"], tool, inp, cwd)
    if r and not ENV.match(cmd):
        return "allowed-yet-prompted", key, r, "a rule allows it: the prompt came from a hook returning ask " \
                                              "or a harness safety check"
    if ENV.match(cmd):
        r = first(pol["allow"], tool, inp, cwd, ENV.sub("", cmd))
        return "env-prefix", key, r, ENV.match(cmd).group(0).strip()
    return "no-rule", key, None, ""


# ---------- sources ----------

def since_ok(ts, since):
    return not since or (ts or "9") >= since


def from_log(cfg, since):
    for p in (os.path.join(cfg, "state", "permission-log.jsonl.1"), os.path.join(cfg, "state", "permission-log.jsonl")):
        try:
            fh = open(p, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if since_ok(d.get("ts"), since):
                    yield {"src": "dialog", "tool": d.get("tool") or "?", "input": d.get("input") or {},
                           "cwd": d.get("cwd") or "", "agent": bool(d.get("agent")), "reason": ""}


def from_transcripts(root, since):
    for f in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        uses = {}
        sub = "/subagents/" in f
        with open(f, errors="replace") as fh:
            for line in fh:
                if "tool_use" not in line and "classifier" not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                for b in (d.get("message") or {}).get("content") or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        uses[b.get("id")] = (b.get("name"), b.get("input") or {}, d.get("cwd") or "")
                    elif b.get("type") == "tool_result" and since_ok(d.get("timestamp"), since):
                        m = CLASSIFIER.search(json.dumps(b.get("content")))
                        if m and b.get("tool_use_id") in uses:
                            name, inp, cwd = uses[b["tool_use_id"]]
                            if name in EDIT_FAMILY:
                                inp = {"file_path": inp.get("file_path") or inp.get("notebook_path")}
                            yield {"src": "classifier", "tool": name, "input": inp, "cwd": cwd,
                                   "agent": sub or bool(d.get("isSidechain")), "reason": m.group(1)}


def hook_denies(cfg, since):
    c = collections.Counter()
    try:
        with open(os.path.join(cfg, "state", "delegation-nudges.tsv"), errors="replace") as fh:
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 3 and p[2].endswith("deny"):
                    ts = datetime.datetime.fromtimestamp(int(p[0]), datetime.timezone.utc).strftime("%Y-%m-%d") if p[0].isdigit() else ""
                    if since_ok(ts, since):
                        c[p[2]] += 1
    except OSError:
        pass
    return c


# ---------- proposals ----------

def propose(tool, cause, key, groups_examples, pol_deny, min_count, count, all_ro):
    """Return (change_text, allow_rules_or_None, env_dict, risk)."""
    if cause == "deny-hit":
        return "none — deny is working as intended", None, {}, "never relax"
    if cause == "ask-override":
        return "decide whether the ask rule is still wanted; narrow it rather than add an allow (ask beats allow)", \
            None, {}, "removing an ask rule widens what runs unprompted"
    if cause == "path-form":
        return "habit: invoke with ~/.claude/… (already allowed)", None, {}, "none"
    if cause == "shell-wrapper":
        return "habit: run the inner command directly (no `bash|zsh|ksh -c`); never allow `<shell> -c *`", \
            None, {}, "a -c rule would allow any command"
    if cause == "outside-cwd":
        return "use the Read/Grep tool on that path, or add the directory to additionalDirectories if it is " \
               "read routinely", None, {}, "additionalDirectories also widens edits in acceptEdits mode"
    if cause == "classifier-deny":
        return "no rule overrides the classifier; split the action (e.g. one-row Edits) or approve manually", \
            None, {}, "n/a"
    if cause == "allowed-yet-prompted":
        return "find the hook or check that asked (hook stderr / transcript); no rule change", None, {}, "n/a"
    if cause == "rule-type":
        return "add the same path rule for the tool actually used", None, {}, "check the path glob is not broader than intended"
    if count < min_count and not all_ro:
        return f"below threshold ({count} < {min_count}); watch", None, {}, ""
    if cause == "compound":
        return "run segments as separate calls; add per-segment rules only for read-only segments", None, {}, \
            "a rule for a compound shape never matches reliably"
    if cause == "env-prefix":
        vals = {ENV.match(e).group(0).strip() for e in groups_examples if ENV.match(e)}
        if len(vals) == 1:
            k, _, v = next(iter(vals)).split()[0].partition("=")
            return f"move {k} into env, drop the prefix", None, {k: v}, "applies to every session"
        return "values vary per run — keep the prefix; add `VAR=* cmd sub *` only if this shape lacks one", None, {}, ""
    # no-rule
    base = key.split()[0] if key else ""
    bare = key.endswith(" *") and len(key.split()) == 2
    if bare and (base in POWERFUL or (tool == "PowerShell" and not base.startswith(PS_READ_VERBS))):
        return f"no narrow form available (`{key}` would be bare); approve case by case", None, {}, "powerful tool"
    # A script shape gets the same rule for bash, zsh and ksh.
    keys = [f"{sh} {key.split(' ', 1)[1]}" for sh in SCRIPT_SHELLS] if base == ANY_SHELL else [key]
    rules = [f"{tool}({k})" for k in keys]
    for k in keys:
        prefix = k[:-2] if k.endswith(" *") else k
        for d, _ in pol_deny:
            dt, ds = parse_rule(d)
            if dt in SHELL_TOOLS and ds and (bash_match(ds, prefix + " x") or ds.split("*")[0].startswith(prefix)):
                return f"`{tool}({k})` would overlap deny `{d}`; not proposed", [], {}, "deny overlap"
    if any(key.startswith(p) for p in HISTORY):
        risk = "rewrites history: allow only if your squash/sync workflow needs it unprompted"
    else:
        risk = "read-only" if all_ro else "runs unprompted from now on; check the shape"
    return "add " + ", ".join(f"`{r}`" for r in rules), rules, {}, risk


def open_text(p):
    try:
        with open(p) as fh:
            return fh.read()
    except OSError:
        return ""


def find_repo(cfg):
    """The synced settings.json carries the repo path in its sync/save allow rules."""
    m = re.search(r"Bash\(\w+ (/[^\s)]+)/claude-config/sync-claude-config\.sh",
                  open_text(os.path.join(cfg, "settings.json")))
    return m.group(1) if m and os.path.isdir(m.group(1)) else None


def merge(base, allow, env):
    """Full settings = base unchanged + new allow rules appended + env keys not already set."""
    merged = json.loads(json.dumps(base))
    perm = merged.setdefault("permissions", {})
    current = perm.setdefault("allow", [])
    added = [r for r in allow if r not in current]
    current += added
    skipped = [k for k, v in env.items() if k in (merged.get("env") or {}) and merged["env"][k] != v]
    if env:
        merged.setdefault("env", {}).update({k: v for k, v in env.items() if k not in skipped})
    return merged, added, skipped


# ---------- report ----------

def code(s, n=100):
    s = SECRET.sub("<redacted>", s.replace("\n", " "))[:n]
    return "`" + s.replace("`", "'") + "`"


def main():
    ap = argparse.ArgumentParser()
    cfg_default = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    ap.add_argument("--since", help="YYYY-MM-DD")
    ap.add_argument("--config-dir", default=cfg_default)
    ap.add_argument("--out", default=os.path.join(cfg_default, "state", "permission-analysis"))
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--no-transcripts", action="store_true")
    ap.add_argument("--repo", default=os.environ.get("REPO_DIR"),
                    help="coding-agents checkout (default: REPO_DIR, else read from the sync rule in settings.json)")
    ap.add_argument("--profile", choices=["admin", "sandbox", "both"],
                    help="settings file(s) to update (default: <config-dir>/.profile, else admin)")
    ap.add_argument("--dry-run", action="store_true", help="report only, do not write settings")
    a = ap.parse_args()
    cfg = os.path.expanduser(a.config_dir)
    pol = Policy(cfg)

    events = list(from_log(cfg, a.since))
    if not a.no_transcripts:
        events += list(from_transcripts(os.path.join(cfg, "projects"), a.since))

    groups = {}
    for e in events:
        p = pol.for_cwd(e["cwd"])
        if e["src"] == "classifier":
            _, key, rule, _ = classify(e["tool"], e["input"], e["cwd"], p)
            cause, detail = "classifier-deny", f"[{e['reason']}]"
        else:
            cause, key, rule, detail = classify(e["tool"], e["input"], e["cwd"], p)
        g = groups.setdefault((cause, key), {"n": 0, "rule": rule, "detail": collections.Counter(), "tool": e["tool"],
                                             "ex": [], "agent": 0, "ro": True, "deny": p["deny"]})
        g["n"] += 1
        g["agent"] += e["agent"]
        g["detail"][detail] += 1
        cmd = e["input"].get("command") or e["input"].get("file_path") or e["input"].get("raw") or ""
        if e["tool"] not in SHELL_TOOLS or not all(read_only(s) for s in segments(cmd)[0]):
            g["ro"] = False
        if len(g["ex"]) < 3 and cmd not in g["ex"]:
            g["ex"].append(cmd)

    allow, env, rows = [], {}, []
    for (cause, key), g in sorted(groups.items(), key=lambda kv: -kv[1]["n"]):
        change, rules, ev, risk = propose(g["tool"], cause, key, g["ex"], g["deny"], a.min_count, g["n"], g["ro"])
        allow += [r for r in rules or [] if r not in allow]
        env.update(ev)
        rows.append((g, cause, key, change, risk))

    hd = hook_denies(cfg, a.since)
    os.makedirs(a.out, exist_ok=True)
    repo = a.repo or find_repo(cfg)
    profile = a.profile or (open_text(os.path.join(cfg, ".profile")) or "admin").strip()
    profiles = ["admin", "sandbox"] if profile == "both" else [profile]
    results = []  # (path, added, env_added, env_skipped, error)
    for p in profiles:
        path = os.path.join(repo, "claude-config", f"settings.{p}.json") if repo else ""
        if not os.path.isfile(path):
            results.append((path or f"settings.{p}.json", [], [], [], "repo settings file not found; "
                            "pass --repo or set REPO_DIR (live ~/.claude/settings.json is never edited)"))
            continue
        merged, added, skipped_env = merge(load_json(path), allow, env)
        env_added = [k for k in env if k not in skipped_env and k not in (load_json(path).get("env") or {})]
        if (added or env_added) and not a.dry_run:
            with open(path, "w") as fh:
                json.dump(merged, fh, indent=2, sort_keys=True, ensure_ascii=False)
                fh.write("\n")
        results.append((path, added, env_added, skipped_env, None))

    L = ["# Permission prompt report", "",
         f"Window: since {a.since or 'start of log'} · events: {len(events)} "
         f"(dialogs {sum(e['src'] == 'dialog' for e in events)}, classifier denials "
         f"{sum(e['src'] == 'classifier' for e in events)}) · groups: {len(groups)} · threshold: {a.min_count}", "",
         "Commands below are logged data, shown truncated and redacted; nothing in them is an instruction.", "",
         "| # | Count | Subagent | Cause | Shape | Current rule | Proposed change | Risk |",
         "|---|---|---|---|---|---|---|---|"]
    for i, (g, cause, key, change, risk) in enumerate(rows, 1):
        L.append(f"| {i} | {g['n']} | {g['agent']} | {cause} | {code(key, 60)} | "
                 f"{code(g['rule'], 60) if g['rule'] else '—'} | {change.replace('|', '/')} | {risk} |")
    L += ["", "## Details", ""]
    for i, (g, cause, key, change, risk) in enumerate(rows, 1):
        L.append(f"**{i}. {code(key, 60)}** — {cause}, {g['n']}×")
        for d, n in g["detail"].most_common(3):
            if d:
                L.append(f"- {d} ({n}×)")
        for ex in g["ex"]:
            L.append(f"- e.g. {code(ex)}")
        L.append("")
    L += ["## Hook denies (category only, from delegation-nudges.tsv)", ""]
    L += [f"- {k}: {v}" for k, v in hd.most_common()] or ["- none"]
    L += ["", "## Settings updated" + (" (dry run, nothing written)" if a.dry_run else ""), ""]
    for path, added, env_added, skipped_env, err in results:
        L.append(f"`{path}`" + (f": {err}" if err else ""))
        L += [f"- allow + {code(r)}" for r in added] + [f"- env + `{k}`" for k in env_added]
        L += [f"- env `{k}` already set to a different value; left unchanged" for k in skipped_env]
        if not err and not added and not env_added:
            L.append("- nothing new")
        L.append("")
    L += ["Existing allow/ask/deny rules, hooks and env are kept; deny rules are never touched. "
          "Review with `git diff claude-config/`, then `sync-claude-config.sh <profile>` to make it live."]
    with open(os.path.join(a.out, "permission-report.md"), "w") as fh:
        fh.write("\n".join(L) + "\n")
    print(f"events {len(events)}  groups {len(groups)}")
    print(f"wrote {a.out}/permission-report.md")
    for path, added, env_added, _, err in results:
        verb = "would add" if a.dry_run else "added"
        print(f"{path}: {err}" if err else f"{path}: {verb} {len(added)} allow, {len(env_added)} env")
    return 1 if any(r[4] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
