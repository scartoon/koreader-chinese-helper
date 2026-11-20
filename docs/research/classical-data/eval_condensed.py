import csv, json, os, re, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
recs = {}
for l in open(os.path.join(HERE, "condensed.jsonl")):
    r = json.loads(l); recs[(r["char"], r["variant"])] = r
samp = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t")}
judg = [j for j in csv.DictReader(open(os.path.join(HERE, "judgments.tsv")), delimiter="\t") if j["status"] == "ok"]
verd = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "verdicts.tsv")), delimiter="\t")}
mode = sys.argv[1] if len(sys.argv) > 1 else "sense"
if mode == "sense":
    for v in ("bundled", "local"):
        rows = []
        for j in judg:
            ch = samp[j["id"]]["char"]; kw = re.compile(j["keywords"], re.I)
            r = recs.get((ch, v)) or recs.get(({"説": "說", "衞": "衛"}.get(ch, ch), v))
            glosses = [s["gloss"] for s in (r["senses"] or [])] if r else []
            hit = next((g for g in glosses if kw.search(g)), None)
            rows.append((j["id"], ch, j["needed"], verd[j["id"]]["classical"] == "1", hit, glosses))
        raw = sum(x[3] for x in rows); kept = sum(1 for x in rows if x[3] and x[4]); cond = sum(1 for x in rows if x[4])
        print(f"{v}: raw English layer had it {raw}; condensed keeps it {kept}; condensed hits overall {cond}")
        for x in rows:
            if (x[3] and not x[4]) or (x[4] and not x[3]):
                print(f"  {x[0]} {x[1]} need: {x[2][:40]} | raw {'Y' if x[3] else 'n'} | cond: {x[4] or '-'} | {' / '.join(x[5])[:160]}")
else:
    STOP = set("a an the of to in on or and with for as by be is it its one's sth someone something used one that this from at into which who what".split())
    def words(t): return {w for w in re.findall(r"[a-z]+", t.lower()) if len(w) > 2 and w not in STOP}
    def stem(w): return w[:5]
    n = flagged = 0
    for (ch, v), r in sorted(recs.items()):
        inp = r["input"]; iw = {stem(w) for w in words(inp)}
        for s in r["senses"] or []:
            n += 1
            gw = {stem(w) for w in words(s["gloss"])}
            moe_only = s.get("sources") == ["MOE"]
            cover = len(gw & iw) / len(gw) if gw else 1
            if not moe_only and cover < 0.5:
                flagged += 1
                print(f"FLAG {ch} {v} {s['sources']} {s['gloss']}")
    print("senses", n, "flagged", flagged)
