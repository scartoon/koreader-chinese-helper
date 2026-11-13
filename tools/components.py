"""Character component analyses from English Wiktionary (kaikki), Make Me a
Hanzi and yi-bai/ids, shared by tools/measure_components.py and the database
build.

Wiktionary (CC BY-SA 4.0): the `Han compound` template of a character entry
gives the parts (args 1, 2, ...), their roles (c1, c2, ...: p phonetic,
s semantic), the gloss of the sense each contributes (t1, ...), a displayed
alternative form (alt1: 氵 for 水), and abbreviated parts (abb1). Simplified
characters carry a `Han simp` template naming the traditional form, or are
soft redirects to it.

Make Me a Hanzi dictionary.txt (LGPL v3): `decomposition` (IDS) and
`etymology` (type ideographic / pictographic / pictophonetic, with semantic
and phonetic for pictophonetic). Its `hint` text is never shown (a learner
mnemonic, wrong for simplified characters).

yi-bai/ids ids_lv2.txt (MIT): structure only.
"""
import gzip
import unicodedata
import json
import os
import re

IDC = {c: 2 for c in "⿰⿱⿴⿵⿶⿷⿸⿹⿺⿻⿼⿽⿾⿿㇯"}
IDC.update({"⿲": 3, "⿳": 3})

# Radical forms: {form: (full character, common name or "")}. 阝 is handled by
# position (left 阜, right 邑).
RADICAL_FORMS = {
    "氵": ("水", "三点水"), "氺": ("水", ""), "扌": ("手", "提手旁"), "龵": ("手", ""),
    "亻": ("人", "单人旁"), "忄": ("心", "竖心旁"), "⺗": ("心", ""), "㣺": ("心", ""),
    "讠": ("言", "言字旁"), "訁": ("言", ""), "钅": ("金", "金字旁"), "釒": ("金", ""),
    "纟": ("糸", "绞丝旁"), "糹": ("糸", ""), "饣": ("食", "食字旁"), "飠": ("食", ""),
    "𩙿": ("食", ""), "礻": ("示", "示字旁"), "衤": ("衣", "衣字旁"),
    "艹": ("艸", "草字头"), "⺾": ("艸", "草字头"), "⺿": ("艸", "草字头"), "䒑": ("艸", ""),
    "⺮": ("竹", "竹字头"), "𥫗": ("竹", "竹字头"),
    "辶": ("辵", "走之旁"), "⻌": ("辵", "走之旁"), "⻍": ("辵", "走之旁"), "⻎": ("辵", "走之旁"),
    "犭": ("犬", "反犬旁"), "灬": ("火", "四点底"), "⺼": ("肉", "肉月旁"),
    "刂": ("刀", "立刀旁"), "⺈": ("刀", ""), "攵": ("攴", "反文旁"),
    "罒": ("网", "四字头"), "⺲": ("网", "四字头"), "⺫": ("网", ""), "覀": ("襾", "西字头"),
    "耂": ("老", "老字头"), "爫": ("爪", "爪字头"), "丬": ("爿", "将字旁"),
    "牜": ("牛", "牛字旁"), "⺧": ("牛", ""), "𧾷": ("足", "足字旁"), "⻊": ("足", "足字旁"),
    "⺶": ("羊", ""), "⺷": ("羊", ""), "𦍌": ("羊", ""), "⻗": ("雨", ""),
    "镸": ("長", ""), "𤣩": ("玉", "斜玉旁"), "⺩": ("玉", "斜玉旁"), "⺻": ("聿", ""),
    "⺌": ("小", ""), "⺍": ("小", ""), "⺊": ("卜", ""), "㔾": ("卩", ""), "⺋": ("卩", ""),
    "⺁": ("厂", ""), "⺆": ("冂", ""), "⺄": ("乙", ""), "⺃": ("乙", ""), "⺀": ("冫", ""),
    "⺙": ("攴", "反文旁"), "⺝": ("月", ""), "⺺": ("聿", ""), "⻞": ("食", ""),
    "⻠": ("食", ""), "⻢": ("馬", ""), "⻣": ("骨", ""), "⻤": ("鬼", ""), "⻥": ("魚", ""),
    "⻦": ("鳥", ""), "⻨": ("麥", ""), "⻩": ("黃", ""), "⻬": ("齊", ""), "⻮": ("齒", ""),
    "⻯": ("龍", ""), "⻱": ("龜", ""), "⻰": ("龍", ""), "⻜": ("飛", ""), "⻛": ("風", ""),
    "⻚": ("頁", ""), "⻙": ("韋", ""), "⻘": ("青", ""), "⻔": ("門", ""), "⻓": ("長", ""),
    "⻑": ("長", ""), "⻋": ("車", ""), "⻉": ("貝", ""), "⻇": ("見", ""), "⻆": ("角", ""),
    "⻈": ("言", ""), "⻄": ("西", ""), "⻁": ("虎", ""), "⺺": ("聿", ""),
}
FORM_NAMES = {"宀": "宝盖头", "冖": "秃宝盖", "疒": "病字旁", "廴": "建之旁", "彳": "双人旁",
              "广": "广字旁", "尸": "尸字头", "囗": "国字框", "冂": "同字框", "匚": "三框",
              "厂": "厂字旁", "卩": "单耳旁", "癶": "登字头", "穴": "穴宝盖", "隹": "",
              "冫": "两点水", "彡": "三撇", "夂": "", "攴": "", "亠": "点横头"}
