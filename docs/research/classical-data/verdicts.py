"""Hand-corrected verdicts over hits_auto.json (see the note for each correction)."""
import csv, json, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
auto = {h["id"]: h["hits"] for h in json.load(open(os.path.join(HERE, "hits_auto.json")))}
band = {r["id"]: r["band"] for r in csv.DictReader(open(os.path.join(HERE, "sample.tsv")), delimiter="\t")}
# id: (cedict_all, classical_en, unique classical source or "") -- only where the hand check differs
C_FIX = {"85": False, "116": False, "120": False, "125": False, "127": False, "150": False, "118": True}
K_FIX = {"14": False, "68": False, "70": False, "81": False, "82": False, "104": False, "108": False,
         "72": False, "121": False, "87": False}
MOE_RESCUES = {}   # MOE checked by hand on every C∪K miss: 夫子, 坐, 小, 宋, 昬, 衞 -- none
out = []
for i, h in auto.items():
    c = C_FIX.get(i, h["cedict_all"]); k = K_FIX.get(i, h["classical_en"])
    out.append((i, band[i], c, k))
with open(os.path.join(HERE, "verdicts.tsv"), "w") as f:
    f.write("id\tband\tcedict\tclassical\n")
    for i, b, c, k in out:
        f.write(f"{i}\t{b}\t{int(c)}\t{int(k)}\n")
def rate(rows):
    n = len(rows)
    return n, sum(r[2] for r in rows), sum(r[3] for r in rows), sum(r[2] or r[3] for r in rows)
print("band        n  cedict  classical  either")
for b in ["over", "top500", "500-3000", "rare", None]:
    rows = [r for r in out if b is None or r[1] == b]
    n, c, k, e = rate(rows)
    print(f"{b or 'all':10s} {n:3d}  {c:3d} {c/n:4.0%}  {k:3d} {k/n:4.0%}  {e:3d} {e/n:4.0%}")
