"""Traditional -> simplified conversion of dictionary prose, shared by the
build scripts (Wiktionary in tools/fallback_sources.py, MOE in
tools/build_moe.py, and phase 3's 成語典).

    from simplify import Simplifier
    s = Simplifier("tw2s")          # Taiwan-standard text (MOE, 成語典)
    s = Simplifier("t2s")           # everything else
    s.convert("清代學者，著有《說文解字注》。")   # -> 清代学者，著有《说文解字注》。

OpenCC does the conversion, character by character with its phrase lists
(never tw2sp: that also swaps vocabulary, 滑鼠 -> 鼠标, which is wrong
inside classical quotations). On top of OpenCC:

  1. 著 meaning "to write" or "notable" stays 著. OpenCC turns 著有, 所著,
     撰著, 原著, 土著, 卓著, 著《...》 and the like into 着 (the aspect
     particle 看著 -> 看着 is right). WRITE_ZHE lists the contexts;
     AUTHOR_ZHE adds the author of a book description (書名。清王國維著。).
  2. 徵 the musical note (宮商角徵羽) stays 徵; elsewhere 徵 -> 征 is right
     (特徵, 象徵, 徵收).
  3. A single character quoted in 「」 stays as written: the form is the
     point (澤，通「襗」, not 通「𫋷」). Longer quotations are citations and
     are converted.
  4. A character whose simplified form is outside the BMP stays
     traditional (顗 not 𫖮, 鑪 not 𬬻): the device fonts draw those as a box.
  5. Japanese kanji stay as written: Han characters followed by hiragana
     (時の, 刻のなみだ). They are not traditional Chinese.
  6. 甚麼 -> 甚么, as OpenCC gives it (not 什么).

OpenCC's t2s and tw2s map one character to one character, so the fixes work
by position: convert the whole string, then put back the original character
wherever a rule says to keep it. If a conversion ever changes the length,
the text is converted in pieces between the kept characters instead.

For Wiktionary, wiktionary() also collapses its "traditional／simplified"
pairs to the simplified side, and keeps a single character named in a
form relation ("variant of 乾", "same as 齟") as written.
"""
import re

HAN = "㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f"
# Kana, without the katakana middle dot (MOE writes 唐・劉禹錫 with it).
KANA_CHARS = "\u3041-\u309f\u30a0-\u30fa\u30fc-\u30ff\u31f0-\u31ff"
KANA = re.compile(f"[{KANA_CHARS}]")
# Japanese kanji: Han characters followed by hiragana, after kana, an
# opening quote or bracket or a colon (“君は刻のなみだ”,
# 日语：特別な気分). Not Chinese before a Japanese word (為日語さようなら),
# after one (おばさん的音譯) or around a katakana loanword (日語バール的).
JAPANESE = re.compile(f"(?<=[{KANA_CHARS}「『“‘（(：:])[{HAN}]+(?=[\u3041-\u309f])")

# Contexts (in the traditional text) where 著 is zhù "to write; notable".
# Each pattern matches at a 著 that is to stay. 著有 after a verb is the
# aspect particle (趁著有利的形勢, 拉著有兩個輪子的車), so 著有 needs a
# clause start, a word like 並/又/所 before it, or a title after it.
WRITE_ZHE = re.compile(
    "(?:^|(?<=[，。；：、並另又所譯曾自也亦尚]))著(?=有)"   # 。著有, 並著有, 所著有
    "|著(?=有[《「〈])"                       # 張機著有《傷寒雜病論》
    "|著(?=[書《〈])"                         # 著書, 著《史記》
    "|(?<=[所撰編合原遺論譯專土卓巨拙新舊共參名昭顯])著(?![眼想手重急落陸色迷魔力地])"  # 所著, 撰著, 土著, 卓著
    "|(?<=不)著(?=撰人)"                      # 不著撰人 "author not recorded"
    "|(?<=知)著"                              # 見微知著
    "|(?<=）)著(?=[，。])"                    # 亞米契斯（Edmondo de Amicis）著。
)
# The author in a book's description: 書名。清王國維著。 / 世親著，一卷。
BOOK = re.compile("^(?:書名|篇名|佛教典籍)|典籍")
AUTHOR_ZHE = re.compile("(?:^|(?<=[。；]))([^，、。；：「」《》]{1,12})著(?=[，。；]|$)")

# 徵 zhǐ, the fourth of the five notes, next to another note.
NOTE_ZHI = re.compile("(?<=[宮宫商角羽、])徵(?=[羽、])|(?<=[宮宫商角])徵|徵(?=[羽])")
SINGLE_QUOTED = re.compile("(?<=「)(.)(?=」)")


