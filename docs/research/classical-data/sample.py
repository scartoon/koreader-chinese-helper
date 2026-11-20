"""Sample ~150 character occurrences from build/classical/texts for judging."""
import glob, os, random, sqlite3
import opencc
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
t2s = opencc.OpenCC("t2s")
rank = dict(sqlite3.connect(os.path.join(ROOT, "chinesehelper.koplugin/data/chinesehelper.sqlite")).execute(
    "SELECT ch, rank FROM chars"))
OVER = list("之其而焉乃且走去湯兵涕也矣以於為所者何安惡若莫或已遂既徒卒謝書信行是斯夫蓋爾宜故及自與將相尋坐再亡獄罪怨恨憐愛謀聞使遺請易")
occ = []
for f in sorted(glob.glob(os.path.join(HERE, "texts", "*.txt"))):
    name = os.path.basename(f)[:-4]
    for ln, line in enumerate(open(f).read().split("\n")[1:]):
        for i, c in enumerate(line):
            if "一" <= c <= "鿿":
                occ.append((name, ln, i, c, line))
rng = random.Random(49)
rng.shuffle(occ)
picked, used = [], {}
def take(pred, n, tag):
    for o in occ:
        if len([p for p in picked if p[-1] == tag]) >= n:
            return
        c = o[3]
        if used.get(c, 0) >= (2 if tag == "over" else 1) or any(p[:3] == o[:3] for p in picked):
            continue
        if pred(c):
            used[c] = used.get(c, 0) + 1
            picked.append(o + (tag,))
def r(c): return rank.get(t2s.convert(c)) or 99999
take(lambda c: c in OVER, 60, "over")
take(lambda c: c not in OVER and r(c) <= 500, 35, "top500")
take(lambda c: c not in OVER and 500 < r(c) <= 3000, 35, "500-3000")
take(lambda c: c not in OVER and r(c) > 3000, 20, "rare")
with open(os.path.join(HERE, "sample.tsv"), "w") as out:
    out.write("id\ttext\tchar\tsimp\trank\tband\tcontext\n")
    for k, (name, ln, i, c, line, _tag) in enumerate(picked, 1):
        a, b = max(0, i - 14), i + 15
        ctx = line[a:i] + "【" + c + "】" + line[i + 1:b]
        out.write(f"{k}\t{name}\t{c}\t{t2s.convert(c)}\t{r(c)}\t{picked[k-1][-1]}\t{ctx}\n")
print(len(picked))
