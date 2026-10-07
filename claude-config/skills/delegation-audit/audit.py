#!/usr/bin/env python3
"""Count main-thread Bash calls on non-haiku models that belong in haiku agents."""
import argparse, collections, datetime, glob, json, os, re, sys

RO = {"grep", "rg", "find", "cat", "ls", "tail", "head", "wc", "sed", "awk", "tree", "fd"}
GIT_RO = {"log", "diff", "show", "blame"}
TEST = re.compile(r"(^| )(test|verify|pytest|surefire:test|failsafe:integration-test|playwright test)( |$)")
SECRET = re.compile(r"(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)=\S{12,}|Bearer \S{12,}|eyJ[\w-]{10,}\.[\w-]{10,}\.\S*")
ENV = re.compile(r"^([A-Za-z_]\w*=\S* +)*")
CD = re.compile(r"^cd [^&;]*(&&|;) *")


def classify(cmd):
    c = CD.sub("", ENV.sub("", cmd.strip()))
    w = c.split()
    if not w:
        return None
    first = w[0]
    if first in RO:
        return first
    if first == "git" and len(w) > 1 and w[1] in GIT_RO:
        return "git-" + w[1]
    if first in {"mvn", "./mvnw", "gradle", "./gradlew", "pytest", "uv", "python", "python3", "npm", "npx", "ng"}:
        if TEST.search(c) and "-Dtest=" not in c:
            return "test-run"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    a = ap.parse_args()
    since = datetime.datetime.strptime(a.since, "%Y-%m-%d").timestamp()
    cats, projs, shapes = collections.Counter(), collections.Counter(), collections.Counter()
    files = 0
    for f in glob.glob(os.path.join(a.root, "*", "*.jsonl")):
        if os.path.getmtime(f) < since:
            continue
        files += 1
        proj = os.path.basename(os.path.dirname(f))
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
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash":
                        cmd = (b.get("input") or {}).get("command", "")
                        k = classify(cmd)
                        if k:
                            cats[k] += 1
                            projs[proj] += 1
                            shapes[SECRET.sub("<redacted>", cmd.replace("\n", " "))[:80]] += 1
    print(f"transcripts: {files}  violations: {sum(cats.values())}")
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
