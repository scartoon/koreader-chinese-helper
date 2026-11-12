#!/usr/bin/env python3
"""What one book still lacks after every dictionary the plugin has, and what
candidate sources would add for it. Nothing here is used by the plugin.

    python3 tools/fetch_books.py --local linggao BOOK.epub ...   # build/corpus/linggao-*.txt
    python3 tools/measure_book.py --book linggao                 # Step 1: build/measure/linggao-report.md
    python3 tools/measure_book.py --book linggao --stage sources,eval   # Step 2: linggao-sources.md

Reuses tools/measure_fallback.py (--book corpus selection, jieba with the big
dictionary, the simulated taps through the plugin's own ch_text.lua, the
Wikipedia dump parser, db_size) and tools/fallback_sources.py (everyday()).

"Current sources" are the tables as built, which is what the popup consults:
CC-CEDICT and the Wiktionary fallback from the plugin database, and the MOE
file from tools/build_moe.py (build/chinesehelper-moe.sqlite). A word is
"known" if any of them has it, in either script.

Stages (cached as build/measure/BOOK/book-STAGE.pickle):

  base      the known headwords, and the book's paragraphs with their chapters.
  discover  new-word discovery on the book: Han n-grams of 2-6 characters seen
            at least MIN_COUNT times, with high cohesion (every split's
            pointwise mutual information) and free boundaries (left and right
            neighbour entropy). jieba's dictionary does not have the book's own
            words (元老院, 归化民, 髡贼), so segmenting with jieba alone would
            break them into pieces and never see them as missing.
  segment   the book segmented with jieba (big dictionary, HMM off) plus the
            discovered words: every token's count, the Han characters it
            covers, its first chapter and the number of chapters it is in.
  report    Step 1 report: the missing words (2+ Han characters, known to no
            current source), frequency ranked; a rough category split; the
            share of running text they make up; CC-CEDICT words the book uses
            far more than general Chinese (candidates for in-universe senses).
  sources   Step 2 candidate sources, indexed like measure_fallback's sources:
            Moegirlpedia (tools/moegirl_slob.py), Chinese Wikipedia titles
            (3+ characters, science/technology/engineering/military/history
            categories), CBDB Ming office titles.
  eval      Step 2 report: each source against the missing words (by
            category), simulated taps (false matches), samples and size.
"""
import argparse
import collections
import math
import os
import pickle
import random
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure_fallback as mf  # noqa: E402
from fallback_sources import everyday, cedict_forms as cedict_forms_measure  # noqa: E402

ROOT = mf.ROOT
BUILD = mf.BUILD
DB = mf.DB
MOE_FILE = os.path.join(BUILD, "chinesehelper-moe.sqlite")
HAN_CHAR = mf.HAN_CHAR
HAN_RUN = re.compile(f"[{mf.HAN}]+")
CHAPTER = re.compile(r"^第[0-9０-９一二三四五六七八九十百千零〇两]+[章节節回]")
VOLUME = re.compile(r"^第[0-9０-９一二三四五六七八九十百千零〇]+卷")

MIN_COUNT = 10          # discovery: n-gram seen at least this often
MAX_N = 6
MIN_ENTROPY = 1.0       # discovery: left and right neighbour entropy (nats)
MIN_PMI = 3.0           # discovery: weakest split's PMI (natural log)

OUT = None
BOOK = None


def cache(name):
    """build/measure/BOOK/book-NAME.pickle: prefixed, since measure_fallback.py
    --book BOOK keeps its own caches (sources, gaps, taps) in the same folder."""
    return os.path.join(OUT, f"book-{name}.pickle")


def save(name, obj):
    os.makedirs(OUT, exist_ok=True)
    with open(cache(name), "wb") as f:
        pickle.dump(obj, f)


def load(name):
    with open(cache(name), "rb") as f:
        return pickle.load(f)


def pct(a, b):
    return f"{100 * a / b:.1f}%" if b else "-"


# ---------------------------------------------------------------------------
# base
# ---------------------------------------------------------------------------


def known_forms():
    """{"cedict": set, "wikt": set, "moe": set} of headword forms as built."""
    con = sqlite3.connect(DB)
    out = {"cedict": set(), "wikt": set(), "moe": set()}
    for simp, trad in con.execute("SELECT simp, trad FROM entries"):
        out["cedict"].update((simp, trad))
    for simp, trad in con.execute("SELECT simp, trad FROM fallback WHERE source = 'wikt'"):
        out["wikt"].update((simp, trad))
    resolver = {w for (w,) in con.execute("SELECT word FROM words")}
    con.close()
    if not os.path.exists(MOE_FILE):
        sys.exit(f"{MOE_FILE} missing: build it with tools/build_moe.py")
    m = sqlite3.connect(MOE_FILE)
    for simp, trad in m.execute("SELECT simp, trad FROM fallback"):
        out["moe"].update((simp, trad))
    m.close()
    return out, resolver


CN_DIGITS = {c: i for i, c in enumerate("零一二三四五六七八九")}


def volume_number(heading):
    """第七卷 -> 7, 第十二卷 -> 12, 第3卷 -> 3 (0 when unreadable)."""
    m = VOLUME.match(heading)
    s = m.group(0)[1:-1] if m else ""
    if s.isdigit():
        return int(s)
    if s.startswith("十"):
        s = "一" + s
    n, cur = 0, 0
    for c in s:
        if c == "十":
            n += (cur or 1) * 10
            cur = 0
        elif c in CN_DIGITS:
            cur = CN_DIGITS[c]
    return n + cur


def stage_base():
    known, resolver = known_forms()
    _, measure = cedict_forms_measure(DB)
    books = []
    for path in mf.corpus_files():
        name = os.path.basename(path)[:-4]
        paras, chapters = [], []
        vol, chap = "", "(front matter)"
        for line in open(path, encoding="utf-8"):
            p = line.rstrip("\n")
            if VOLUME.match(p):
                vol = p[:30]
            if CHAPTER.match(p):
                chap = p[:30]
            paras.append(p)
            chapters.append(f"{vol} {chap}".strip())
        books.append({"name": name, "paras": paras, "chapters": chapters,
                      "first_volume": next((volume_number(p) for p in paras if VOLUME.match(p)), 0)})
    # Reading order (first appearance means first in the story), not file order.
    books.sort(key=lambda b: (b["first_volume"], b["name"]))
    save("base", {"known": known, "resolver": resolver, "measure": measure, "books": books})
    print(f"  known forms: " + ", ".join(f"{k} {len(v):,}" for k, v in known.items()))
    print(f"  {len(books)} files, {sum(len(b['paras']) for b in books):,} paragraphs")


# ---------------------------------------------------------------------------
# discover
# ---------------------------------------------------------------------------


def entropy(counter):
    n = sum(counter.values())
    return -sum(c / n * math.log(c / n) for c in counter.values()) if n else 0.0


