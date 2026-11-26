#!/usr/bin/env python3
"""#87 steps 1-2: how much CBDB would add to the popup, per category, and how
often it would be right.

    .venv/bin/python tools/measure_cbdb.py taps [--per-book 3000]   # simulated taps -> build/measure/cbdb/
    .venv/bin/python tools/measure_cbdb.py sample                   # judging batches
    .venv/bin/python tools/measure_cbdb.py report                   # with verdicts -> report.md

Categories, each indexed under its CBDB form and OpenCC t2s:
  person   BIOG_MAIN.c_name_chn (2-8 Han characters)
  alt      ALTNAME_DATA.c_alt_name_chn, with its type (字, 室名、別號, 諡號 ...)
  office   OFFICE_CODES.c_office_chn and its alternatives, with dynasty
  place    ADDR_CODES.c_name_chn and its alternatives
  book     TEXT_CODES.c_title_chn

Taps are the same simulation as measure_fallback.py (the plugin's own
candidate code, run in lupa, on a seeded sample of Han characters per book of
build/corpus/). A hit is a candidate word (2+ characters) that a category has.
Two modes:
  always    every hit (#88's default: CBDB shown even when CC-CEDICT has the word)
  fallback  only hits that CC-CEDICT, Wiktionary, Wikipedia titles, the
            Classical dictionary and MOE all lack

Nothing here is used by the plugin, and nothing from CBDB is committed: the
outputs stay in build/ (gitignored).
"""
import argparse
import collections
import csv
import glob
import os
import pickle
import random
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure_fallback as mf  # noqa: E402

ROOT = mf.ROOT
OUT = os.path.join(ROOT, "build", "measure", "cbdb")
CBDB = sorted(glob.glob(os.path.join(ROOT, "build", "sources", "cbdb", "db", "*.sqlite3")))[-1]
MOE = os.path.join(ROOT, "build", "chinesehelper-moe.sqlite")
CATS = ["person", "alt", "office", "place", "book"]
HAN2 = re.compile(f"[{mf.HAN}]{{2,8}}")
# Endings of modern titles: CBDB has some as historical offices (副总裁 Ming, 副局长 Jin), but books use them
# in today's sense.
MODERN_TITLE = ("局长", "总裁", "经理", "主任", "处长", "科长", "部长", "厂长", "主席", "书记", "董事", "秘书",
                "会长", "院长", "校长", "所长", "司长", "厅长", "省长", "市长", "县长", "镇长", "乡长", "村长",
                "队长", "组长", "社长", "台长", "站长", "行长", "总监", "委员", "代表", "教授", "讲师", "干部",
                "警官", "律师", "总统", "总理", "议员", "大使", "领事", "主编")
ADMIN_SUFFIX = set("州府縣县郡軍军路道衛卫所鎮镇廳厅監监司寨堡城")


