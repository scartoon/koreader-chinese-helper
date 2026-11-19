#!/usr/bin/env python3
"""Compare the reader's own ranks (build/user-ranks.tsv, from
tools/build_user_ranks.py) with the bundled ones, offline (#42).

    python3 tools/compare_user_ranks.py [--threshold 3500] [--passage FILE:LINE ...]

Writes build/user-ranks-compare.md (crossing counts and the characters that
gain and lose pinyin) and build/user-ranks-pages.md (page-sized passages from
build/corpus/, each run through the plugin's own Lua at the threshold under
both rank sources: the characters that gain or lose pinyin, with the corpus
file and line so the same page can be found on the device). Only characters
are written, never passage text. Prints a short summary.
"""
import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import build_user_ranks as U  # noqa: E402

PAGE_HAN = 260   # about one Boox Go 7 landscape page at 64 px text (24 x 11)
# (corpus file, share of the way through the book): 临高启明 and a Ming history.
DEFAULT_PASSAGES = [("159", 0.2), ("159", 0.5), ("159", 0.8), ("158", 0.5),
                    ("172", 0.2), ("172", 0.5), ("172", 0.8)]


def read_ranks(path):
    rows, info = {}, {}
    for line in open(path, encoding="utf-8").read().splitlines():
        if line.startswith("#"):
            parts = line[1:].strip().split("\t")
            if len(parts) == 2:
                info[parts[0]] = parts[1]
            continue
        ch, r, w, n = line.split("\t")
        rows[ch] = (int(r), int(w), int(n))
    return rows, info


def crossings(public, user, threshold):
    """Simplified characters only (traditional forms and 〇 follow theirs)."""
    def drawn(r):
        return r == 0 or r > threshold
    gain, lose = [], []
    for ch, pub in public.rank.items():
        if ch in public.t2s or ch == "〇":
            continue
        u = user.get(ch, (pub,))[0]
        if drawn(u) and not drawn(pub):
            gain.append(ch)
        elif drawn(pub) and not drawn(u):
            lose.append(ch)
    return gain, lose