class Simplifier:
    def __init__(self, config="t2s"):
        import opencc
        if config not in ("t2s", "tw2s"):
            raise ValueError(f"use t2s or tw2s, not {config} (tw2sp swaps vocabulary)")
        self.config = config
        self._cc = opencc.OpenCC(config)

    def opencc(self, text):
        """OpenCC alone, without the fixes."""
        return self._cc.convert(text)

    def kept(self, text):
        """Positions in `text` whose character stays as written (rules 1, 2, 3, 5)."""
        keep = set()
        for rx in (WRITE_ZHE, NOTE_ZHI, SINGLE_QUOTED):
            keep.update(m.start() for m in rx.finditer(text))
        if KANA.search(text):
            for m in JAPANESE.finditer(text):
                keep.update(range(m.start(), m.end()))
        if "著" in text and BOOK.search(text):
            keep.update(m.end(1) for m in AUTHOR_ZHE.finditer(text))
        return keep

    def convert(self, text, keep=()):
        """`text` in simplified characters, with the fixes above. keep: more
        positions to leave as written."""
        if not text:
            return text
        conv = self._cc.convert(text)
        if conv == text:
            return text
        keep = self.kept(text) | set(keep)
        if len(conv) != len(text):
            return self._convert_pieces(text, keep)
        out = []
        for i, (a, b) in enumerate(zip(text, conv)):
            if i in keep or (ord(b) > 0xFFFF and ord(a) <= 0xFFFF):
                out.append(a)
            else:
                out.append(b)
        return "".join(out)

    def _convert_pieces(self, text, keep):
        out, start = [], 0
        for i in sorted(keep) + [len(text)]:
            piece = text[start:i]
            conv = self._cc.convert(piece)
            if len(conv) == len(piece):
                conv = "".join(a if ord(b) > 0xFFFF and ord(a) <= 0xFFFF else b for a, b in zip(piece, conv))
            out.append(conv)
            if i < len(text):
                out.append(text[i])
            start = i + 1
        return "".join(out)

    # -- Wiktionary --------------------------------------------------------

    # A form: Han characters, with commas inside a quoted saying
    # (宁为鸡口，無為牛後); a pair or a chain of forms joined by ／.
    FORM = f"[{HAN}](?:[{HAN}，]*[{HAN}])?"
    PAIR = re.compile(f"{FORM}(?:[ \u3000]*／[ \u3000]*{FORM})+")
    SLASH = re.compile("[ \u3000]*／[ \u3000]*")
    # "variant of 乾", "same as 齟", "interchangeable with 懾": one character,
    # named as a form.
    RELATION = re.compile(f"(?:variant(?: form)? of|form of|same as|interchangeabl[ey] with|written as \"?)"
                          f" ([{HAN}])(?![{HAN}])")

    def collapse_pairs(self, text):
        """'鵲洲 ／鹊洲' -> '鹊洲' where the last form is the first one's
        simplified form (煙袋鍋 ／菸袋鍋 ／烟袋锅 -> 烟袋锅); pairs OpenCC
        disagrees with (髼鬆／髼鬙) stay as written. Rule 4 applies: 顗／𫖮 -> 顗."""
        def collapse(forms):
            a, b = forms[0], forms[-1]
            if self._cc.convert(a) != b:
                return None
            return self.convert(a) if any(ord(c) > 0xFFFF for c in b) else b

        def repl(m):
            forms = self.SLASH.split(m.group(0))
            out = collapse(forms)
            if out is None and "，" in forms[0] and "，" not in forms[-1]:
                # 鸡，鴨／鸭: only the last form before the slash is paired.
                head, _, last = forms[0].rpartition("，")
                out = collapse([last] + forms[1:])
                return m.group(0) if out is None else head + "，" + out
            return m.group(0) if out is None else out
        return self.PAIR.sub(repl, text)

    def wiktionary(self, sense):
        """A Wiktionary sense in simplified characters."""
        # Pairs first, then everything else; the collapsed side is already
        # simplified (convert leaves it alone), the uncollapsed pairs are
        # protected by position.
        pos, text, protect = 0, "", set()
        for m in self.PAIR.finditer(sense):
            text += sense[pos:m.start()]
            rep = self.collapse_pairs(m.group(0))
            if rep == m.group(0):
                protect.update(range(len(text), len(text) + len(rep)))
            text += rep
            pos = m.end()
        text += sense[pos:]
        protect.update(m.start(1) for m in self.RELATION.finditer(text))
        return self.convert(text, protect)