LEFT_EAR, RIGHT_EAR = ("阜", "左耳旁"), ("邑", "右耳旁")
EAR = set("阝⻖⻏")


def base_form(form, position=None):
    """(full character, name) for a radical form; position "left"/"right"
    decides 阝."""
    if form in EAR:
        if position == "left":
            return LEFT_EAR
        if position == "right":
            return RIGHT_EAR
        return (form, "")
    if form in RADICAL_FORMS:
        return RADICAL_FORMS[form]
    return (form, FORM_NAMES.get(form, ""))


# ---------------------------------------------------------------- IDS

def parse_ids(s):
    """Parse an IDS string into a tree: a single character (str) or
    (operator, [children]). Returns None on malformed input."""
    pos = 0

    def node():
        nonlocal pos
        if pos >= len(s):
            raise ValueError
        c = s[pos]
        pos += 1
        if c in IDC:
            return (c, [node() for _ in range(IDC[c])])
        return c
    try:
        t = node()
    except ValueError:
        return None
    return t if pos == len(s) else None


def flat(tree):
    if isinstance(tree, str):
        return tree
    return tree[0] + "".join(flat(c) for c in tree[1])


def top_parts(tree):
    """[(text, position)] for the top-level children of an IDS tree. Text is
    one character, or a flattened sub-IDS for an unencoded part."""
    if tree is None or isinstance(tree, str):
        return []
    op, kids = tree
    out = []
    for i, k in enumerate(kids):
        pos = None
        if op in "⿰⿲":
            pos = "left" if i == 0 else ("right" if i == len(kids) - 1 else "middle")
        out.append((flat(k), pos))
    return out


# ---------------------------------------------------------------- Wiktionary

def _wikt_cache(src_dir):
    """Single-character entries of the kaikki dump, cached as JSONL (the full
    dump takes a minute to read)."""
    cache = os.path.join(src_dir, "char_etym.jsonl")
    gz = os.path.join(src_dir, "kaikki-Chinese.jsonl.gz")
    if not os.path.exists(cache) or os.path.getmtime(cache) < os.path.getmtime(gz):
        seen = set()
        with gzip.open(gz, "rt", encoding="utf-8") as f, open(cache + ".tmp", "w", encoding="utf-8") as out:
            for line in f:
                e = json.loads(line)
                w = e.get("word", "")
                if len(w) != 1 or e.get("lang_code") != "zh":
                    continue
                pos = e.get("pos")
                key = (w, pos if pos == "soft-redirect" else "", e.get("etymology_number"),
                       e.get("etymology_text"))
                if key in seen:
                    continue
                seen.add(key)
                out.write(json.dumps({"w": w, "pos": pos, "n": e.get("etymology_number"),
                                      "text": e.get("etymology_text"),
                                      "tpl": e.get("etymology_templates") or [],
                                      "redirects": e.get("redirects") or []},
                                     ensure_ascii=False) + "\n")
        os.replace(cache + ".tmp", cache)
    with open(cache, encoding="utf-8") as f:
        for line in f:
            yield json.loads(line)


def _han_compound(args):
    parts = []
    i = 1
    while str(i) in args:
        form = args[str(i)].strip()
        if not form:
            i += 1
            continue
        role = args.get(f"c{i}", "").strip()
        parts.append({
            "form": form,
            "alt": args.get(f"alt{i}", "").strip(),
            "role": role if role in ("p", "s") else "",
            "gloss": args.get(f"t{i}", "").strip(),
            "abbr": bool(args.get(f"abb{i}")),
        })
        i += 1
    return parts