def stage_discover():
    base = load("base")
    runs = [r for b in base["books"] for p in b["paras"] for r in HAN_RUN.findall(p)]
    total = sum(len(r) for r in runs)
    counts = {1: collections.Counter(c for r in runs for c in r)}
    for n in range(2, MAX_N + 1):
        prev = counts[n - 1]
        cn = collections.Counter()
        for r in runs:
            for i in range(len(r) - n + 1):
                g = r[i:i + n]
                if n == 2 or (prev.get(g[:-1], 0) >= MIN_COUNT and prev.get(g[1:], 0) >= MIN_COUNT):
                    cn[g] += 1
        counts[n] = collections.Counter({g: c for g, c in cn.items() if c >= MIN_COUNT}) if n > 2 else cn
        print(f"  {n}-grams counted: {len(counts[n]):,}", flush=True)
    counts[2] = collections.Counter({g: c for g, c in counts[2].items() if c >= MIN_COUNT})

    def count(g):
        return counts[len(g)].get(g, 0)

    cands = {}
    for n in range(2, MAX_N + 1):
        for g, c in counts[n].items():
            pmi = min(math.log(c * total / (count(g[:k]) * count(g[k:]))) for k in range(1, n)
                      if count(g[:k]) and count(g[k:])) if n > 1 else 0
            if pmi >= MIN_PMI:
                cands[g] = [c, pmi]
    left = collections.defaultdict(collections.Counter)
    right = collections.defaultdict(collections.Counter)
    edge = 0
    for r in runs:
        for n in range(2, MAX_N + 1):
            for i in range(len(r) - n + 1):
                g = r[i:i + n]
                if g in cands:
                    edge += 1
                    # A run boundary counts as a distinct neighbour each time.
                    left[g][r[i - 1] if i > 0 else f"^{edge}"] += 1
                    right[g][r[i + n] if i + n < len(r) else f"${edge}"] += 1
    words = {}
    for g, (c, pmi) in cands.items():
        le, re_ = entropy(left[g]), entropy(right[g])
        if min(le, re_) >= MIN_ENTROPY:
            words[g] = {"count": c, "pmi": pmi, "le": le, "re": re_}
    save("discover", {"words": words, "total": total})
    known = set().union(*base["known"].values())
    new = {w for w in words if w not in known}
    print(f"  {len(words):,} discovered words, {len(new):,} known to no current source")


# ---------------------------------------------------------------------------
# segment
# ---------------------------------------------------------------------------


def jieba_with(words):
    """measure_fallback's jieba (big dictionary), with the discovered words
    added: the same instance tap_samples() uses, so its word boundaries see
    them too."""
    jieba = mf._jieba()
    for w in words:
        jieba.add_word(w)
    return jieba


def discovered_for_jieba(disc, known):
    """The discovered words added to jieba: those no current source has, minus
    a closed-class word glued to a known word (这些首长 is not a word)."""
    allknown = set().union(*known.values())
    return sorted(w for w in disc["words"] if w not in allknown and not noise_reason(w, known["cedict"]))


EDGE_FUNCTION = set("的了是在我你他她它这那一不也就都和与又还着过把被让给向从对为说道吗呢吧啊么个们之其")


def noise_reason(w, cedict, measure=frozenset()):
    """Why a missing word is likely segmentation noise, or None."""
    r = everyday(w, cedict, measure)
    if r:
        return r
    if w[0] in EDGE_FUNCTION or w[-1] in EDGE_FUNCTION:
        return "function character at an edge"
    if PHRASE.search(w):
        return "verb/numeral phrase"
    return None


# Free phrases jieba's dictionary lists or the discovery finds: a verb with a
# complement or aspect, numeral + measure, reduplication (看了看).
PHRASE = re.compile(r"^(几|第[一二三四五六七八九十百]|并|能不|要不|会不|是不|有没有|有多|觉得|想到|叹了|看了|"
                    r"点了点|摇了摇|笑了笑|想了想|听了|说着|一下|一声|一眼|一口|一阵|一些)|"
                    r"(到这里|起来|下来|出来|上去|下去|过来|过去|一下|一番|一声|之后|之前|以后|以前|时候|"
                    r"的话|而已|一样|似的|不过|而已)$|^(.)了\3$|^(.)\4$")


def stage_segment():
    base = load("base")
    disc = load("discover")
    add = discovered_for_jieba(disc, base["known"])
    jieba = jieba_with(add)
    tokens = collections.Counter()
    first = {}
    chapters = collections.defaultdict(set)
    han_total = 0
    for b in base["books"]:
        for p, chap in zip(b["paras"], b["chapters"]):
            han_total += len(HAN_CHAR.findall(p))
            for tok in jieba.cut(p, HMM=False):
                if mf.han_word(tok):
                    tokens[tok] += 1
                    if len(tok) >= 2:
                        if tok not in first:
                            first[tok] = f"{b['name']}: {chap}"
                        chapters[tok].add((b["name"], chap))
    save("segment", {"tokens": tokens, "first": first, "nchap": {w: len(c) for w, c in chapters.items()},
                     "han_total": han_total, "added": add})
    print(f"  {han_total:,} Han characters; {sum(tokens.values()):,} Han tokens, {len(tokens):,} types; "
          f"{len(add):,} discovered words added to jieba")


# ---------------------------------------------------------------------------
# Categories (rough, rule based; the top of the list is checked by hand via
# build/measure/BOOK/labels.tsv, which overrides the rules)
# ---------------------------------------------------------------------------

CATEGORIES = ["in-universe", "ming/historical", "technical", "slang", "names", "noise", "phrase", "other"]
# noise: closed-class word glued to a known word, or an ordinary combination
#        jieba lists (送来); phrase: 3+ characters made entirely of CC-CEDICT
#        words (进行了一次, 粮食供应): readable from the pieces the popup shows.

IN_UNIVERSE = re.compile(r"元老|首长|髡|澳洲|澳宋|归化|执委|企划院|穿越|临高|百仞|大图书馆|本时空|旧时空|新时空|"
                         r"伏波|芳草地|博铺|东门市|马袅|启明星|生活秘书|女仆|大世界|海南岛|三亚|"
                         r"仆人|元老院|中央|委员|处长|部长|局长|主任")
MING = re.compile(r"知县|知府|知州|巡抚|总督|总兵|参将|游击|守备|千总|把总|千户|百户|卫所|指挥|都司|布政|按察|兵备|"
                  r"道台|御史|翰林|内阁|阁老|司礼监|锦衣卫|东厂|举人|进士|秀才|生员|童生|县丞|主簿|典史|衙门|胥吏|书办|"
                  r"师爷|长随|里甲|保甲|钱粮|赋役|一条鞭|藩台|臬台|府台|县令|大老爷|老爷|官人|相公|小的|奴婢|"
                  r"银子|铜钱|两银|文钱|贯|石米|亩|斤|丁口|户口|士绅|缙绅|乡绅|大户|佃户|佃农|田主|官军|营兵|"
                  r"家丁|海盗|海贼|流寇|闯贼|建奴|鞑子|东虏|朝廷|圣上|万岁|天启|崇祯|万历|大明|皇明|官府|"
                  r"巡检|驿站|塘报|揭帖|题本|奏本|邸报|票拟|廷寄|吏部|户部|礼部|兵部|刑部|工部")