def load_cbdb():
    """{cat: {form: [info dicts]}} and per-person documentation counts."""
    t2s, _s2t, _tw = mf.converters()
    con = sqlite3.connect(f"file:{CBDB}?mode=ro", uri=True)
    dyn = dict(con.execute("SELECT c_dy, c_dynasty_chn FROM DYNASTIES"))
    docs = collections.Counter()
    for table in ("POSTED_TO_OFFICE_DATA", "ENTRY_DATA", "ALTNAME_DATA", "BIOG_ADDR_DATA", "STATUS_DATA",
                  "BIOG_TEXT_DATA", "KIN_DATA", "ASSOC_DATA"):
        for pid, n in con.execute(f"SELECT c_personid, count(*) FROM {table} GROUP BY c_personid"):
            docs[pid] += n
    people = {}
    for pid, name, iy, by, dy, d in con.execute(
            "SELECT c_personid, c_name_chn, c_index_year, c_birthyear, c_deathyear, c_dy FROM BIOG_MAIN"):
        people[pid] = {"pid": pid, "name": name, "iy": iy or 0, "by": by or 0, "dy": dy or 0,
                       "dyn": dyn.get(d, ""), "docs": docs[pid]}
    idx = {c: collections.defaultdict(list) for c in CATS}

    def put(cat, form, info):
        if not form:
            return
        for f in {form, t2s.convert(form)}:
            if HAN2.fullmatch(f):
                idx[cat][f].append(info)

    for p in people.values():
        put("person", p["name"], p)
    types = dict(con.execute("SELECT c_name_type_code, c_name_type_desc_chn FROM ALTNAME_CODES"))
    for pid, alt, code in con.execute("SELECT c_personid, c_alt_name_chn, c_alt_name_type_code FROM ALTNAME_DATA"):
        p = people.get(pid)
        if p:
            put("alt", alt, dict(p, type=types.get(code, "?")))
    for oid, d, chn, alt, tr in con.execute(
            "SELECT c_office_id, c_dy, c_office_chn, c_office_chn_alt, c_office_trans FROM OFFICE_CODES"):
        info = {"oid": oid, "dyn": dyn.get(d, ""), "en": "" if (tr or "").startswith("[") else (tr or "")}
        put("office", chn, info)
        for a in re.split(r"[;；,，、/ ]+", alt or ""):
            put("office", a, info)
    for aid, chn, alts, at in con.execute("SELECT c_addr_id, c_name_chn, c_alt_names, c_admin_type FROM ADDR_CODES"):
        info = {"aid": aid, "admin": at or ""}
        put("place", chn, info)
        for a in re.split(r"[;；,，、/ ]+", alts or ""):
            put("place", a, info)
    for tid, title, tr in con.execute("SELECT c_textid, c_title_chn, c_title_trans FROM TEXT_CODES"):
        put("book", title, {"tid": tid, "en": tr or ""})
    con.close()
    return idx


def other_dicts():
    """(cedict forms, forms of every other dictionary the popup consults)."""
    con = sqlite3.connect(mf.DB)
    cedict, other = set(), set()
    for s, t in con.execute("SELECT simp, trad FROM entries"):
        cedict.update((s, t))
    for s, t in con.execute("SELECT simp, trad FROM fallback"):
        other.update((s, t))
    for s, t in con.execute("SELECT simp, trad FROM classical"):
        other.update((s, t))
    con.close()
    if os.path.exists(MOE):
        m = sqlite3.connect(MOE)
        for s, t in m.execute("SELECT simp, trad FROM fallback"):
            other.update((s, t))
        m.close()
    return cedict, other


def stage_taps(per_book, seed):
    os.makedirs(OUT, exist_ok=True)
    print("Loading CBDB ...")
    idx = load_cbdb()
    for c in CATS:
        print(f"  {c}: {len(idx[c]):,} forms")
    cedict, other = other_dicts()
    taps = []
    for book, para, i, cands, left, right, bounds in mf.tap_samples(per_book, seed):
        hits = []
        for text, start, length in cands:
            if length < 2:
                continue
            cats = [c for c in CATS if text in idx[c]]
            if not cats:
                continue
            a, b = i + start, i + start + length
            hits.append({"word": text, "len": length, "cats": cats, "cedict": text in cedict,
                         "other": text in other, "aligned": a in bounds and b in bounds,
                         "sent": para[max(0, a - 25):b + 25], "at": a - max(0, a - 25)})
        taps.append({"book": book, "hits": hits})
    # Only the infos of words hit, to keep the pickle small.
    words = {h["word"] for t in taps for h in t["hits"]}
    info = {c: {w: idx[c][w] for w in words if w in idx[c]} for c in CATS}
    with open(os.path.join(OUT, "taps.pickle"), "wb") as f:
        pickle.dump({"taps": taps, "info": info, "cbdb": os.path.basename(CBDB)}, f)
    print(f"  {len(taps):,} taps, {sum(1 for t in taps if t['hits']):,} with a CBDB hit")


def load_taps():
    with open(os.path.join(OUT, "taps.pickle"), "rb") as f:
        return pickle.load(f)


