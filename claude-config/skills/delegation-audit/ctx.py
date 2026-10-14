import json, glob, os, statistics as st
from collections import defaultdict

root = os.path.expanduser("~/.claude/projects")
MECH = {"Bash", "Grep", "Glob", "Read"}
rows = []
models = defaultdict(lambda: defaultdict(int))
for f in glob.glob(root + "/*/*.jsonl") + glob.glob(root + "/*/*/subagents/*.jsonl"):
    seen = set()
    series = []
    is_sub = "/subagents/" in f
    proj = os.path.basename(os.path.dirname(f))[-30:]
    try:
        for line in open(f):
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message") or {}
            u = m.get("usage")
            if d.get("type") != "assistant" or not u:
                continue
            mid = m.get("id") or d.get("uuid")
            if mid in seen:
                continue
            seen.add(mid)
            side = is_sub or bool(d.get("isSidechain"))
            blocks = m.get("content") if isinstance(m.get("content"), list) else []
            tools = [b.get("name") for b in blocks if b.get("type") == "tool_use"]
            text = any(b.get("type") == "text" and (b.get("text") or "").strip() for b in blocks)
            key = (("sub:" if side else "main:") + str(m.get("model") or "?"))
            s = models[key]
            s["turns"] += 1
            s["out"] += u.get("output_tokens") or 0
            s["fresh"] += (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
            s["cread"] += u.get("cache_read_input_tokens") or 0
            if tools and not text and all(t in MECH for t in tools):
                s["mech"] += 1
            if side:
                continue
            c = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
            if c:
                series.append(c)
    except Exception:
        continue
    if len(series) < 5:
        continue
    drops = [i for i in range(1, len(series)) if series[i] < series[i - 1] * 0.6 and series[i - 1] > 50000]
    peaks = [series[i - 1] for i in drops]
    rows.append((proj, len(series), max(series), len(drops), peaks, sum(series)))

rows.sort(key=lambda r: -r[2])
print("sessions", len(rows))
mx = [r[2] for r in rows]
q = lambda p: sorted(mx)[min(len(mx) - 1, int(len(mx) * p))]
print("peak ctx: median %d p75 %d p90 %d max %d" % (st.median(mx), q(.75), q(.9), max(mx)))
for t in (100000, 150000, 200000, 300000, 500000):
    print(">%dk peak: %d sessions" % (t // 1000, sum(1 for x in mx if x > t)))
print("sessions with >=1 compaction:", sum(1 for r in rows if r[3]), " total compactions:", sum(r[3] for r in rows))
allpk = [p for r in rows for p in r[4]]
if allpk:
    print("ctx at compaction: median %d min %d max %d" % (st.median(allpk), min(allpk), max(allpk)))
print("sum ctx tokens over all turns: %d" % sum(r[5] for r in rows))
print("top 8 sessions: proj, turns, peak, compactions")
for r in rows[:8]:
    print(r[0], r[1], r[2], r[3])
print("model usage (main/sub: model): turns, mechanical-only turns, output tok, fresh-in tok, cache-read tok")
for k in sorted(models, key=lambda k: -models[k]["turns"]):
    s = models[k]
    print("%-40s %6d %6d %10d %12d %14d" % (k, s["turns"], s["mech"], s["out"], s["fresh"], s["cread"]))
