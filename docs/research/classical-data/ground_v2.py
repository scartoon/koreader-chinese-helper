import json, re, sys, collections
STOP = set("a an the of to in on or and with for as by be is it its one's sth someone something used one that this from at into which who what also etc e.g".split())
def words(t): return {w[:5] for w in re.findall(r"[a-z]+", t.lower()) if len(w) > 2 and w not in STOP}
f = sys.argv[1] if len(sys.argv) > 1 else "build/classical/condensed.jsonl"
n = flagged = moe_cited = 0; out = []
for l in open(f):
    r = json.loads(l)
    lines = {int(x.split(". ", 1)[0]): x.split(". ", 1)[1] for x in r["input"].split("\n")[1:]}
    for s in r["senses"] or []:
        n += 1
        cited = [c for c in s.get("lines", []) if c in lines]
        if any(lines[c].startswith("[MOE]") for c in cited):
            moe_cited += 1
            if all(lines[c].startswith("[MOE]") for c in cited):
                continue
        eng = " ".join(lines[c] for c in cited if not lines[c].startswith("[MOE]"))
        gw = words(s["gloss"]); cover = len(gw & words(eng)) / len(gw) if gw else 1
        if not cited or s.get("bad_lines") or cover < 0.5:
            flagged += 1
            out.append(f"FLAG {r['char']} {r['variant']} lines={s.get('lines')} cover={cover:.2f} | {s['gloss']} || " + " | ".join(lines[c][:60] for c in cited))
print("\n".join(out)); print("senses", n, "flagged", flagged, "MOE-only senses (not checkable by words)", moe_cited)