# Technical stems: strong single characters, and longer stems; generic
# characters (报, 表, 化, 压) only inside longer stems.
TECH = re.compile(r"[炉钢炮枪弹厂阀硝磺砖焦煤铸锻铣螺膛泵钻镗刨焊铆舰艇桅矿冶炼窑硫氨锅]|机[械床器组车枪炮]|[发电]机|"
                  r"蒸汽|水泥|车床|线膛|后装|雷管|火药|炸药|苦味酸|硫酸|硝酸|甘油|口径|毫米|厘米|公斤|吨位|马力|"
                  r"锅炉|发动机|引擎|变速|齿轮|轴承|仪器|模具|铸件|叶片|测绘|经纬|勘探|玻璃|橡胶|纺织|纺纱|织布|"
                  r"印刷|铅字|发报|无线电|电台|电报|电话|化工|化学|疫苗|消毒|细菌|疟疾|霍乱|肥料|制糖|榨糖|盐场|"
                  r"工程|工厂|工业|技术|技师|工人|学徒|车间|生产线|流水线|标准化|帆船|蒸汽机|步枪|火枪|大炮|"
                  r"火炮|炮弹|子弹|弹药|铁路|铁轨|机车|轮船|船厂|造船|船坞|电力|电线|发电|电池|实验|试验|"
                  r"化验|医院|医生|卫生|防疫|种植|农场|拖拉机")
SLANG_SEED = set("""YY 吐槽 坑爹 给力 雷人 杯具 洗具 河蟹 和谐 囧 打酱油 酱油 神马 浮云 屌丝 逆袭 高富帅 白富美 土豪 装逼 装B
牛逼 牛B 傻逼 SB 二逼 苦逼 撕逼 卧槽 我靠 尼玛 草泥马 菊花 蛋疼 淡定 纠结 悲催 坑 挖坑 填坑 太监 腐 腐女 宅 宅男
种马 后宫 萌 萌妹 萝莉 御姐 正太 伪娘 女仆 傲娇 呆萌 卖萌 吃货 剧透 跪了 膜拜 顶 沙发 板凳 地板 楼主 LZ 马甲 灌水
水贴 水帖 版主 斑竹 潜水 冒泡 拍砖 砖家 叫兽 围观 人肉 人肉搜索 打脸 脑残 NC 脑补 猪脚 主角光环 光环 金手指 外挂
开挂 作弊 YY小说 意淫 小白 白痴 弱智 二货 逗比 屁民 P民 五毛 美分 公知 带路党 汉奸 精日 精神 正能量 负能量
不明觉厉 喜大普奔 人艰不拆 细思恐极 累觉不爱 何弃疗 然并卵 也是醉了 醉了 主要看气质 duang 壕 有钱任性 任性
蓝瘦香菇 套路 老司机 开车 带节奏 节奏 黑 黑粉 脑残粉 粉丝 洗地 洗白 甩锅 背锅 接盘 接盘侠 剩女 剩男 宅女 宅腐
御宅 宅腐 二次元 三次元 中二 中二病 鬼畜 弹幕 吐血 喷 喷子 键盘侠 口水 口水战 嘴炮 打嘴炮 跑题 歪楼 盖楼 楼歪了
挖坟 坟贴 考据 考据党 技术宅 理工男 文青 愤青 小资 BS 鄙视 汗 瀑布汗 晕 倒 orz OTZ 233 666 hhh 哈哈哈""".split())
NAME_SURNAMES = set("王李张刘陈杨黄赵吴周徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕"
                    "丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武"
                    "戴莫孔向汤常温康施文牛樊葛邢安齐易乔伍庞颜倪庄聂章鲁岳翟殷詹申欧耿关兰焦俞左柳甘祝包宁尚符舒阮柯"
                    "纪梅童凌毕单季裴霍涂成苗谷盛曲翁冉骆蓝路游辛靳管柴蒙鲍华喻祁蒲房滕屈饶解牟艾尤阳时穆农司卓古吉缪"
                    "简车项连芦麦褚娄窦戚岑景党宫费卜冷晏席卫米柏宗瞿桂全佟应臧闵苟邬边卞姬师和仇栾隋商刁沙荣巫寇桑郎"
                    "甄丛仲虞敖巩明佘池查麻苑迟邝萧")
TRANSLIT = set("斯克尔特亚尼德罗伊莱利诺布塞维奥拉玛琳娜丽莎卡兰埃格里西安塔哈曼森芬戈默蒂普瓦阿巴达拉米索")
PLACE_END = re.compile(r"(县|州|府|港|岛|城|镇|村|山|河|湾|江|湖|海|角|峡|堡|寨|营|坊|街|路|门|岭|洲|乡|墟|口|浦|澳)$")


_JIEBA_FREQ = None
ORDINARY_JIEBA_FREQ = 20


def jieba_freq(w):
    """The word's count in jieba's big dictionary (0 when not listed). Unlike
    wordfreq, which estimates any compound from its parts, this is 0 for the
    book's own words and names."""
    global _JIEBA_FREQ
    if _JIEBA_FREQ is None:
        _JIEBA_FREQ = {}
        for line in open(os.path.join(mf.SRC, "jieba", "dict.txt.big"), encoding="utf-8"):
            parts = line.split()
            if len(parts) >= 2:
                _JIEBA_FREQ[parts[0]] = int(parts[1])
    return _JIEBA_FREQ.get(w, 0)


def splits_known(w, cedict):
    return any(w[:k] in cedict and w[k:] in cedict for k in range(1, len(w)))


def all_known_pieces(w, cedict):
    """True when w splits entirely into CC-CEDICT words, at least one of 2+
    characters (a phrase, not a new word)."""
    n = len(w)
    best = [None] * (n + 1)      # best[i]: longest piece used so far, for w[:i]
    best[0] = 0
    for i in range(n):
        if best[i] is None:
            continue
        for j in range(i + 1, min(n, i + 8) + 1):
            if w[i:j] in cedict and (best[j] is None or max(best[i], j - i) > best[j]):
                best[j] = max(best[i], j - i)
    return best[n] is not None and best[n] >= 2