def features(cat, h, info):
    """Filter features for one hit."""
    infos = info[cat][h["word"]]
    before, after = h["sent"][h["at"] - 1:h["at"]], h["sent"][h["at"] + h["len"]:h["at"] + h["len"] + 1]
    f = {"word": h["word"], "dictword": h["cedict"] or h["other"], "len": h["len"], "aligned": h["aligned"], "n": len(infos),
         "quoted": before in ("《", "〈") or after in ("》", "〉")}
    if cat in ("person", "alt"):
        f["docs"] = max(p["docs"] for p in infos)
        f["iy"] = any(p["iy"] for p in infos)
        f["dated"] = any(p["by"] or p["dy"] for p in infos)
        if cat == "alt":
            f["type"] = collections.Counter(p["type"] for p in infos).most_common(1)[0][0]
    if cat == "office":
        f["en"] = any(o["en"] for o in infos)
        f["dyn"] = "/".join(sorted({o["dyn"] for o in infos}))[:30]
    if cat == "place":
        f["suffix"] = h["word"][-1] in ADMIN_SUFFIX
    if cat == "book":
        f["en"] = any(b["en"] for b in infos)
    return f


def gloss(cat, w, info):
    infos = info[cat][w]
    if cat in ("person", "alt"):
        top = sorted(infos, key=lambda p: -p["docs"])[:3]
        return "; ".join(f"{p['name']}{'(' + p.get('type', '') + ')' if cat == 'alt' else ''} {p['dyn']} "
                         f"{p['by'] or ''}-{p['dy'] or ''} docs={p['docs']}" for p in top) + \
            (f" (+{len(infos) - 3} more)" if len(infos) > 3 else "")
    if cat == "office":
        return "; ".join(f"{o['dyn']} {o['en']}" for o in infos[:3])
    if cat == "place":
        return "; ".join(o["admin"] for o in infos[:3])
    return "; ".join(o["en"] for o in infos[:2])


def stage_sample(n_always, n_fallback, seed):
    d = load_taps()
    rnd = random.Random(seed)
    rows = []
    for cat in CATS:
        hits = [h for t in d["taps"] for h in t["hits"] if cat in h["cats"]]
        fb = [h for h in hits if not h["cedict"] and not h["other"]]
        pick = [(h, "always") for h in rnd.sample(hits, min(n_always, len(hits)))]
        ids = {id(h) for h, _ in pick}
        rest = [h for h in fb if id(h) not in ids]
        pick += [(h, "fallback") for h in rnd.sample(rest, min(n_fallback, len(rest)))]
        for h, pool in pick:
            s = h["sent"].replace("\t", " ").replace("\n", " ")
            ctx = s[:h["at"]] + "【" + h["word"] + "】" + s[h["at"] + h["len"]:]
            rows.append({"pool": pool, "cat": cat, "word": h["word"], "context": ctx, "cbdb": gloss(cat, h["word"], d["info"]),
                         **{k: v for k, v in features(cat, h, d["info"]).items()}})
    rnd.shuffle(rows)
    os.makedirs(os.path.join(OUT, "judge"), exist_ok=True)
    keys = ["id", "cat", "word", "context", "cbdb"]
    per = 60
    for b in range(0, len(rows), per):
        with open(os.path.join(OUT, "judge", f"batch-{b // per:02d}.tsv"), "w", encoding="utf-8") as f:
            f.write("\t".join(keys) + "\n")
            for k, r in enumerate(rows[b:b + per]):
                r["id"] = b + k
                f.write("\t".join(str(r[x]) for x in keys) + "\n")
    with open(os.path.join(OUT, "sample.pickle"), "wb") as f:
        pickle.dump(rows, f)
    print(f"  {len(rows)} hits in {(len(rows) + per - 1) // per} batches in {OUT}/judge/")