def passage(path, share, size=PAGE_HAN):
    """(line number, text) of the page-sized passage starting at the first
    line at least `share` of the way through the file with Chinese text."""
    lines = open(path, encoding="utf-8").read().splitlines()
    start = int(len(lines) * share)
    while start < len(lines) and len(U.HAN_RE.findall(lines[start])) < 20:
        start += 1
    out, han = [], 0
    for line in lines[start:]:
        need = size - han
        found = U.HAN_RE.findall(line)
        if len(found) > need:
            # cut the line after the need-th Han character
            k, seen = 0, 0
            for k, ch in enumerate(line):
                if U.HAN_RE.match(ch):
                    seen += 1
                    if seen == need:
                        break
            out.append(line[:k + 1])
            han = size
            break
        out.append(line)
        han += len(found)
        if han >= size:
            break
    return start + 1, "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ranks", default=U.OUT)
    ap.add_argument("--threshold", type=int, default=3500)
    ap.add_argument("--passage", nargs="*", metavar="FILE:SHARE",
                    help="corpus file and share of the way through (159:0.5); default: 临高启明 and 显微镜下的大明")
    args = ap.parse_args()
    public = U.Public.from_db()
    user, info = read_ranks(args.ranks)
    gain, lose = crossings(public, user, args.threshold)
    base = sum(1 for ch, r in public.rank.items()
               if ch not in public.t2s and ch != "〇" and 0 < r <= args.threshold)

    # 20 + 20: the gains with the smallest bundled ranks (common on the web,
    # rare in the books), the losses with the largest (or unranked).
    gain.sort(key=lambda ch: public.rank[ch])
    lose.sort(key=lambda ch: -public.sort_rank(ch))
    common_gain = [ch for ch in gain if public.rank[ch] <= 1000]

    def row(ch):
        r, w, n = user.get(ch, (None, 0, 0))
        pub = public.rank[ch] or "unranked"
        mine = f"{r:,}" if r else "absent"
        return f"| {ch} | {pub:,} | {mine} | {w} | {n:,} |" if isinstance(pub, int) else \
            f"| {ch} | {pub} | {mine} | {w} | {n:,} |"

    out = os.path.join(ROOT, "build", "user-ranks-compare.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write(f"# User ranks vs bundled, at {args.threshold:,}\n\n")
        f.write(f"File: {info.get('date')}, {info.get('works')} works, {int(info.get('han', 0)):,} Han characters, "
                f"{int(info.get('ranked', 0)):,} ranked, exact to {int(info.get('exact', 0)):,}.\n\n")
        f.write(f"Simplified characters within the bundled {args.threshold:,}: {base:,}.\n\n")
        f.write(f"- gain pinyin (bundled <= {args.threshold:,}, mine above): {len(gain):,} "
                f"({len(gain) / base:.1%}); of them bundled <= 1,000: {len(common_gain)}\n")
        f.write(f"- lose pinyin (bundled above or unranked, mine <= {args.threshold:,}): {len(lose):,} "
                f"({len(lose) / base:.1%})\n\n")
        for title, chars in (("Gain pinyin (smallest bundled rank first)", gain),
                             ("Lose pinyin (largest bundled rank first)", lose)):
            f.write(f"## {title}\n\n| char | bundled | mine | works | occurrences |\n|---|---|---|---|---|\n")
            for ch in chars[:20]:
                f.write(row(ch) + "\n")
            f.write("\n")
        f.write(f"## Every character that gains pinyin\n\n{''.join(gain)}\n\n")
        f.write(f"## Every character that loses pinyin\n\n{''.join(lose)}\n")

    # The page check, through the plugin's own Lua.
    from plugin_runtime import Plugin
    plugin = Plugin()
    lua = plugin.lua
    parsed = lua.require("ch_ranks").load(args.ranks)
    if isinstance(parsed, tuple):
        parsed = parsed[0]
    set_ranks = lua.eval("function(d, p) if p then d:setUserRanks(p.ranks, p.info.exact) else d:setUserRanks(nil) end end")
    specs = [(s.split(":")[0], float(s.split(":")[1])) for s in args.passage] if args.passage else DEFAULT_PASSAGES
    names = dict(U.read_index(U.CORPUS))
    pages_out = os.path.join(ROOT, "build", "user-ranks-pages.md")
    summary = []
    with open(pages_out, "w", encoding="utf-8") as f:
        f.write(f"# Page check at Which characters {args.threshold:,}: bundled vs my books\n\n")
        f.write(f"Passages of {PAGE_HAN} Han characters (about one Boox Go 7 landscape page) from build/corpus/, "
                "run through Resolve.annotate (tools/plugin_runtime.py) under both rank sources. "
                "Line: the passage's first line in build/corpus/<file>.txt (1-based).\n\n")
        for key, share in specs:
            line_no, text = passage(os.path.join(U.CORPUS, key + ".txt"), share)
            set_ranks(plugin.data, None)
            before = {p: ch for p, ch, *_ in plugin.details(text, args.threshold)}
            set_ranks(plugin.data, parsed)
            after = {p: ch for p, ch, *_ in plugin.details(text, args.threshold)}
            set_ranks(plugin.data, None)
            gained = sorted({after[p] for p in after if p not in before})
            lost = sorted({before[p] for p in before if p not in after})
            title = names.get(key, key).split(" -- ")[0].split(" (")[0][:30]
            f.write(f"## {key}.txt line {line_no} ({title})\n\n")
            f.write(f"- drawn: bundled {len(before)}, mine {len(after)}\n")
            f.write(f"- gain pinyin: {' '.join(gained) or '-'}\n")
            f.write(f"- lose pinyin: {' '.join(lost) or '-'}\n\n")
            summary.append((key, line_no, title, len(before), len(after), gained, lost))
    print(f"at {args.threshold:,}: {len(gain)} gain pinyin, {len(lose)} lose it (of {base:,}); "
          f"{len(common_gain)} gainers are bundled <= 1,000")
    for key, line_no, title, nb, na, g, l in summary:
        print(f"  {key}:{line_no} drawn {nb} -> {na}, +{len(g)} -{len(l)}")
    print(f"-> {out}\n-> {pages_out}")


if __name__ == "__main__":
    main()