def rule_category(w, cedict, measure):
    """Rough category of a missing word. Order matters: noise first, then the
    book's own institutions, Ming vocabulary, ordinary combinations, names,
    technical words."""
    if noise_reason(w, cedict, measure):
        return "noise"
    if w in SLANG_SEED:
        return "slang"
    if IN_UNIVERSE.search(w):
        return "in-universe"
    if MING.search(w):
        return "ming/historical"
    # Listed by jieba as a common word and made of two dictionary words: an
    # ordinary combination CC-CEDICT leaves out on purpose (送来, 情报人员).
    if jieba_freq(w) >= ORDINARY_JIEBA_FREQ and splits_known(w, cedict):
        return "noise"
    if len(w) >= 3 and sum(c in TRANSLIT for c in w) >= len(w) - 1:
        return "names"
    if 2 <= len(w) <= 3 and w[0] in NAME_SURNAMES and not TECH.search(w) and jieba_freq(w) < ORDINARY_JIEBA_FREQ:
        return "names"
    if PLACE_END.search(w) and len(w) >= 3 and not TECH.search(w):
        return "names"
    if TECH.search(w):
        return "technical"
    if len(w) >= 3 and all_known_pieces(w, cedict):
        return "phrase"
    return "other"


def read_labels():
    """Hand labels: build/measure/BOOK/labels.tsv, word<TAB>category[<TAB>note]."""
    path = os.path.join(OUT, "labels.tsv")
    labels = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and not line.startswith("#") and parts[1] in CATEGORIES:
                labels[parts[0]] = parts[1]
    return labels


def missing_words():
    """[(word, count)] of 2+ character tokens no current source has, most
    frequent first; with categories (hand label, else rule)."""
    base = load("base")
    seg = load("segment")
    known = set().union(*base["known"].values())
    labels = read_labels()
    miss = [(w, c) for w, c in seg["tokens"].most_common() if len(w) >= 2 and w not in known]
    cat = {w: labels.get(w) or rule_category(w, base["known"]["cedict"], base["measure"]) for w, _ in miss}
    return miss, cat, labels


# ---------------------------------------------------------------------------
# Step 1 report
# ---------------------------------------------------------------------------


def wordfreq_zh(w):
    from wordfreq import word_frequency
    return word_frequency(w, "zh")


def stage_report():
    base = load("base")
    seg = load("segment")
    disc = load("discover")
    miss, cat, labels = missing_words()
    tokens, han_total = seg["tokens"], seg["han_total"]
    ntok = sum(tokens.values())
    ntok2 = sum(c for w, c in tokens.items() if len(w) >= 2)
    known = base["known"]
    L = []
    w = L.append
    names = ", ".join(b["name"] for b in base["books"])
    w(f"# {BOOK}: what the dictionaries still lack\n")
    w(f"Corpus: {names} (build/corpus/{BOOK}-*.txt), {han_total:,} Han characters; "
      f"{ntok:,} Han tokens ({ntok2:,} of 2+ characters), {len(tokens):,} word types.\n")
    w("Current sources, as built (what the popup consults): CC-CEDICT "
      f"{len(known['cedict']):,} forms, Wiktionary fallback {len(known['wikt']):,} forms, "
      f"MOE file {len(known['moe']):,} forms (simplified and traditional). A word is missing when none has it.\n")
    w("Segmentation: jieba, big dictionary, HMM off, plus the words found by n-gram discovery on this book "
      f"(2-{MAX_N} characters, at least {MIN_COUNT} occurrences, weakest-split PMI ≥ {MIN_PMI}, left and right "
      f"neighbour entropy ≥ {MIN_ENTROPY}): {len(disc['words']):,} discovered, {len(seg['added']):,} of them unknown "
      "to every source and added to jieba (closed-class combinations left out). Without the discovery, jieba "
      "splits the book's own words (元老院 → 元老 + 院) and they never show up as missing.\n")

    # --- gap size and share of running text
    mtok = sum(c for _, c in miss)
    mchar = sum(c * len(x) for x, c in miss)
    by_cat = collections.defaultdict(lambda: [0, 0, 0])
    for x, c in miss:
        k = by_cat[cat[x]]
        k[0] += 1
        k[1] += c
        k[2] += c * len(x)
    real = [(x, c) for x, c in miss if cat[x] not in ("noise", "phrase")]
    rtok = sum(c for _, c in real)
    rchar = sum(c * len(x) for x, c in real)
    w("## 1. Size of the gap\n")
    w(f"- missing word types (2+ Han characters): **{len(miss):,}**; seen 3+ times: "
      f"{sum(1 for _, c in miss if c >= 3):,}; 10+ times: {sum(1 for _, c in miss if c >= 10):,}")
    w(f"- their occurrences: **{mtok:,}** = {pct(mtok, ntok2)} of 2+ character tokens, {pct(mtok, ntok)} of all "
      f"Han tokens; they cover {mchar:,} Han characters = **{pct(mchar, han_total)} of the running text**")
    w(f"- leaving out segmentation noise and transparent phrases (categories below): **{len(real):,} types, "
      f"{rtok:,} occurrences, {pct(rchar, han_total)} of the running text**")
    for label, cats in (("names alone", {"names"}),
                        ("in-universe + Ming/historical + technical + slang (what a dictionary could add)",
                         {"in-universe", "ming/historical", "technical", "slang"}),
                        ("other (unclassified 2-character words and the rest)", {"other"})):
        t = sum(1 for x, _ in miss if cat[x] in cats)
        o = sum(c for x, c in miss if cat[x] in cats)
        ch = sum(c * len(x) for x, c in miss if cat[x] in cats)
        w(f"  - {label}: {t:,} types, {o:,} occurrences, {pct(ch, han_total)} of the running text, "
          f"{1000 * o / han_total:.1f} per 1,000 characters")
    w(f"- how often a reader meets one: {1000 * rtok / han_total:.1f} per 1,000 characters, about "
      f"{400 * rtok / han_total:.1f} per page of 400 characters (noise and phrases left out)\n")

    # --- simulated taps: share of taps that land in a missing word
    taps = load("taps") if os.path.exists(cache("taps")) else None
    if taps:
        n = len(taps)
        inside = sum(1 for t in taps if t["gap_word"])
        inside_real = sum(1 for t in taps if t["gap_word"] and cat.get(t["gap_word"]) not in ("noise", "phrase"))
        by = collections.Counter(cat.get(t["gap_word"], "other") for t in taps if t["gap_word"])
        w(f"Simulated taps ({n:,} random Han characters, the same sample as Step 2): the tapped character is "
          f"inside a missing word in {inside:,} ({pct(inside, n)}), {inside_real:,} ({pct(inside_real, n)}) "
          "leaving out noise and phrases. By category: " +
          ", ".join(f"{k} {by[k]:,} ({pct(by[k], n)})" for k in CATEGORIES) +
          ". The popup then shows only the pieces the dictionaries have.\n")

    # --- category split
    w("## 2. Rough split by category\n")
    w("Rules (tools/measure_book.py rule_category: keyword lists for the book's institutions, Ming offices and "
      "money, technical stems, a seed list of 2009-2015 forum slang, surnames and transliteration characters for "
      f"names, everyday() and edge function characters for noise); {len(labels):,} of the most frequent words "
      f"checked by hand (build/measure/{BOOK}/labels.tsv), which override the rules. 'phrase' (3+ characters made "
      "entirely of CC-CEDICT words) also holds some transparent in-universe names of institutions (治安军, 海兵队, "
      "国家警察); 'other' is unclassified, mostly 2-character words and names the rules miss.\n")
    w("| Category | types | occurrences | share of running text | of the top 300 (hand-checked) |")
    w("|---|---|---|---|---|")
    top = miss[:300]
    topcat = collections.Counter(cat[x] for x, _ in top)
    for c in CATEGORIES:
        t, o, ch = by_cat[c]
        w(f"| {c} | {t:,} | {o:,} | {pct(ch, han_total)} | {topcat[c]} |")
    w("")
    w("Occurrence-weighted examples per category (most frequent first):\n")
    for c in CATEGORIES:
        ex = [f"{x} {n}" for x, n in miss if cat[x] == c][:25]
        w(f"- **{c}**: " + ", ".join(ex))
    w("")

    # --- top 300
    w("## 3. The 300 most frequent missing words\n")
    w("word · occurrences · category · chapters it appears in · first appearance\n")
    for i in range(0, 300, 1):
        if i >= len(miss):
            break
        x, c = miss[i]
        w(f"{i + 1}. {x} · {c} · {cat[x]}{'' if x not in labels else ' ✓'} · {seg['nchap'].get(x, 0)} · "
          f"{seg['first'].get(x, '')}")
    w("")
    w(f"Full list: build/measure/{BOOK}/missing.tsv (✓ = hand-checked label).\n")
    with open(os.path.join(OUT, "missing.tsv"), "w", encoding="utf-8") as f:
        f.write("rank\tword\tcount\tcategory\thand_label\tchapters\tfirst\tdiscovered\n")
        for i, (x, c) in enumerate(miss, 1):
            f.write(f"{i}\t{x}\t{c}\t{cat[x]}\t{int(x in labels)}\t{seg['nchap'].get(x, 0)}\t"
                    f"{seg['first'].get(x, '')}\t{int(x in disc['words'])}\n")

    # --- in-universe senses of known words
    w("## 4. CC-CEDICT words the book uses far more than general Chinese\n")
    w("Candidates for words the novel uses in its own sense (澳洲人 = the time travellers, 首长, 元老). "
      "Keyness = the word's rate in the book over its wordfreq rate in general Chinese (floor 0.05 per million); "
      "CC-CEDICT words of 2+ characters seen 30+ times, ranked by keyness × log(count). A ranking, not a "
      "judgement: the glossary picks in the handoff are checked by hand.\n")
    rows = []
    for x, c in tokens.items():
        if len(x) < 2 or c < 30 or x not in known["cedict"]:
            continue
        book_pm = 1e6 * c / ntok
        gen_pm = max(1e6 * wordfreq_zh(x), 0.05)
        rows.append((book_pm / gen_pm * math.log(c), x, c, book_pm, gen_pm))
    rows.sort(reverse=True)
    with open(os.path.join(OUT, "keyness.tsv"), "w", encoding="utf-8") as f:
        f.write("word\tcount\tbook_per_million\tgeneral_per_million\tscore\tchapters\tfirst\n")
        for s, x, c, b, g in rows:
            f.write(f"{x}\t{c}\t{b:.1f}\t{g:.2f}\t{s:.1f}\t{seg['nchap'].get(x, 0)}\t{seg['first'].get(x, '')}\n")
    w("| word | count | per million: book / general | chapters | first appearance |")
    w("|---|---|---|---|---|")
    for s, x, c, b, g in rows[:120]:
        w(f"| {x} | {c:,} | {b:.0f} / {g:.2f} | {seg['nchap'].get(x, 0)} | {seg['first'].get(x, '')} |")
    w(f"\nFull list: build/measure/{BOOK}/keyness.tsv.\n")
    path = os.path.join(BUILD, "measure", f"{BOOK}-report.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {path}")


