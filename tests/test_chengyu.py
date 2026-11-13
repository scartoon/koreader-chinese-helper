"""Unit tests for tools/chengyu.py (the 成語典 and Xinhua idiom files;
tools/check.sh runs them)."""
import io
import os
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import chengyu  # noqa: E402


class XinhuaExplanation(unittest.TestCase):
    def clean(self, word, text):
        return chengyu.clean_xinhua_explanation(word, text)

    def test_two_glosses(self):
        self.assertEqual(
            self.clean("首鼠两端", "首鼠鼠性多疑，出洞时一进一退，不能自决；两端拿不定主意。在两者之间犹豫不决。"),
            "首鼠：鼠性多疑，出洞时一进一退，不能自决；两端：拿不定主意。在两者之间犹豫不决。")

    def test_one_character_gloss_after_a_two_character_one(self):
        self.assertEqual(self.clean("层峦迭嶂", "层峦重重叠叠的山岭；嶂直立像屏障的山。形容山峰重叠。"),
                         "层峦：重重叠叠的山岭；嶂：直立像屏障的山。形容山峰重叠。")

    def test_one_character_at_the_start_left_alone(self):
        # 鼻 starts the sentence but is not glossed (鼻子发青).
        self.assertEqual(self.clean("鼻青额肿", "鼻子发青，额头肿起。形容被打得很惨。"),
                         "鼻子发青，额头肿起。形容被打得很惨。")
        self.assertEqual(self.clean("一毛不拔", "一根汗毛也不肯拔。形容为人非常吝啬自私。"),
                         "一根汗毛也不肯拔。形容为人非常吝啬自私。")

    def test_nothing_after_the_clause(self):
        # 有国家却不能回去 is the whole explanation, not 有国 glossed.
        self.assertEqual(self.clean("有国难投", "有国家却不能回去。"), "有国家却不能回去。")

    def test_extended_sense_sign(self):
        self.assertEqual(self.clean("一毛不拔", "原指杨朱的极端为我主义◇形容为人非常吝啬自私。"),
                         "原指杨朱的极端为我主义。形容为人非常吝啬自私。")

    def test_opening_quotes(self):
        self.assertEqual(self.clean("割据一方", "凭借武力割占一个地区，与中央政权对立。亦作各霸一方”。"),
                         "凭借武力割占一个地区，与中央政权对立。亦作“各霸一方”。")
        self.assertEqual(self.clean("鸾漂凤泊", "比喻夫妻离散。亦作“凤泊鸾飘”、飘鸾泊凤”。"),
                         "比喻夫妻离散。亦作“凤泊鸾飘”、“飘鸾泊凤”。")
        self.assertEqual(self.clean("一坐皆惊", "指满座皆惊服。同“一坐尽惊”。"), "指满座皆惊服。同“一坐尽惊”。")

    def test_lost_text_and_numbers(self):
        self.assertEqual(self.clean("沐猴而冠", "比喻虚有其表★形同傀儡。"), "比喻虚有其表…形同傀儡。")
        self.assertEqual(self.clean("八窗玲珑", "①指四壁窗户轩敞。②比喻通达明澈。"), "1.指四壁窗户轩敞。2.比喻通达明澈。")

    def test_empty(self):
        self.assertEqual(self.clean("割据一方", "无"), "")


class XinhuaDerivation(unittest.TestCase):
    def clean(self, text, word=""):
        return chengyu.clean_xinhua_derivation(text, word)

    def test_title_then_text(self):
        self.assertEqual(self.clean("宋·文莹《湘山野录》之乎者也，助得甚事？”"), "宋·文莹《湘山野录》：“之乎者也，助得甚事？”")

    def test_doubled_title_mark_and_inner_quote(self):
        self.assertEqual(self.clean("《吕氏春秋·察今》》楚人有涉江者，遽契其舟曰‘是吾剑之所从坠。’舟止。”"),
                         "《吕氏春秋·察今》：“楚人有涉江者，遽契其舟曰：‘是吾剑之所从坠。’舟止。”")

    def test_numbered_section(self):
        self.assertEqual(self.clean("元·吴昌龄《东坡梦》第一折久闻老师父大名。”"), "元·吴昌龄《东坡梦》第一折：“久闻老师父大名。”")
        self.assertEqual(self.clean("宋·孙光宪《北梦琐言》卷十七苏楷皆人才寝陋。”"), "宋·孙光宪《北梦琐言》卷十七：“苏楷皆人才寝陋。”")

    def test_several_citations(self):
        self.assertEqual(self.clean("《周书·王褒传》云飞泥沉，金铄兰灭。”《隋书·卢思道传》云飞泥沉，卑高异等。”"),
                         "《周书·王褒传》：“云飞泥沉，金铄兰灭。”《隋书·卢思道传》：“云飞泥沉，卑高异等。”")

    def test_poem_left_alone(self):
        # 诗 may be the kind of work (《七哀》诗) or the start of the quotation.
        text = "汉·阮瑀《七哀》诗冥冥九泉室，漫漫长夜台。”"
        self.assertEqual(self.clean(text), text)

    def test_see_also_dropped(self):
        self.assertEqual(self.clean("见拔赵帜易汉帜”。"), "")
        self.assertEqual(self.clean("无"), "")

    def test_idiom_sign(self):
        self.assertEqual(self.clean("《苦斗》说世风日下，就是～！”", "世风日下"), "《苦斗》：“说世风日下，就是世风日下！”")


