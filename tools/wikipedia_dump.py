"""Chinese Wikipedia's SQL dumps: page titles, their English interlanguage
links and their categories. Used by tools/fallback_sources.py (the "wp"
fallback rows in the release database) and tools/measure_fallback.py.

The five files (about 1.1 GB) go in build/sources/wikipedia/:
    zhwiki-latest-{page,langlinks,page_props,categorylinks,linktarget}.sql.gz
from https://dumps.wikimedia.org/zhwiki/latest/ (CC BY-SA 4.0).
"""
import collections
import gzip
import os
import re
import urllib.request

FILES = ["page", "langlinks", "page_props", "categorylinks", "linktarget"]
URL = "https://dumps.wikimedia.org/zhwiki/latest/zhwiki-latest-{}.sql.gz"


def path_of(d, name):
    return os.path.join(d, f"zhwiki-latest-{name}.sql.gz")


def download(d):
    """The dump files that are missing from `d`."""
    os.makedirs(d, exist_ok=True)
    headers = {"User-Agent": "koreader-chinese-helper build script"}
    for name in FILES:
        path = path_of(d, name)
        if os.path.exists(path):
            continue
        print(f"Downloading {URL.format(name)}")
        with urllib.request.urlopen(urllib.request.Request(URL.format(name), headers=headers), timeout=600) as r, \
                open(path + ".part", "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
        os.replace(path + ".part", path)


def dump_date(d):
    """The page dump's "Dump completed on" date (YYYY-MM-DD), or "": the
    latest/ files carry no date in their names."""
    last = ""
    with gzip.open(path_of(d, "page"), "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("-- Dump completed on"):
                last = line.split("on", 1)[1].strip()[:10]
    return last



SQL_STR = r"'((?:[^'\\]|\\.)*)'"


def sql_unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1)), s)


def sql_rows(path, pattern):
    rx = re.compile(pattern)
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            # Rows come one per line after "INSERT INTO `t` VALUES" (newer dumps)
            # or all on the INSERT line (older ones).
            if line.startswith("(") or line.startswith("INSERT INTO"):
                yield from rx.finditer(line)


def sql_columns(path):
    cols, inside = [], False
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE"):
                inside = True
                continue
            if inside:
                m = re.match(r"\s+`(\w+)`", line)
                if m:
                    cols.append(m.group(1))
                elif line.startswith(")"):
                    return cols


PERSON_CAT = re.compile(r"(\d+年(代)?出生|\d+年(代)?逝世|在世人物|出生年份不詳|出生年份不详|逝世年份不詳|逝世年份不详|"
                        r"人物$|演員$|演员$|歌手$|作家$|運動員$|运动员$|政治人物|球員$|球员$|模特兒$|模特儿$)")
WP_SLANG = re.compile(r"網路用語|网络用语|網路流行語|网络流行语|流行語|流行语|網路迷因|网络迷因|網路文化|网络文化|俚語|俚语|黑话|黑話")
WP_TECH = re.compile(r"技術|技术|計算機|计算机|電腦|电脑|軟體|软件|程式|编程|程序设计|化學|化学|物理|數學|数学|醫學|医学|"
                     r"疾病|藥物|药物|生物|工程|電子|电子|統計|统计|天文|地質|地质|經濟學|经济学|金融|法律|材料|演算法|算法|"
                     r"網際網路|互联网|半導體|半导体|通訊|通信")
WP_HIST = re.compile(r"朝|官職|官职|官制|歷史|历史|古代|典故|成語|成语|制度|科舉|科举|年號|年号|封建|典章|爵位|宮廷|宫廷|"
                     r"文言|古籍|經典|经典|詩|诗|詞|词牌")
WP_PLACE = re.compile(r"行政區劃|行政区划|城市|鄉鎮|乡镇|村$|縣$|县$|市$|區$|区$|河流|山峰|島嶼|岛屿|車站|车站|機場|机场|"
                      r"街道|道路|公路|鐵路|铁路|學校|学校|大學|大学|公司$|企業|企业|球隊|球队|電影|电影|電視劇|电视剧|專輯|专辑|"
                      r"歌曲|小說|小说|遊戲$|游戏$|動畫|动画|漫畫|漫画")


