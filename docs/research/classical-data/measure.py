"""Step 5: which sources have the judged sense, by keyword; misses listed for hand review."""
import csv, json, os, re, sqlite3, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
DB = os.path.join(ROOT, "chinesehelper.koplugin/data/chinesehelper.sqlite")
sample = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t")}
judg = [r for r in csv.DictReader(open(os.path.join(HERE, "judgments.tsv")), delimiter="\t") if r["status"] == "ok"]
coll = collections.defaultdict(lambda: collections.defaultdict(list))
for r in csv.DictReader(open(os.path.join(HERE, "collated.tsv")), delimiter="\t"):
    if r["source"] == "unihan" and r["tag"] != "rare":
        continue
    for k in {r["trad"], r["simp"]}:
        coll[k][r["source"]].append(r["sense"])
con = sqlite3.connect(DB)
def cedict(ch):
    return [d for (d,) in con.execute("SELECT defs FROM entries WHERE simp=? OR trad=?", (ch, ch))]
over = {"over": [], "top500": [], "500-3000": [], "rare": []}
res = []
for j in judg:
    s = sample[j["id"]]; ch = s["char"]
    kw = re.compile(j["keywords"], re.I)
    hits = {"cedict_all": any(kw.search(d) for d in cedict(ch))}
    for src in ("cedict", "wikt", "cn", "unihan", "moe"):
        hits[src] = any(kw.search(x) for x in coll[ch][src] + (coll[s["simp"]][src] if s["simp"] != ch else []))
    hits["classical_en"] = any(hits[x] for x in ("cedict", "wikt", "cn", "unihan"))
    res.append((j, s, hits))
json.dump([{"id": j["id"], "hits": h} for j, s, h in res], open(os.path.join(HERE, "hits_auto.json"), "w"))
n = len(res)
for key in ("cedict_all", "cedict", "wikt", "cn", "unihan", "moe", "classical_en"):
    print(f"{key:13s} {sum(h[key] for _, _, h in res):4d}/{n}")
both = sum(h["cedict_all"] or h["classical_en"] for _, _, h in res)
print(f"cedict_all OR classical_en {both}/{n}")
if "-v" in sys.argv:
    for j, s, h in res:
        if not h["classical_en"] or not h["cedict_all"]:
            print(j["id"], s["char"], "|", j["needed"], "| CED" if h["cedict_all"] else "| ---", "CLS" if h["classical_en"] else "---")
if "-m" in sys.argv:
    for j, s, h in res:
        kw = re.compile(j["keywords"], re.I); ch = s["char"]
        def first(lst):
            for d in lst:
                for part in d.split("/"):
                    if kw.search(part): return part[:55]
            return "-"
        ced = first(cedict(ch))
        cls = "-"
        for src in ("cn", "wikt", "cedict", "unihan"):
            f = first(coll[ch][src] + (coll[s["simp"]][src] if s["simp"] != ch else []))
            if f != "-": cls = src + ":" + f; break
        print(f'{j["id"]}\t{ch}\t{j["needed"][:38]}\tC: {ced}\tK: {cls}')
