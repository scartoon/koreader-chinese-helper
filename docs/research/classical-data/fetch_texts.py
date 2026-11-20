"""Fetch the classical test set from zh.wikisource (parsed HTML -> plain text)."""
import json, re, sys, time, urllib.parse, urllib.request, html, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "texts")
PAGES = [
    ("lunyu_xueer", "論語/學而第一"), ("lunyu_weizheng", "論語/為政第二"), ("lunyu_liren", "論語/里仁第四"),
    ("lunyu_shuer", "論語/述而第七"), ("mengzi_lianghuiwang_shang", "孟子/梁惠王上"),
    ("zuozhuan_yingong", "春秋左氏傳/隱公"), ("shiji_lianpo", "史記/卷081"), ("shiji_quyuan", "史記/卷084"),
    ("shiji_cike", "史記/卷086"), ("zizhi_tongjian_001", "資治通鑑/卷001"),
    ("guwen_chushibiao", "出師表"), ("guwen_shishuo", "師說"), ("guwen_yueyanglouji", "岳陽樓記"),
    ("guwen_zuiwengtingji", "醉翁亭記"), ("guwen_chenqingbiao", "陳情表"), ("guwen_guoqinlun", "過秦論"),
    ("guwen_taohuayuanji", "桃花源記"), ("guwen_lanting", "蘭亭集序"),
]
UA = "classical-test-set-fetcher/0.1 (research script)"
def get(title):
    q = urllib.parse.urlencode({"action": "parse", "page": title, "prop": "text", "format": "json",
                                "redirects": 1, "variant": "zh-hant"})
    req = urllib.request.Request("https://zh.wikisource.org/w/api.php?" + q, headers={"User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=60))
def clean(h):
    h = re.sub(r"(?s)<(style|script|table|sup)[^>]*>.*?</\1>", "", h)
    h = re.sub(r'(?s)<div[^>]*class="[^"]*(header|navbox|licenseContainer|mw-references)[^"]*".*?</div>', "", h)
    h = re.sub(r"<br\s*/?>|</p>|</dd>|</li>|</h\d>", "\n", h)
    t = html.unescape(re.sub(r"<[^>]+>", "", h))
    lines = [l.strip() for l in t.split("\n")]
    keep = [l for l in lines if sum(1 for c in l if "一" <= c <= "鿿") >= 8]
    return "\n".join(keep)
for name, title in PAGES:
    path = os.path.join(OUT, name + ".txt")
    if os.path.exists(path):
        continue
    try:
        d = get(title)
        text = clean(d["parse"]["text"]["*"])
        open(path, "w").write(f"# {title} (zh.wikisource.org, public domain)\n" + text + "\n")
        print(name, len(text))
    except Exception as e:
        print("FAIL", name, title, e, file=sys.stderr)
    time.sleep(1)