# ---------------------------------------------------------------------------
# taps: the plugin's candidate code on random characters of the book
# ---------------------------------------------------------------------------


def stage_taps(per_book, seed):
    """Simulated taps (measure_fallback.tap_samples: ch_text.lua in lupa), with
    jieba knowing the discovered words, so a match of 元老院 or 髡贼 is judged
    against word boundaries that include them. For each tap: the candidates,
    whether each starts and ends on a word boundary, which current source has
    it, and the missing word the tapped character is in, if any."""
    base = load("base")
    seg = load("segment")
    jieba_with(seg["added"])
    known = base["known"]
    allknown = set().union(*known.values())
    taps = []
    for book, para, i, cands, left, right, bounds in mf.tap_samples(per_book, seed):
        a = max(b for b in bounds if b <= i)
        b = min(x for x in bounds if x > i)
        tok = para[a:b]
        gap_word = tok if len(tok) >= 2 and mf.han_word(tok) and tok not in allknown else None
        cs = []
        for text, start, length in cands:
            s, e = i + start, i + start + length
            src = next((k for k in ("cedict", "wikt", "moe") if text in known[k]), None)
            cs.append((text, length, s in bounds and e in bounds, src))
        taps.append({"book": book, "context": "".join(left) + "[" + para[i] + "]" + "".join(right),
                     "cands": cs, "gap_word": gap_word, "token": tok})
    save("taps", taps)
    print(f"  {len(taps):,} simulated taps; inside a missing word: {sum(1 for t in taps if t['gap_word']):,}")


def stage_gentaps(per_book=150, seed=20261111):
    """The same simulated taps on the Phase 1 corpus (the device's books,
    build/corpus/NNN.txt), for false matches outside this book."""
    base = load("base")
    known = base["known"]
    files = sorted(p for p in mf.glob.glob(os.path.join(mf.CORPUS, "*.txt"))
                   if re.fullmatch(r"\d{3}\.txt", os.path.basename(p)))
    saved = mf.corpus_files
    mf.corpus_files = lambda: files
    try:
        taps = []
        for book, para, i, cands, left, right, bounds in mf.tap_samples(per_book, seed):
            cs = []
            for text, start, length in cands:
                s, e = i + start, i + start + length
                src = next((k for k in ("cedict", "wikt", "moe") if text in known[k]), None)
                cs.append((text, length, s in bounds and e in bounds, src))
            taps.append({"book": book, "context": "".join(left) + "[" + para[i] + "]" + "".join(right),
                         "cands": cs})
    finally:
        mf.corpus_files = saved
    save("gentaps", taps)
    print(f"  {len(taps):,} taps on {len(files)} books of the general corpus")


# ---------------------------------------------------------------------------
# sources: the Step 2 candidates
# ---------------------------------------------------------------------------