TARGETS = {
    "person": ("3+ chars, aligned, docs >= 10",
               lambda f: f["len"] >= 3 and f["aligned"] and f["docs"] >= 10),
    "alt": ("aligned, not dictionary word, docs >= 30",
            lambda f: f["aligned"] and not f["dictword"] and f["docs"] >= 30),
    "office": ("3+ chars, aligned, not a modern title",
               lambda f: f["len"] >= 3 and f["aligned"] and not f["word"].endswith(MODERN_TITLE)),
    "place": ("3+ chars, aligned, admin suffix", lambda f: f["len"] >= 3 and f["aligned"] and f["suffix"]),
    "book": ("in 《》, or 3+ chars and not a dictionary word",
             lambda f: f.get("quoted") or (f["len"] >= 3 and not f["dictword"])),
}


def filter_rates(d):
    """{cat: (taps per 1,000 with a hit passing the target filter, always; fallback)}"""
    n, res = len(d["taps"]), {}
    for cat, (_name, fn) in TARGETS.items():
        a = fb = 0
        for t in d["taps"]:
            ok = [h for h in t["hits"] if cat in h["cats"] and fn(features(cat, h, d["info"]))]
            a += bool(ok)
            fb += any(not h["cedict"] and not h["other"] for h in ok)
        res[cat] = (1000 * a / n, 1000 * fb / n)
    return res


def stage_sample2(n_target, seed):
    """Round 2: n_target hits per category that pass its TARGETS filter, not judged in round 1."""
    d = load_taps()
    rnd = random.Random(seed + 2)
    with open(os.path.join(OUT, "sample.pickle"), "rb") as f:
        rows = pickle.load(f)
    seen = {(r["word"], r["context"]) for r in rows}
    new = []
    for cat, (name, fn) in TARGETS.items():
        hits = [h for t in d["taps"] for h in t["hits"] if cat in h["cats"] and fn(features(cat, h, d["info"]))]
        rnd.shuffle(hits)
        k = 0
        for h in hits:
            if k >= n_target:
                break
            s = h["sent"].replace("\t", " ").replace("\n", " ")
            ctx = s[:h["at"]] + "【" + h["word"] + "】" + s[h["at"] + h["len"]:]
            if (h["word"], ctx) in seen:
                continue
            seen.add((h["word"], ctx))
            new.append({"pool": "target", "cat": cat, "word": h["word"], "context": ctx,
                        "cbdb": gloss(cat, h["word"], d["info"]), **features(cat, h, d["info"])})
            k += 1
    rnd.shuffle(new)
    keys, per, base = ["id", "cat", "word", "context", "cbdb"], 60, len(rows)
    for b in range(0, len(new), per):
        with open(os.path.join(OUT, "judge", f"batch-{(base + b) // per:02d}.tsv"), "w", encoding="utf-8") as f:
            f.write("\t".join(keys) + "\n")
            for k, r in enumerate(new[b:b + per]):
                r["id"] = base + b + k
                f.write("\t".join(str(r[x]) for x in keys) + "\n")
    with open(os.path.join(OUT, "sample.pickle"), "wb") as f:
        pickle.dump(rows + new, f)
    print(f"  {len(new)} more hits, batches from {base // per:02d}")