def load_wiktionary(src_dir):
    """{ch: {"compound": analysis or None, "simp_of": traditional form or
    None, "text": etymology prose of the entry used}}.

    analysis: {"type": "psc"/"ic"/"", "parts": [...], "disputed": bool}. The
    first `Han compound` of the first etymology section that has one is used;
    "disputed" when that section records another analysis (a second
    `Han compound`, or `liushu` types that disagree)."""
    out = {}
    for e in _wikt_cache(src_dir):
        ch = e["w"]
        d = out.setdefault(ch, {"compound": None, "simp_of": None, "text": None,
                                "simp_changes": [], "liushu": None, "liushu_text": None,
                                "simp_text": None})
        if e["pos"] == "soft-redirect":
            if not d["simp_of"] and e["redirects"]:
                d["simp_of"] = e["redirects"][0]
            continue
        tpl = e["tpl"]
        if d["liushu"] is None:
            types = [t["args"].get("1", "").strip() for t in tpl if t["name"] == "liushu"]
            if types:
                d["liushu"] = types
                d["liushu_text"] = e["text"]
        for t in tpl:
            if t["name"] == "Han simp" and not d["simp_text"]:
                d["simp_text"] = e["text"]
            if t["name"] == "Han simp" and not d["simp_of"]:
                a = t["args"]
                d["simp_of"] = a.get("1", "").strip() or None
                ch_ = []
                for suf in ("", "2", "3", "4"):
                    if a.get("f" + suf) and a.get("t" + suf):
                        ch_.append((a["f" + suf], a["t" + suf]))
                d["simp_changes"] = ch_
        if d["compound"]:
            continue
        hcs = [t for t in tpl if t["name"] == "Han compound"]
        if not hcs:
            continue
        a = hcs[0]["args"]
        parts = _han_compound(a)
        if not parts:
            continue
        types = {t["args"].get("1", "").strip() for t in tpl if t["name"] == "liushu"}
        types.discard("")
        disputed = len(hcs) > 1 or len(types - {a.get("ls", ""), a.get("ls2", "")}) > 0
        d["compound"] = {"type": a.get("ls", "").strip(), "type2": a.get("ls2", "").strip(),
                         "parts": parts, "disputed": disputed}
        d["text"] = e["text"]
    if "" in out:
        del out[""]
    return out


def wikt_simp_links(wikt):
    return {ch: d["simp_of"] for ch, d in wikt.items() if d["simp_of"]}


# ---------------------------------------------------------------- Make Me a Hanzi