MOEGIRL = os.path.join(mf.SRC, "moegirl", "zhmoegirl-20230507-alpha.slob")
CBDB = os.path.join(mf.SRC, "cbdb", "db", "cbdb_20261107.sqlite3")
CBDB_MING = (19, 80)    # DYNASTIES.c_dy: 明, 南明


def _parse_moegirl(item):
    import moegirl_slob as M
    key, html_text = item
    r = M.parse(html_text)
    r["kind"] = M.kind(r["opening"])
    r["ends_ok"] = html_text.rstrip().endswith("</div>")
    del r["opening"]
    return key, r


def _moegirl_items(path):
    import moegirl_slob as M
    for key, _, html_text in M.entries(path):
        if mf.han_word(key):
            yield key, html_text


def load_moegirl():
    """{key: parsed opening} for every Moegirlpedia key of 1-8 Han characters
    (redirect keys included: title != key), plus the slob's tags and counts."""
    import multiprocessing
    import moegirl_slob as M
    tags, nkeys, nblobs = M.tags(MOEGIRL)
    pages = {}
    with multiprocessing.Pool(max(1, os.cpu_count() - 2)) as pool:
        for n, (key, r) in enumerate(pool.imap_unordered(_parse_moegirl, _moegirl_items(MOEGIRL), chunksize=64), 1):
            pages[key] = r
            if n % 20000 == 0:
                print(f"  moegirl: {n:,} parsed", flush=True)
    return {"pages": pages, "tags": tags, "keys": nkeys, "blobs": nblobs}


WP_EXTRA_TECH = (r"|武器|兵器|火炮|大炮|枪|槍|彈|弹药|軍艦|军舰|船舶|艦|舰|冶金|機械|机械|化工|工業|工业|蒸汽|"
                 r"鍋爐|锅炉|機床|机床|火藥|火药|炸藥|炸药|軍事技術|军事技术|科學|科学|技術史|技术史|工藝|工艺|"
                 r"建築材料|建筑材料|紡織|纺织|農業|农业|醫療|医疗|測量|测量")


def load_wp_filtered():
    """Chinese Wikipedia titles with an English article (measure_fallback's
    parser), the technical regex widened to engineering and military
    technology; kept: 3+ characters, technical or historical category, not a
    place/organisation/work."""
    old = mf.WP_TECH
    mf.WP_TECH = re.compile(old.pattern + WP_EXTRA_TECH)
    try:
        index, stats, _ = mf.load_wikipedia()
    finally:
        mf.WP_TECH = old
    kept = {}
    drop = collections.Counter()
    for form, e in index.items():
        if len(form) < 3:
            drop["shorter than 3"] += 1
        elif not e["cls"] & {"technical", "historical/literary"}:
            drop["no science/technology/history category"] += 1
        elif e.get("place"):
            drop["place/organisation/work category"] += 1
        else:
            kept[form] = e
    stats.update({"filtered out: " + k: v for k, v in drop.items()})
    stats["kept (3+, tech/history, not place)"] = len(kept)
    return kept, stats, index


def load_cbdb():
    """CBDB office titles of the Ming and Southern Ming (OFFICE_CODES), under
    the original, its simplified form (OpenCC t2s) and alternative names."""
    import opencc
    t2s = opencc.OpenCC("t2s")
    con = sqlite3.connect(f"file:{CBDB}?mode=ro", uri=True)
    index, stats = {}, collections.Counter()
    q = ("SELECT c_office_chn, c_office_chn_alt, c_office_pinyin, c_office_trans, c_dy FROM OFFICE_CODES "
         f"WHERE c_dy IN ({','.join(map(str, CBDB_MING))})")
    for chn, alt, py, trans, dy in con.execute(q):
        stats["Ming office codes"] += 1
        trans = (trans or "").strip()
        if not trans or trans.startswith("["):
            stats["... without an English translation"] += 1
        forms = []
        for name in [chn] + re.split(r"[;；,，/、]", alt or ""):
            name = (name or "").strip()
            if name:
                forms += [name, t2s.convert(name)]
        good = [f for f in forms if mf.han_word(f)]
        if not good:
            stats["... no 1-8 Han character name"] += 1
            continue
        ent = {"head": chn, "py": py or "", "gloss": trans, "cls": {"historical/literary"}, "n": 1,
               "dy": dy}
        mf.add(index, good, ent)
    con.close()
    stats["indexed forms"] = len(index)
    return index, stats


def moegirl_index(mg, mode):
    """The Moegirlpedia headwords a built source would have:
      all       every key of 1-8 Han characters (redirect keys too)
      pages     keys that are a page's own title (no redirects)
      terms     pages whose opening describes a term (用语, 梗, 流行语, ...),
                not a character, work or person (moegirl_slob.kind)
      slang     term pages whose first sentence calls the word internet/forum
                usage, not disambiguation or 萌属性 pages (moegirl_slob.is_slang):
                all of Moegirlpedia's slang, not only this book's
    Each also under its simplified form (t2s)."""
    import opencc
    import moegirl_slob as M
    t2s = opencc.OpenCC("t2s")
    index = {}
    for key, r in mg["pages"].items():
        if mode == "slang" and (r["title"] != key or r["kind"] != "term" or not M.is_slang(r["gloss"])):
            continue
        redirect = r["title"] != key
        if mode in ("pages", "terms") and redirect:
            continue
        if mode == "terms" and r["kind"] != "term":
            continue
        if not r["gloss"]:
            continue
        ent = {"head": r["title"] or key, "py": "", "gloss": r["gloss"], "cls": set(), "n": 1,
               "kind": r["kind"], "redirect": redirect}
        mf.add(index, [key, t2s.convert(key)], ent)
    return index


def stage_sources():
    out = {}
    print("  Moegirlpedia...", flush=True)
    out["moegirl"] = load_moegirl()
    print("  CBDB...", flush=True)
    out["cbdb"], out["cbdb_stats"] = load_cbdb()
    print("  Wikipedia (filtered)...", flush=True)
    out["wpf"], out["wpf_stats"], wp_all = load_wp_filtered()
    out["wp_all"] = wp_all
    save("sources", out)
    print(f"  moegirl keys parsed {len(out['moegirl']['pages']):,}; cbdb {len(out['cbdb']):,}; "
          f"wp filtered {len(out['wpf']):,} of {len(wp_all):,}")


# ---------------------------------------------------------------------------
# eval: Step 2 report
# ---------------------------------------------------------------------------

EVAL_SOURCES = [
    ("moegirl-all", "Moegirlpedia, every key (redirects included)"),
    ("moegirl-pages", "Moegirlpedia, page titles only (no redirects)"),
    ("moegirl-terms", "Moegirlpedia, term pages only (opening says 用语/梗/流行语/称呼...)"),
    ("moegirl-slang", "Moegirlpedia, all slang pages (internet/forum usage; no disambiguation or 萌属性)"),
    ("wp-all", "Chinese Wikipedia titles, unfiltered (as measured in Phase 1)"),
    ("wpf", "Chinese Wikipedia titles, 3+ characters, science/technology/engineering/military/history"),
    ("cbdb", "CBDB Ming office titles"),
]