def stage_report():
    d = load_taps()
    taps = d["taps"]
    n = len(taps)
    with open(os.path.join(OUT, "sample.pickle"), "rb") as f:
        rows = pickle.load(f)
    rates = filter_rates(d)
    verdict = {}
    for p in glob.glob(os.path.join(OUT, "judge", "verdicts-*.tsv")):
        for r in csv.DictReader(open(p, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE):
            verdict[int(r["id"])] = r["verdict"].strip().lower()
    rows = [r for r in rows if r["id"] in verdict]
    out = [f"# CBDB in the popup (#87): {d['cbdb']}, {n:,} simulated taps on {len({t['book'] for t in taps})} books",
           "", "Taps per 1,000 tapped characters with at least one hit in the category (always / fallback mode).", "",
           "| Category | Always | Fallback | Distinct words hit (always) |", "|---|---:|---:|---:|"]
    for cat in CATS:
        a = sum(1 for t in taps if any(cat in h["cats"] for h in t["hits"]))
        fb = sum(1 for t in taps if any(cat in h["cats"] and not h["cedict"] and not h["other"] for h in t["hits"]))
        words = len({h["word"] for t in taps for h in t["hits"] if cat in h["cats"]})
        out.append(f"| {cat} | {1000 * a / n:.1f} | {1000 * fb / n:.1f} | {words:,} |")
    anyc = sum(1 for t in taps if t["hits"])
    out += ["", f"Any category: {1000 * anyc / n:.1f} per 1,000 taps (always).", ""]
    # The "always" pool is uniform over all hits; the "fallback" pool adds hits no dictionary has. Filters
    # that keep only such hits use both pools (both uniform over them), the others the always pool only.
    filters = {
        "all": lambda r: True,
        "fallback only (no dictionary has it)": lambda r: not r["dictword"],
        "not a dictionary word, 3+ chars": lambda r: not r["dictword"] and r["len"] >= 3,
        "3+ chars": lambda r: r["len"] >= 3,
        "jieba-aligned": lambda r: r["aligned"],
        "aligned, not dictionary word": lambda r: r["aligned"] and not r["dictword"],
        "docs >= 10": lambda r: r.get("docs", 0) >= 10,
        "docs >= 30": lambda r: r.get("docs", 0) >= 30,
        "docs >= 10, 3+ chars": lambda r: r.get("docs", 0) >= 10 and r["len"] >= 3,
        "dated (birth or death year)": lambda r: r.get("dated", False),
        "type 字": lambda r: r.get("type") == "字",
        "type 室名、別號": lambda r: r.get("type") == "室名、別號",
        "type 諡號": lambda r: r.get("type") == "諡號",
        "with English": lambda r: r.get("en", False),
        "admin suffix": lambda r: r.get("suffix", False),
        "admin suffix, 3+ chars": lambda r: r.get("suffix", False) and r["len"] >= 3,
    }
    for cat in CATS:
        rs = [r for r in rows if r["cat"] == cat and r["id"] in verdict]
        out += [f"## {cat}", "", f"{len(rs)} judged hits.", "", "| Filter | Judged | Right | Precision |",
                "|---|---:|---:|---:|"]
        for name, fn in filters.items():
            fallback_only = "dictionary" in name and "not" in name or name.startswith("fallback only")
            sub = [r for r in rs if fn(r) and (r["pool"] == "always" or (fallback_only and r["pool"] == "fallback"))]
            if len(sub) < 10:
                continue
            ok = sum(1 for r in sub if verdict[r["id"]] == "yes")
            out.append(f"| {name} | {len(sub)} | {ok} | {100 * ok / len(sub):.0f}% |")
        tname, tfn = TARGETS[cat]
        tr = [r for r in rs if r["pool"] in ("target", "always") and tfn(r)]
        if tr:
            ok = sum(1 for r in tr if verdict[r["id"]] == "yes")
            fbr = [r for r in tr if not r["dictword"]]
            okf = sum(1 for r in fbr if verdict[r["id"]] == "yes")
            a, f = rates[cat]
            out += ["", f"**Round 2 filter: {tname}.** {len(tr)} judged, {ok} right: {100 * ok / len(tr):.0f}% "
                    f"(no dictionary has it: {okf}/{len(fbr)}). Shows on {a:.1f} taps per 1,000 (always), "
                    f"{f:.1f} (fallback)."]
        out.append("")
    path = os.path.join(OUT, "report.md")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stage", choices=["taps", "sample", "sample2", "report"])
    ap.add_argument("--per-book", type=int, default=3000)
    ap.add_argument("--always", type=int, default=120)
    ap.add_argument("--fallback", type=int, default=60)
    ap.add_argument("--target", type=int, default=100)
    ap.add_argument("--seed", type=int, default=87)
    args = ap.parse_args()
    if args.stage == "taps":
        stage_taps(args.per_book, args.seed)
    elif args.stage == "sample":
        stage_sample(args.always, args.fallback, args.seed)
    elif args.stage == "sample2":
        stage_sample2(args.target, args.seed)
    else:
        stage_report()


if __name__ == "__main__":
    main()