class XinhuaExample(unittest.TestCase):
    def test_source_and_idiom(self):
        self.assertEqual(chengyu.clean_xinhua_example("刻舟求剑", "便是～，胶柱鼓瑟了！★清·曹雪芹《红楼梦》第一百二十回"),
                         "便是刻舟求剑，胶柱鼓瑟了！ ——清·曹雪芹《红楼梦》第一百二十回")


class IdiomsText(unittest.TestCase):
    def test_source_text(self):
        text = ("孟子曰：「_x000D_\n*1*楊子_x000D_\n取_x000D_\n*2*為我_x000D_\n，拔一毛而利天下，不為也。_x000D_\n"
                "#子莫執中，執中為近之。")
        self.assertEqual(chengyu.source_text(text), ["孟子曰：「楊子取為我，拔一毛而利天下，不為也。", "子莫執中，執中為近之。"])

    def test_separators(self):
        # ＋ (and ＆) between two source passages: a new paragraph, never shown.
        text = "昔日*1*齷齪_x000D_\n不足誇。_x000D_\n＋_x000D_\n唐詩*1*情深詞婉_x000D_\n，故有久久莫知其意者。"
        self.assertEqual(chengyu.source_text(text), ["昔日齷齪不足誇。", "唐詩情深詞婉，故有久久莫知其意者。"])
        self.assertEqual(chengyu.source_text("甲。_x000D_\n＆_x000D_\n乙。"), ["甲。", "乙。"])
        # ＆ between senses: a new line in the view, nothing in the short line.
        self.assertEqual(chengyu.lines_of("比喻甲。褒義。＆比喻乙。褒義。"), ["比喻甲。褒義。", "比喻乙。褒義。"])
        self.assertEqual(chengyu.lines_of("例一。_x000D_\n＆_x000D_\n例二。"), ["例一。", "例二。"])
        self.assertEqual(chengyu.lines_of("注一。_x000D_\n＋_x000D_\n注二。"), ["注一。", "注二。"])
        self.assertEqual(chengyu.one_line("比喻甲。褒義。＆比喻乙。_x000D_\n"), "比喻甲。褒義。比喻乙。")

    def test_source_title(self):
        self.assertEqual(chengyu.source_title("＃《莊子．山木》*1*"), "《莊子．山木》")
        self.assertEqual(chengyu.source_title("※《醒世姻緣傳》第三四回_x000D_\n※《水滸傳》第二四回"),
                         "《醒世姻緣傳》第三四回；《水滸傳》第二四回")
        self.assertEqual(chengyu.source_title("◎1宋．王之道〈惜奴嬌〉詞"), "宋．王之道〈惜奴嬌〉詞")

    def test_own_explanation(self):
        self.assertEqual(chengyu.own_explanation("猶「玉石俱焚」。見「玉石俱焚」條。01.三國魏．陳琳〈檄〉：「大兵一放。」"),
                         "猶「玉石俱焚」。")
        self.assertEqual(chengyu.own_explanation("一根毫毛也不願意拔取。※語本《孟子》。 _x000D_\n△「愛財如命」"),
                         "一根毫毛也不願意拔取。語本《孟子》。")

    def test_only_equals(self):
        self.assertTrue(chengyu.ONLY_EQUALS.match("猶「玉石俱焚」。"))
        self.assertTrue(chengyu.ONLY_EQUALS.match("㕙，兔。盧，黑色獵犬。「㕙盡盧烹」猶「兔死狗烹」。"))
        self.assertFalse(chengyu.ONLY_EQUALS.match("比喻有限的本領。"))

    def test_first_reading(self):
        self.assertEqual(chengyu.first_reading("yī máo bù bá （變） yì máo bù bá"), "yī máo bù bá")

    def test_shorten(self):
        self.assertEqual(chengyu.shorten("甲。" * 60, 10), "甲。" * 5)
        self.assertEqual(chengyu.shorten("短。"), "短。")

    def test_boxes_dropped(self):
        stats = Counter()
        self.assertEqual(chengyu.no_boxes(["好", "字", "𠟃足"], stats, "x"), ["好"])
        self.assertEqual(stats["x: lines with characters fonts draw as a box (dropped)"], 2)