def stage_eval():
    src = load("sources")
    base = load("base")
    taps = load("taps")
    miss, cat, labels = missing_words()
    seg = load("segment")
    known = set().union(*base["known"].values())
    mg = src["moegirl"]
    idx = {"moegirl-all": moegirl_index(mg, "all"), "moegirl-pages": moegirl_index(mg, "pages"),
           "moegirl-terms": moegirl_index(mg, "terms"), "moegirl-slang": moegirl_index(mg, "slang"), "wp-all": src["wp_all"], "wpf": src["wpf"],
           "cbdb": src["cbdb"]}
    han_total = seg["han_total"]
    L = []
    w = L.append
    w(f"# {BOOK}: candidate sources against the missing words\n")
    w(f"Missing words from build/measure/{BOOK}-report.md: {len(miss):,} types, "
      f"{sum(c for _, c in miss):,} occurrences. Categories: rules plus {len(labels)} hand labels. "
      "A source 'covers' a missing word when it has that exact string (either script). Only entries no "
      "current source (CC-CEDICT, Wiktionary, MOE) has count: the plugin's priority would hide the rest.\n")

    # --- Moegirl facts
    pages = mg["pages"]
    w("## 1. Moegirlpedia snapshot: what is in it\n")
    w(f"- file: build/sources/moegirl/zhmoegirl-20230507-alpha.slob, {os.path.getsize(MOEGIRL) / 1e9:.2f} GB; "
      f"{mg['keys']:,} keys, {mg['blobs']:,} blobs (articles); created {mg['tags'].get('created.at', '')[:10]}")
    w(f"- licence tag: {mg['tags'].get('license.name', '')} ({mg['tags'].get('license.url', '')})")
    nred = sum(1 for k, r in pages.items() if r["title"] != k)
    w(f"- keys of 1-8 Han characters: {len(pages):,}, of which redirects (key ≠ page title): {nred:,}")
    kinds = collections.Counter(r["kind"] for k, r in pages.items() if r["title"] == k)
    w("- page kinds from the opening sentence (non-redirect keys): " +
      ", ".join(f"{k} {v:,}" for k, v in kinds.most_common()))
    hm = sum(1 for r in pages.values() if r["heimu"])
    st = sum(1 for r in pages.values() if r["strike"])
    w(f"- 黑幕 (`span.heimu`) in {hm:,} pages ({pct(hm, len(pages))}); strikethrough (`<s>`/`<del>`) in {st:,} "
      f"({pct(st, len(pages))}); both are marked up and stripped by tools/moegirl_slob.py")
    nog = sum(1 for r in pages.values() if not r["gloss"])
    end = sum(1 for r in pages.values() if r["ends_ok"])
    tocok = sum(1 for r in pages.values() if r["toc"] and r["headlines"] >= r["toc"])
    toc = sum(1 for r in pages.values() if r["toc"])
    w(f"- completeness: {pct(end, len(pages))} of pages end with their closing markup; of {toc:,} pages with a "
      f"table of contents, {pct(tocok, toc)} have every TOC heading present in the text; "
      f"{nog:,} ({pct(nog, len(pages))}) have no paragraph of real text (stubs, lists, pure infobox pages)")
    w("- categories: none survive (no catlinks block); navboxes link to category pages, which says nothing "
      "about the page itself")
    w("")
    w("Typical openings of term pages (first sentence, 黑幕 and strikethrough removed):\n")
    ex = [(k, r) for k, r in pages.items() if r["title"] == k and r["kind"] == "term" and k in seg["tokens"]]
    ex.sort(key=lambda kr: -seg["tokens"][kr[0]])
    for k, r in ex[:12]:
        w(f"- **{k}**: {r['gloss']}")
    w("")

    # --- coverage
    w("## 2. Coverage of the missing words\n")
    w("| Source | headwords not in current sources | missing types covered | occurrences covered | " +
      " | ".join(CATEGORIES) + " |")
    w("|---|---|---|---|" + "---|" * len(CATEGORIES))
    tot_by_cat = collections.Counter()
    for x, c in miss:
        tot_by_cat[cat[x]] += 1
    w("| (all missing words) | | " + f"{len(miss):,} | {sum(c for _, c in miss):,} | " +
      " | ".join(f"{tot_by_cat[k]:,}" for k in CATEGORIES) + " |")
    cover = {}
    for key, label in EVAL_SOURCES:
        S = idx[key]
        cov = [(x, c) for x, c in miss if x in S]
        cover[key] = cov
        bc = collections.Counter(cat[x] for x, _ in cov)
        new = sum(1 for h in S if h not in known)
        w(f"| {label} | {new:,} | {len(cov):,} ({pct(len(cov), len(miss))}) | {sum(c for _, c in cov):,} "
          f"({pct(sum(c for _, c in cov), sum(c for _, c in miss))}) | " +
          " | ".join(f"{bc[k]:,}" for k in CATEGORIES) + " |")
    w("")
    w("Top 300 missing words (hand-checked categories), covered:\n")
    top = miss[:300]
    for key, label in EVAL_SOURCES:
        S = idx[key]
        cv = [x for x, _ in top if x in S]
        w(f"- {label}: {len(cv)} of 300 — " + ", ".join(f"{x} ({cat[x]})" for x in cv[:40]))
    w("")

    # --- taps
    w("## 3. Simulated taps: what each source would add, and false matches\n")
    n = len(taps)
    gap_taps = [t for t in taps if t["gap_word"]]
    w(f"{n:,} taps on random Han characters ({n // max(1, len(base['books']))} per file), candidates from the "
      "plugin's own ch_text.lua (measure_fallback.tap_samples). A source's match counts where no current source "
      "has the string. Plausible = starts and ends on a word boundary of jieba + the discovered words; likely "
      "false = cuts through a word (e.g. a 2-character title matching across two words). "
      f"{len(gap_taps):,} taps ({pct(len(gap_taps), n)}) land inside a missing word.\n")
    w("| Source | taps gaining a plausible match | taps gaining a likely-false match | matches: plausible / "
      "likely false | false-match rate | taps inside a missing word that get it |")
    w("|---|---|---|---|---|---|")
    tap_hits = {}
    for key, label in EVAL_SOURCES:
        S = idx[key]
        hits = [[(text, ln, al) for text, ln, al, s in t["cands"] if s is None and text in S] for t in taps]
        tap_hits[key] = hits
        good = sum(1 for h in hits if any(al for _, _, al in h))
        bad = sum(1 for h in hits if any(not al for _, _, al in h))
        na = sum(1 for h in hits for x in h if x[2])
        nb = sum(1 for h in hits for x in h if not x[2])
        rescued = sum(1 for t in gap_taps if t["gap_word"] in S)
        w(f"| {label} | {good:,} ({pct(good, n)}) | {bad:,} ({pct(bad, n)}) | {na:,} / {nb:,} | "
          f"{pct(nb, na + nb)} | {rescued:,} of {len(gap_taps):,} |")
    w("")
    rnd = random.Random(3)
    for key, label in EVAL_SOURCES:
        for kind_, flag in (("plausible", True), ("likely false", False)):
            ex = [(x[0], t["context"]) for t, h in zip(taps, tap_hits[key]) for x in h if x[2] == flag]
            rnd.shuffle(ex)
            w(f"**{key}, {kind_}** ({len(ex):,}): " + "; ".join(f"{a} in {b}" for a, b in ex[:12]))
            w("")

    # --- samples
    w("## 4. Sample entries (missing words each source covers, most frequent first)\n")
    for key, label in EVAL_SOURCES:
        S = idx[key]
        w(f"**{label}**\n")
        for x, c in cover[key][:25]:
            e = S[x]
            extra = f" [{e.get('kind', '')}{', redirect to ' + e['head'] if e.get('redirect') else ''}]" \
                if key.startswith("moegirl") else ""
            w(f"- {x} ×{c} ({cat[x]}){extra} {e.get('py', '')} — {e.get('gloss', '')[:120]}")
        w("")
    # Random entries of the filtered sources, for quality beyond this book.
    for key in ("moegirl-slang", "moegirl-terms", "wpf", "cbdb"):
        S = idx[key]
        pool = [h for h, e in S.items() if h not in known and h == e["head"]] or \
            [h for h in S if h not in known]
        rnd.shuffle(pool)
        w(f"Random entries of {key} (not limited to this book): " +
          "; ".join(f"{h} — {S[h].get('gloss', '')[:60]}" for h in pool[:15]) + "\n")

    # --- the same sources on the general corpus (the reader's other books)
    gen = load("gentaps") if os.path.exists(cache("gentaps")) else None
    if gen:
        g = len(gen)
        w("## 3b. The same sources on the reader's other books\n")
        w(f"{g:,} taps on the Phase 1 corpus (build/corpus/NNN.txt, the device's Chinese books, 150 per book, "
          "seed of Phase 1): a source is used for every book, so its false matches elsewhere count too.\n")
        w("| Source | taps gaining a plausible match | taps gaining a likely-false match | false-match rate |")
        w("|---|---|---|---|")
        for key, label in EVAL_SOURCES:
            S = idx[key]
            hits = [[al for text, ln, al, s in t["cands"] if s is None and text in S] for t in gen]
            good = sum(1 for h in hits if any(h))
            bad = sum(1 for h in hits if not all(h) and h)
            na = sum(sum(h) for h in hits)
            nb = sum(len(h) - sum(h) for h in hits)
            w(f"| {label} | {good:,} ({pct(good, g)}) | {bad:,} ({pct(bad, g)}) | {pct(nb, na + nb)} ({nb:,} of "
              f"{na + nb:,}) |")
        w("")
    # --- slang in the book, whether or not a current source has the word
    S = idx["moegirl-slang"]
    text = "\n".join(p for b in base["books"] for p in b["paras"])
    present = []
    for h, e in S.items():
        if h != e["head"] or len(h) < 2:
            continue
        c = seg["tokens"].get(h, 0) if len(h) == 2 else text.count(h)
        if c:
            present.append((c, h, h in known))
    present.sort(reverse=True)
    w("## 3c. Moegirlpedia's slang in the book\n")
    w(f"Slang pages whose title occurs in the book (3+ characters: substring count; 2 characters: as a token): "
      f"{len(present):,}, {sum(c for c, _, _ in present):,} occurrences; of those titles, already in a current "
      f"source: {sum(1 for _, _, k in present if k):,}. Most frequent (✓ = a current source has it): " +
      ", ".join(f"{h} {c}{' ✓' if k else ''}" for c, h, k in present[:60]) + "\n")

    # --- sizes
    w("## 5. Size\n")
    w("measure_fallback.db_size: one row per indexed form not in a current source (form, headword, reading, "
      "the short gloss used here), two indexes, VACUUMed; zip -9. Lower bounds for a real build with fuller "
      "glosses.\n")
    w("| Source | rows | SQLite | zipped |")
    w("|---|---|---|---|")
    for key, label in EVAL_SOURCES:
        S = {h: e for h, e in idx[key].items() if h not in known}
        raw, z, rows = mf.db_size(S, os.path.join(OUT, f"size-{key}.sqlite"))
        w(f"| {label} | {rows:,} | {raw / 1e6:.1f} MB | {z / 1e6:.1f} MB |")
    w("")
    w("## 6. Loader statistics\n")
    for k in ("wpf_stats", "cbdb_stats"):
        w(f"**{k}**: " + "; ".join(f"{a} {b:,}" for a, b in src[k].items()) + "\n")
    path = os.path.join(BUILD, "measure", f"{BOOK}-sources.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    # Full coverage lists for the handoff session.
    with open(os.path.join(OUT, "coverage.tsv"), "w", encoding="utf-8") as f:
        f.write("source\tword\tcount\tcategory\theadword\tgloss\n")
        for key, _ in EVAL_SOURCES:
            for x, c in cover[key]:
                e = idx[key][x]
                f.write(f"{key}\t{x}\t{c}\t{cat[x]}\t{e['head']}\t{e.get('gloss', '')[:200]}\n")
    print(f"wrote {path}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

STAGES = ["base", "discover", "segment", "taps", "report", "sources", "gentaps", "eval"]


def main():
    global OUT, BOOK
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--book", required=True, help="build/corpus/BOOK-*.txt (fetch_books.py --local BOOK ...)")
    ap.add_argument("--stage", default="base,discover,segment,taps,report",
                    help="comma-separated, from: " + ", ".join(STAGES))
    ap.add_argument("--taps-per-book", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=20261112)
    args = ap.parse_args()
    BOOK = args.book
    mf.set_book(BOOK)
    OUT = mf.OUT
    if not mf.corpus_files():
        sys.exit(f"no build/corpus/{BOOK}-*.txt: run tools/fetch_books.py --local {BOOK} FILE... first")
    stages = args.stage.split(",")
    for s in stages:
        if s not in STAGES:
            sys.exit(f"unknown stage {s}")
    funcs = {"base": stage_base, "discover": stage_discover, "segment": stage_segment,
             "taps": lambda: stage_taps(args.taps_per_book, args.seed), "report": stage_report,
             "sources": lambda: stage_sources(), "gentaps": lambda: stage_gentaps(), "eval": lambda: stage_eval()}
    for s in STAGES:
        if s in stages:
            print(f"[{s}]", flush=True)
            funcs[s]()


if __name__ == "__main__":
    sys.exit(main())