def load_mmah(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            out[e["character"]] = e
    return out


def mmah_analysis(e):
    """{"type": "psc"/"ic"/"pictogram"/"", "parts": [...]} from a Make Me a
    Hanzi entry. Pictophonetic: the semantic and phonetic parts, in the
    order of the decomposition. Ideographic: the top-level parts of the
    decomposition, no roles. Pictographic: no parts."""
    et = e.get("etymology") or {}
    typ = et.get("type")
    tree = parse_ids(e.get("decomposition") or "")
    tops = top_parts(tree)
    position = {t: p for t, p in tops}
    if typ == "pictophonetic" and et.get("semantic") and et.get("phonetic"):
        sem, pho = et["semantic"], et["phonetic"]
        parts = [{"form": sem, "role": "s", "pos": position.get(sem)},
                 {"form": pho, "role": "p", "pos": position.get(pho)}]
        order = [t for t, _ in tops]
        if pho in order and sem in order and order.index(pho) < order.index(sem):
            parts.reverse()
        return {"type": "psc", "parts": parts}
    if typ == "pictographic":
        return {"type": "pictogram", "parts": []}
    parts = [{"form": t, "role": "", "pos": p} for t, p in tops
             if len(t) == 1 and t not in "？"]
    if len(parts) != len(tops):
        parts = []
    return {"type": "ic" if typ == "ideographic" else "", "parts": parts}


# ---------------------------------------------------------------- comparison

def norm(form, pos=None):
    return base_form(form, pos)[0]


def compare(wc, mc, t2s=None):
    """None if the analyses agree, else "parts" or "roles". Parts are
    compared after mapping radical forms to full characters (and through
    t2s, a {traditional: simplified} dict, when given)."""
    def key(f, pos=None):
        f = norm(f, pos)
        return t2s.get(f, f) if t2s else f
    wp = [key(p["form"]) for p in wc["parts"]]
    wp_alt = [key(p["alt"]) if p["alt"] else None for p in wc["parts"]]
    mp = [key(p["form"], p.get("pos")) for p in mc["parts"]]
    def same(i, m):
        return m == wp[i] or m == wp_alt[i]
    if len(wp) != len(mp):
        return "parts"
    used = set()
    match = {}
    for j, m in enumerate(mp):
        for i in range(len(wp)):
            if i not in used and same(i, m):
                used.add(i)
                match[j] = i
                break
        else:
            return "parts"
    w_psc = wc["type"] == "psc" or wc.get("type2") == "psc" or any(p["role"] == "p" for p in wc["parts"])
    m_psc = mc["type"] == "psc"
    if w_psc != m_psc:
        return "roles"
    if m_psc:
        for j, p in enumerate(mc["parts"]):
            if p["role"] == "p" and wc["parts"][match[j]]["role"] != "p":
                return "roles"
    return None


def describe(a):
    bits = []
    for p in a["parts"]:
        s = p["form"]
        if p.get("alt"):
            s += f"({p['alt']})"
        if p.get("abbr"):
            s += "[abbr]"
        if p.get("role"):
            s += ":" + p["role"]
        if p.get("gloss"):
            s += f" “{p['gloss']}”"
        bits.append(s)
    t = a.get("type", "")
    if a.get("type2"):
        t += "+" + a["type2"]
    return f"{t} " + " + ".join(bits) + (" [disputed]" if a.get("disputed") else "")


# ---------------------------------------------------------------- yi-bai/ids

_IDS_TAIL = re.compile(r"\([^)]*\)$")


def load_ids(path):
    """{ch: IDS string}: the first primary sequence of each character, when
    it is a plain IDS (no stroke-level or private markup)."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 2:
                continue
            seq = _IDS_TAIL.sub("", cols[1].split(";")[0])
            if any(c in seq for c in "#{}[]()?"):
                continue
            if seq and seq != cols[0] and parse_ids(seq):
                out[cols[0]] = seq
    return out


def visible_forms(ch, ids, depth=4):
    """Every component reachable from `ch` through the IDS table."""
    seen = set()
    todo = [(ch, 0)]
    while todo:
        c, d = todo.pop()
        tree = parse_ids(ids.get(c, "")) if d < depth else None
        stack = [tree] if tree else []
        while stack:
            t = stack.pop()
            if isinstance(t, str):
                if t not in seen:
                    seen.add(t)
                    todo.append((t, d + 1))
            else:
                stack.extend(t[1])
    return seen


# ---------------------------------------------------------------- pinyin match

_INITIALS = ("zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
             "j", "q", "x", "r", "z", "c", "s")
_Y = {"yi": "i", "ya": "ia", "ye": "ie", "yao": "iao", "you": "iou", "yan": "ian", "yin": "in",
      "yang": "iang", "ying": "ing", "yong": "iong", "yu": "ü", "yue": "üe", "yuan": "üan",
      "yun": "ün", "yo": "io"}
_W = {"wu": "u", "wa": "ua", "wo": "uo", "wai": "uai", "wei": "uei", "wan": "uan", "wen": "uen",
      "wang": "uang", "weng": "ueng"}


def toneless(syl):
    """'guān' -> 'guan', 'lǜ' -> 'lü'."""
    s = unicodedata.normalize("NFD", syl.lower())
    s = "".join(c for c in s if c not in "̀́̄̌")
    return unicodedata.normalize("NFC", s).replace("v", "ü")


def final(syl):
    """The final of a toneless syllable, written in full: 'jiu' -> 'iou',
    'yan' -> 'ian', 'xu' -> 'ü', 'gui' -> 'uei'."""
    if syl in _Y:
        return _Y[syl]
    if syl in _W:
        return _W[syl]
    for ini in _INITIALS:
        if syl.startswith(ini) and len(syl) > len(ini):
            f = syl[len(ini):]
            if ini in ("j", "q", "x") and f.startswith("u"):
                f = "ü" + f[1:]
            return {"iu": "iou", "ui": "uei", "un": "uen", "ün": "ün"}.get(f, f)
    return syl


def rhyme(f):
    """The final without its medial: 'iang' -> 'ang', 'uei' -> 'ei',
    'üan' -> 'an'; 'i', 'in', 'ing', 'u', 'ü', 'ün' stay."""
    if len(f) > 1 and f[0] in "iuü" and f[1] in "aeoiu":
        return f[1:]
    return f


def match_label(part_reading, char_reading):
    """"same" (same syllable, tone aside), "ending" (same final) or "loose"."""
    a, b = toneless(part_reading), toneless(char_reading)
    if not a or not b:
        return ""
    if a == b:
        return "same"
    if rhyme(final(a)) == rhyme(final(b)):
        return "ending"
    return "loose"


MATCH_ORDER = {"same": 0, "ending": 1, "loose": 2, "": 3}


# ---------------------------------------------------------------- the table

# Systematic simplified radicals that are not the simplified form of the full
# character (t2s(金) is 金, but on the left it is written 钅).
SIMP_RADICAL = {"金": "钅", "釒": "钅", "言": "讠", "訁": "讠", "食": "饣", "飠": "饣", "𩙿": "饣",
                "糸": "纟", "糹": "纟"}
# Written forms a part's full character takes inside another character.
VISIBLE = {}
for _f, (_b, _n) in RADICAL_FORMS.items():
    VISIBLE.setdefault(_b, []).append(_f)
VISIBLE.setdefault("阜", []).extend(["阝", "⻖"])
VISIBLE.setdefault("邑", []).extend(["阝", "⻏"])
VISIBLE.setdefault("肉", []).append("月")
VISIBLE.setdefault("玉", []).append("王")
EXTRA_NAMES = {("肉", "月"): "肉月旁", ("玉", "王"): "斜玉旁", ("阜", "阝"): "左耳旁", ("邑", "阝"): "右耳旁",
               ("阜", "⻖"): "左耳旁", ("邑", "⻏"): "右耳旁"}

_SKIP_SENSE = re.compile(r"^(old |archaic |ancient |erroneous |Japanese |\(old\) |\(archaic\) )?"
                         r"(variant|form) of|^see |^see also|^surname|Kangxi radical|"
                         r"radical in Chinese characters|^CL:|^used in |^\(Tw\)|^Taiwan pr\.",
                         re.I)


def short_gloss(defs, limit=32):
    """A few words of the first sense worth showing ("to go back; to
    return"), at most about `limit` characters."""
    senses = [x.strip() for x in defs.split("/") if x.strip()]
    kept = [x for x in senses if not _SKIP_SENSE.search(x)] or senses[:1]
    # A long leading qualifier says when the sense applies, not what it is:
    # "(after a verb or adjective) one who ..." -> "one who ...".
    kept = [re.sub(r"^\([^)]{16,}\)\s*", "", x) or x for x in kept]
    subs = []
    for sense in kept:
        subs.extend(x.strip() for x in sense.split(";") if x.strip())
        if len(subs) >= 2:
            break
    out = ""
    for x in subs:
        if len(x) > limit:
            x = x[:limit].rsplit(" ", 1)[0].rstrip(",;(") + "…"
        cand = x if not out else out + "; " + x
        if out and len(cand) > limit:
            break
        out = cand
        if len(out) >= limit * 0.6:
            break
    return out


_OUTSIDE_BMP = re.compile("[\U00010000-\U0010FFFF]")


def displayable(text):
    """No character outside the BMP: KOReader's CJK fonts mostly lack those
    and draw a box, so nothing containing one is shown."""
    return not _OUTSIDE_BMP.search(text)


class Builder:
    """Component rows for the database: build(chars) -> {ch: body}, {ch: note}.

    body: tab-separated lines (ch_components.lua parses them).
      H  source  type  flags  via  changes  choices
         source   wikt / mmah / ids
         type     psc / ic / pictogram / "" (structure only)
         flags    "d" when Wiktionary records a competing analysis
         via      the traditional form whose analysis this is, or ""
         changes  the parts simplification replaced in a way that hides them,
                  "雚>又,見>见" (via rows only)
         choices  a simplified character with several traditional forms:
                  "發=;髮=" (each with its changes), chosen by the word tapped
         origin   another character whose origin note applies too (銃 for 铳,
                  whose parts are 銃's written the simplified way)
      P  form  lookup  role  reading  gloss  match  flags
         form     as written in the character (氵, 阝)
         lookup   the character whose popup the part's button opens (水, 阜),
                  "" when there is nothing to show
         role     s (meaning), p (sound) or ""
         match    same / ending / loose for a sound part
         flags    "a" abbreviated part
    note: Wiktionary's etymology text (the popup's Origin view).
    """

    def __init__(self, entries, chars, wikt, mmah, ids):
        self.wikt, self.mmah, self.ids = wikt, mmah, ids
        self.reading = {ch: r for ch, _, r in chars}
        self.by_form = {}
        self.trads = {}
        self.t2s = {}
        self.stats = __import__("collections").Counter()
        for simp, trad, pinyin, syllables, defs in entries:
            if len(simp) != 1 or len(trad) != 1:
                continue
            row = (syllables, defs, pinyin[:1].isupper())
            for f in {simp, trad}:
                self.by_form.setdefault(f, []).append(row)
            real = not all(re.match(r"^(old |archaic |ancient )?variant of", x) for x in defs.split("/"))
            if real:
                self.trads.setdefault(simp, [])
                if trad not in self.trads[simp]:
                    self.trads[simp].append(trad)
            if simp != trad:
                self.t2s.setdefault(trad, simp)

    # -- helpers

    def readings_of(self, form):
        """[(syllable, defs)] of CC-CEDICT's ordinary entries for one form."""
        out = []
        for syl, defs, proper in self.by_form.get(form, []):
            if proper or " " in syl:
                continue
            if all(_SKIP_SENSE.search(s) for s in defs.split("/")) and len(self.by_form[form]) > 1:
                continue
            out.append((syl, defs))
        if not out:
            out = [(syl, defs) for syl, defs, proper in self.by_form.get(form, []) if " " not in syl]
        return out

    def trad_forms(self, ch):
        """The traditional forms CC-CEDICT gives `ch` other than itself, and
        whether `ch` is also a traditional form itself."""
        ts = self.trads.get(ch, [])
        return [t for t in ts if t != ch], ch in ts

    def visible(self, ch):
        return visible_forms(ch, self.ids)

    def changes(self, s, t):
        """[(from, to)] parts replaced from traditional `t` to simplified
        `s`, or None when the whole shape changed."""
        w = self.wikt.get(s)
        if w and w["simp_of"] == t and w["simp_changes"]:
            return list(w["simp_changes"])
        a, b = parse_ids(self.ids.get(s, "")), parse_ids(self.ids.get(t, ""))
        if isinstance(a, tuple) and isinstance(b, tuple) and a[0] == b[0] and len(a[1]) == len(b[1]):
            pairs = [(flat(y), flat(x)) for x, y in zip(a[1], b[1]) if flat(x) != flat(y)]
            if len(pairs) < len(a[1]):
                return pairs
        return None
        return None

    def transparent(self, pairs):
        if pairs is None:
            return False
        for f, t in pairs:
            if self.t2s.get(f) == t or SIMP_RADICAL.get(f) == t or base_form(f)[0] == base_form(t)[0]:
                continue
            return False
        return True

    def opaque_pairs(self, pairs):
        return [(f, t) for f, t in (pairs or [])
                if not (self.t2s.get(f) == t or SIMP_RADICAL.get(f) == t or base_form(f)[0] == base_form(t)[0])]

    def analysis_of(self, ch):
        """(source, analysis) of a character's own analysis with roles:
        Wiktionary's, else Make Me a Hanzi's phono-semantic one."""
        w = self.wikt.get(ch)
        if w and w["compound"]:
            return "wikt", w["compound"]
        m = self.mmah.get(ch)
        if m:
            a = self.mmah_fixed(m)
            if a["type"] == "psc":
                return "mmah", a
        return None, None

    _PRON = re.compile(r"(\S)\s*(?:also )?provides? the pronunciation")

    def mmah_fixed(self, m):
        """Make Me a Hanzi's analysis, with the phonetic its hint names for an
        "ideographic" entry ("戉 also provides the pronunciation")."""
        a = mmah_analysis(m)
        et = m.get("etymology") or {}
        if et.get("type") == "ideographic" and a["parts"]:
            mm = self._PRON.search(et.get("hint") or "")
            if mm and any(p["form"] == mm.group(1) for p in a["parts"]):
                for p in a["parts"]:
                    p["role"] = "p" if p["form"] == mm.group(1) else "s"
                a["type"] = "psc"
                self.stats["mmah: phonetic from the hint"] += 1
        return a

    # -- part lines

    def part_line(self, ch, char_reading, form, lookup, role, gloss, abbr, visible):
        """One P line. `form` as Wiktionary or MMAH gives it; `lookup` its
        full character (水 for 氵)."""
        shown = form
        name = base_form(form)[1] if form != lookup else ""
        if form not in visible and lookup in VISIBLE:
            for v in VISIBLE[lookup]:
                if v in visible:
                    shown = v
                    name = EXTRA_NAMES.get((lookup, v)) or base_form(v)[1]
                    break
        if shown in EAR and not name:
            name = {"阜": "左耳旁", "邑": "右耳旁"}.get(lookup, "")
        reading, defs, match = "", "", ""
        cands = self.readings_of(lookup) or self.readings_of(form)
        default = self.reading.get(lookup) or self.reading.get(form) or ""
        if cands:
            pick = None
            if role == "p" and char_reading:
                pick = min(cands, key=lambda c: (MATCH_ORDER[match_label(c[0], char_reading)],
                                                 c[0] != default))
            else:
                pick = next((c for c in cands if c[0] == default), cands[0])
            reading, defs = pick
        elif default:
            reading = default
        if role == "p" and reading and char_reading:
            match = match_label(reading, char_reading)
        g = gloss or (short_gloss(defs) if defs else "")
        if name:
            g = f"{g} ({name})" if g else name
        has_popup = bool(self.by_form.get(lookup) or self.ids.get(lookup) or self.wikt.get(lookup, {}).get("compound"))
        target = lookup if has_popup and len(lookup) == 1 else ""
        clean = lambda s: s.replace("\t", " ").replace("\n", " ")
        return "\t".join(["P", shown, target, role, reading, clean(g), match, "a" if abbr else ""])

    def lines_for(self, ch, source, a, via="", changes=(), mapping=None, choices="", origin=""):
        """H and P lines for analysis `a` of `ch` (or of `via`). `origin`:
        another character whose origin note also applies (the traditional
        form a mapped analysis comes from)."""
        about = via or ch
        char_reading = self.reading.get(about, "")
        vis = self.visible(ch if mapping else about)
        typ = a.get("type") or ""
        if a.get("type2") == "psc" or (source == "wikt" and any(p.get("role") == "p" for p in a["parts"])):
            typ = "psc"
        flags = "d" if a.get("disputed") else ""
        head = "\t".join(["H", source, typ, flags, via, ",".join(f"{f}>{t}" for f, t in changes), choices,
                          origin])
        lines = [head]
        for p in a["parts"]:
            form = p.get("alt") or p["form"]
            lookup = base_form(p["form"], p.get("pos"))[0]
            if mapping:
                for f, t in mapping:
                    if f in (p["form"], p.get("alt")):
                        form = t
                        if t in self.by_form and t not in RADICAL_FORMS:
                            lookup = t
            role = p.get("role", "")
            # Wiktionary's ideogrammic compounds: every part gives meaning.
            # (Make Me a Hanzi's "ideographic" is too often a phono-semantic
            # compound to say so.)
            if typ == "ic" and not role and source == "wikt":
                role = "s"
            if not form or any(c in IDC for c in form) or form in "？?":
                return None
            lines.append(self.part_line(ch, char_reading, form, lookup, role, p.get("gloss", ""),
                                        p.get("abbr"), vis))
        return "\n".join(lines)

    # -- one character

    def row(self, ch, structure=True):
        w = self.wikt.get(ch) or {}
        trads, is_trad = self.trad_forms(ch)
        choices = ""
        if len(trads) + (1 if is_trad else 0) > 1:
            bits = []
            for t in trads:
                src, a = self.analysis_of(t)
                bit = f"{t}=" + ",".join(f"{f}>{x}" for f, x in self.opaque_pairs(self.changes(ch, t)))
                if a and displayable(bit):
                    bits.append(bit)
            choices = ";".join(bits)
        body = None
        for cand in self.own_rows(ch, w, trads, is_trad, choices, structure):
            if cand and displayable(cand):
                body = cand
                break
            if cand:
                self.stats["skipped: a character outside the BMP"] += 1
        if body or not choices:
            return body
        # Nothing of its own, but the word tapped may pick a traditional form.
        self.stats["choices only"] += 1
        return "\t".join(["H", "", "", "", "", "", choices])

    def own_rows(self, ch, w, trads, is_trad, choices, structure=True):
        """Candidate rows, best source first (row() takes the first that
        displays cleanly)."""
        # 1. Its own Wiktionary analysis.
        if w.get("compound"):
            self.stats["wikt: own"] += 1
            yield self.lines_for(ch, "wikt", w["compound"], choices=choices)
        # 2. One traditional form: its analysis.
        if len(trads) == 1 and not is_trad:
            t = trads[0]
            src, a = self.analysis_of(t)
            if a:
                pairs = self.changes(ch, t)
                if self.transparent(pairs):
                    self.stats[f"{src}: traditional form, parts mapped"] += 1
                    yield self.lines_for(ch, src, a, mapping=pairs, origin=t)
                self.stats[f"{src}: traditional form shown"] += 1
                yield self.lines_for(ch, src, a, via=t, changes=self.opaque_pairs(pairs))
            kind = self.wikt_kind(t)
            if kind:
                self.stats[f"wikt: traditional form's {kind}"] += 1
                yield self.kind_row(ch, kind, via=t, choices=choices)
        # 3. A Wiktionary pictogram or indicative (指事).
        kind = self.wikt_kind(ch)
        if kind:
            self.stats["wikt: " + kind] += 1
            yield self.kind_row(ch, kind, choices=choices)
        # 4. Make Me a Hanzi; roles only where no simplification hid a part.
        m = self.mmah.get(ch)
        hidden = any(self.opaque_pairs(self.changes(ch, t)) or self.changes(ch, t) is None for t in trads)
        if m:
            a = self.mmah_fixed(m)
            if hidden:
                a = {"type": "", "parts": [dict(p, role="") for p in a["parts"]]}
                self.stats["mmah: roles dropped (simplified, part hidden)"] += int(bool(a["parts"]))
            if a["type"] == "pictogram" and not hidden:
                self.stats["mmah: pictogram"] += 1
                yield "\t".join(["H", "mmah", "pictogram", "", "", "", choices])
            if a["parts"]:
                body = self.lines_for(ch, "mmah", a, choices=choices)
                if body:
                    self.stats["mmah: " + (a["type"] or "structure")] += 1
                    yield body
        # 5. Structure only.
        tree = parse_ids(self.ids.get(ch, "")) if structure else None
        if isinstance(tree, tuple):
            leaves = []
            for k in tree[1]:
                if isinstance(k, str):
                    leaves.append(k)
                else:
                    leaves.extend(x for x in k[1] if isinstance(x, str))
                    if any(not isinstance(x, str) for x in k[1]):
                        leaves = None
                        break
            if leaves and len(leaves) <= 4:
                ops = top_parts(tree)
                pos = {t: p for t, p in ops}
                a = {"type": "", "parts": [{"form": x, "role": "", "pos": pos.get(x)} for x in leaves]}
                body = self.lines_for(ch, "ids", a, choices=choices)
                if body:
                    self.stats["ids: structure"] += 1
                    yield body

    def wikt_kind(self, ch):
        """"pictogram" or "indicative" when that is all Wiktionary says of
        the character's type (no Han compound), else None."""
        w = self.wikt.get(ch) or {}
        ls = w.get("liushu")
        if w.get("compound") or not ls:
            return None
        return {"p": "pictogram", "i": "indicative"}.get(ls[0])

    def kind_row(self, ch, kind, via="", choices=""):
        """An H line for a pictogram or indicative: disputed when Wiktionary
        gives the character more than one type."""
        about = via or ch
        flags = "d" if len(set(self.wikt[about]["liushu"])) > 1 else ""
        return "\t".join(["H", "wikt", kind, flags, via, "", choices])

    def note(self, ch):
        """Wiktionary's text from the etymology section that gave the
        analysis (its Han compound, its type, or `Han simp`)."""
        w = self.wikt.get(ch) or {}
        text = w.get("text") or w.get("liushu_text") or w.get("simp_text")
        if not text or not text.strip()[:1].isalnum() or not displayable(text):
            return None
        text = text.strip()
        return text[:4000] + ("…" if len(text) > 4000 else "")

    def build(self, chars, structure_for=None):
        """{ch: body} and {ch: note} for `chars` and every part they reach.
        Rows giving the structure alone (yi-bai/ids) only for characters in
        `structure_for` (all when None) and for parts."""
        bodies, notes = {}, {}
        todo = [(ch, False) for ch in chars]
        seen = set()
        while todo:
            ch, is_part = todo.pop()
            if ch in seen or len(ch) != 1:
                continue
            allowed = structure_for is None or is_part or ch in structure_for
            body = self.row(ch, allowed)
            if allowed or body:
                seen.add(ch)   # (else a visit as a part may still give it a structure)
            if not body:
                continue
            bodies[ch] = body
            for line in body.split("\n"):
                f = line.split("\t")
                if f[0] == "H":
                    if f[4]:
                        todo.append((f[4], True))
                    for c in f[6].split(";"):
                        if c:
                            todo.append((c.split("=")[0], True))
                elif f[0] == "P" and f[2]:
                    todo.append((f[2], True))
        for ch in bodies:
            n = self.note(ch)
            if n:
                notes[ch] = n
        return bodies, notes