HEADER = ["編號", "成語", "注音", "漢語拼音", "釋義", "典源文獻名稱", "典源文獻內容", "典源注解", "典源參考資料", "典故說明",
          "書證", "用法說明-語義說明", "用法說明-使用類別", "用法說明-例句", "辨識-形音辨誤", "辨識-同", "辨識-異", "辨識-例句",
          "近義成語", "反義成語", "參考詞語", "主條成語／非主條成語"]


def tiny_xlsx(rows):
    """A minimal workbook with inline strings."""
    def cell(ref, v):
        v = v.replace("&", "&amp;").replace("<", "&lt;")
        return f'<c r="{ref}" t="inlineStr"><is><t>{v}</t></is></c>'
    letters = [chr(65 + k) if k < 26 else "A" + chr(65 + k - 26) for k in range(len(HEADER))]
    xml = ['<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>']
    for i, r in enumerate([HEADER] + rows, 1):
        xml.append(f'<row r="{i}">' + "".join(cell(f"{letters[k]}{i}", v) for k, v in enumerate(r) if v) + "</row>")
    xml.append("</sheetData></worksheet>")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("xl/worksheets/sheet1.xml", "".join(xml))
    return buf.getvalue()


def row(**kw):
    return [kw.get(h, "") for h in HEADER]


class IdiomsEntries(unittest.TestCase):
    def setUp(self):
        main = row(成語="玉石俱焚", 漢語拼音="yù shí jù fén", 釋義="美玉和石頭一起燒毀。",
                   典源文獻名稱="《書經．胤征》", 典源文獻內容="火炎*1*崐岡_x000D_\n，玉石俱焚。", 典源注解="崐岡：崑崙山。",
                   典故說明="夏帝仲康時……", 書證="01.《三國志》：「玉石俱焚。」（源）",
                   **{"用法說明-語義說明": "比喻好壞同時受害。", "主條成語／非主條成語": "主條成語",
                      "近義成語": "同歸於盡"})
        sub = row(成語="玉石俱碎", 漢語拼音="yù shí jù suì", 釋義="猶「玉石俱焚」。見「玉石俱焚」條。01.陳琳〈檄〉：「玉石俱碎。」",
                  典源文獻內容="此處所列為「玉石俱焚」之典源，提供參考。", 典故說明="此處所列為「玉石俱焚」之典故說明，提供參考。夏帝……",
                  書證="01.陳琳〈檄〉：「玉石俱碎。」", **{"主條成語／非主條成語": "非主條成語"})
        with tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False) as f:
            f.write(tiny_xlsx([main, sub]))
            self.path = f.name

    def tearDown(self):
        os.remove(self.path)

    def test_entries(self):
        rows = chengyu.read_xlsx(self.path)
        self.assertEqual(rows[0]["成語"], "玉石俱焚")
        out = {e["trad"]: e for e in chengyu.idioms_entries(rows, Counter())}
        main, sub = out["玉石俱焚"], out["玉石俱碎"]
        self.assertEqual(main["short"], "比喻好壞同時受害。")
        self.assertEqual(sub["short"], "猶「玉石俱焚」：比喻好壞同時受害。")
        view = chengyu.view_text(main["sections"])
        self.assertIn("典源　《書經．胤征》\n火炎崐岡，玉石俱焚。", view)
        self.assertIn("书证\n01.《三國志》：「玉石俱焚。」\n", view)
        self.assertIn("近义：同歸於盡", view)
        sub_view = chengyu.view_text(sub["sections"])
        self.assertTrue(sub_view.startswith("释义\n猶「玉石俱焚」。\n\n书证\n01.陳琳"))
        self.assertIn("典源（玉石俱焚）　《書經．胤征》", sub_view)
        self.assertIn("典故说明（玉石俱焚）\n夏帝仲康時……", sub_view)
        self.assertNotIn("提供參考", sub_view)

    def test_tables(self):
        stats = Counter()
        entries = [{"simp": "玉石俱焚", "trad": "玉石俱焚", "pinyin": "yù", "short": "比喻/好坏", "view": "v"},
                   {"simp": "一毛不拔", "trad": "一毛不拔", "pinyin": "yī", "short": "吝啬", "view": ""}]
        fallback, idioms = chengyu.tables(entries, "idioms", {"一毛不拔"}, stats)
        self.assertEqual(fallback, [("玉石俱焚", "玉石俱焚", "yù", "", "比喻／好坏", "idioms")])
        self.assertEqual(len(idioms), 2)
        con = sqlite3.connect(":memory:")
        chengyu.write_idioms(con, idioms)
        got = con.execute(chengyu.idioms_sql(2), ["一毛不拔", "", "", ""]).fetchall()
        self.assertEqual(got, [("一毛不拔", "一毛不拔", "吝啬", "")])


if __name__ == "__main__":
    unittest.main()
