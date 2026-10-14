#!/usr/bin/env python3
"""Audit main-thread (non-haiku) lookups that belong in a code-search dispatch.

A lookup (read-only Bash command, Grep or Glob tool call) is a violation when it is the 2nd or
later in a run with no Edit/Write/Agent in between, when it is piped/chained, or when it is an
inline module-wide test run. A single lookup is the allowed locate-before-edit. Read is neutral.
The raw legacy count (every first-word lookup) is printed too, for comparison with old baselines.
"""
import argparse, collections, datetime, glob, json, os, re, sys

RO = {"grep", "rg", "find", "cat", "ls", "tail", "head", "wc", "sed", "awk", "tree", "fd"}
GIT_RO = {"log", "diff", "show", "blame"}
TEST = re.compile(r"(^| )(test|verify|pytest|surefire:test|failsafe:integration-test|playwright test)( |$)")
INLINE_TEST = re.compile(r"mvn-test/test\.sh( +[^\s-][^\s]*)? *$|ng-verify/verify\.sh")
SECRET = re.compile(r"(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)=\S{12,}|Bearer \S{12,}|eyJ[\w-]{10,}\.[\w-]{10,}\.\S*")
ENV = re.compile(r"^([A-Za-z_]\w*=\S* +)*")
CD = re.compile(r"^cd [^&;]*(&&|;) *")
QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'")
SPLIT = re.compile(r"\|\||&&|;|\|")
MANDATED = re.compile(
    r"^git (log --oneline(?: origin/\S+)?(?: -[1-3])?(?: origin/\S+)?|diff --stat(?: HEAD)? origin/\S+(?: HEAD)?)$")
BOOKKEEPING = ("/.claude/memory/", "/.claude/projects/")
RESET_TOOLS = {"Edit", "Write", "NotebookEdit", "Agent", "Task"}


def classify(cmd):
    """Return (kind, chained). kind is None for non-lookups."""
    c = CD.sub("", ENV.sub("", cmd.strip()))
    w = c.split()
    if not w:
        return None, False
    first = w[0]
    chained = len([p for p in SPLIT.split(QUOTED.sub("", c)) if p.strip()]) > 1
    if first in RO:
        return first, chained
    if first == "git" and len(w) > 1 and w[1] in GIT_RO:
        return "git-" + w[1], chained
    if first in {"mvn", "./mvnw", "gradle", "./gradlew", "pytest", "uv", "python", "python3", "npm", "npx", "ng"}:
        if TEST.search(c) and "-Dtest=" not in c:
            return "test-run", chained
    if first == "bash" and INLINE_TEST.search(c):
        return "test-run", chained
    return None, False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    a = ap.parse_args()
    since = datetime.datetime.strptime(a.since, "%Y-%m-%d").timestamp()
    cats, projs, shapes = collections.Counter(), collections.Counter(), collections.Counter()
    files = calls = raw = runs3 = 0
    for f in glob.glob(os.path.join(a.root, "*", "*.jsonl")):
        if os.path.getmtime(f) < since:
            continue
        files += 1
        proj = os.path.basename(os.path.dirname(f))
        run = 0
        with open(f, errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "assistant" or d.get("isSidechain"):
                    continue
                m = d.get("message", {})
                if "haiku" in str(m.get("model", "")):
                    continue
                if (d.get("timestamp") or "9") < a.since:
                    continue
                for b in m.get("content") or []:
                    if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                        continue
                    name, inp = b.get("name"), b.get("input") or {}
                    if name in RESET_TOOLS:
                        run = 0
                        continue
                    if name in ("Grep", "Glob"):
                        calls += 1
                        if any(p in str(inp.get("path", "")) for p in BOOKKEEPING):
                            continue
                        kind, chained, text = name.lower() + "-tool", False, name + " " + str(inp.get("pattern", ""))
                    elif name == "Bash":
                        calls += 1
                        cmd = inp.get("command", "")
                        kind, chained = classify(cmd)
                        text = cmd
                        if kind:
                            raw += 1
                        if not kind or MANDATED.match(cmd.strip()) or any(p in cmd for p in BOOKKEEPING):
                            continue
                    else:
                        continue
                    run += 1
                    if run == 3:
                        runs3 += 1
                    if run >= 2 or chained or kind == "test-run":
                        cats[kind] += 1
                        projs[proj] += 1
                        shapes[SECRET.sub("<redacted>", text.replace("\n", " "))[:80]] += 1
    viol = sum(cats.values())
    rate = f"{100 * viol / calls:.0f}%" if calls else "n/a"
    print(f"transcripts: {files}  main-thread Bash/Grep/Glob calls: {calls}")
    print(f"violations (run-based): {viol}  rate: {rate}  runs>=3: {runs3}")
    print(f"raw legacy count (every first-word lookup, Bash only): {raw}")
    print("\nper command:")
    for k, v in cats.most_common():
        print(f"  {k:12} {v}")
    print("\nper project:")
    for k, v in projs.most_common():
        print(f"  {k:60} {v}")
    print("\ntop shapes:")
    for k, v in shapes.most_common(5):
        print(f"  {v:4}  {k}")


if __name__ == "__main__":
    sys.exit(main())