# Engineering and military technology (for a historical novel's cannons,
# muskets and mills), added to WP_TECH for the fallback rows.
WP_EXTRA_TECH = (r"|武器|兵器|火炮|大炮|枪|槍|彈|弹药|軍艦|军舰|船舶|艦|舰|冶金|機械|机械|化工|工業|工业|蒸汽|"
                 r"鍋爐|锅炉|機床|机床|火藥|火药|炸藥|炸药|軍事技術|军事技术|科學|科学|技術史|技术史|工藝|工艺|"
                 r"建築材料|建筑材料|紡織|纺织|農業|农业|醫療|医疗|測量|测量")
# Living things and chemical compounds: precise but never what a reader taps
# (黄嘴喜鹊, 磷酸三苯酯); left out of the fallback rows.
WP_NATURE = re.compile(r"物種|物种|[屬属]$|[^學学百]科$|動物|动物|植物|昆蟲|昆虫|真菌|細菌|细菌|病毒|鳥類|鸟类|魚類|鱼类|"
                       r"哺乳|爬行|兩棲|两栖|化合物|有機物|有机物|無機物|无机物|蛋白|[酶酸酯醇烷烯炔胺]$|礦物|矿物|"
                       r"化學元素|化学元素|生物分類|生物分类|未評估物種|未评估物种|瀕危物種|濒危物种|無危物種|无危物种")


def titles_with_english(d, stats=None):
    """{page_id: (title, English title, [category names], disambiguation)}
    for every article (namespace 0, not a redirect) whose title is 1-8 Han
    characters and which has an English interlanguage link."""
    from fallback_sources import han_word
    stats = stats if stats is not None else collections.Counter()
    page = path_of(d, "page")
    cols = sql_columns(page)
    assert cols[:4] == ["page_id", "page_namespace", "page_title", "page_is_redirect"], cols
    titles = {}
    for m in sql_rows(page, r"\((\d+),(-?\d+)," + SQL_STR + r",(\d),"):
        if m.group(2) != "0" or m.group(4) == "1":
            continue
        title = sql_unescape(m.group(3))
        if han_word(title):
            titles[int(m.group(1))] = title
    stats["wp: Han-only 1-8 article titles"] = len(titles)
    ll = path_of(d, "langlinks")
    assert sql_columns(ll)[:3] == ["ll_from", "ll_lang", "ll_title"]
    english = {}
    for m in sql_rows(ll, r"\((\d+),'en'," + SQL_STR + r"\)"):
        pid = int(m.group(1))
        if pid in titles:
            english[pid] = sql_unescape(m.group(2))
    stats["wp: ... with an English article"] = len(english)
    disamb = {int(m.group(1)) for m in sql_rows(path_of(d, "page_props"), r"\((\d+),'disambiguation',")}
    lt = path_of(d, "linktarget")
    assert sql_columns(lt)[:3] == ["lt_id", "lt_namespace", "lt_title"]
    catname = {int(m.group(1)): sql_unescape(m.group(2)) for m in sql_rows(lt, r"\((\d+),14," + SQL_STR + r"\)")}
    cl = path_of(d, "categorylinks")
    cl_cols = sql_columns(cl)
    assert cl_cols[0] == "cl_from" and cl_cols[-1] == "cl_target_id", cl_cols
    cats = collections.defaultdict(list)
    for m in sql_rows(cl, r"\((\d+)," + SQL_STR + r",'[^']*'," + SQL_STR + r",'(?:page|subcat|file)',\d+,(\d+)\)"):
        pid = int(m.group(1))
        if pid in english:
            name = catname.get(int(m.group(4)))
            if name:
                cats[pid].append(name)
    return {pid: (titles[pid], en, cats.get(pid, []), pid in disamb) for pid, en in english.items()}
