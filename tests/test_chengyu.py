"""Unit tests for tools/chengyu.py (the Xinhua idiom file; tools/check.sh
runs them). The 成語典's text is ch_moe.lua's: tests/test_moe.lua."""
import os
import sqlite3
import sys
import unittest
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


class Shared(unittest.TestCase):
    def test_shorten(self):
        self.assertEqual(chengyu.shorten("甲。" * 60, 10), "甲。" * 5)
        self.assertEqual(chengyu.shorten("短。"), "短。")

    def test_boxes_dropped(self):
        stats = Counter()
        self.assertEqual(chengyu.no_boxes(["好", "字", "𠟃足"], stats, "x"), ["好"])
        self.assertEqual(stats["x: lines with characters fonts draw as a box (dropped)"], 2)


class Tables(unittest.TestCase):
    def test_tables(self):
        stats = Counter()
        # The source's text, and (#48) its simplified copy when it differs.
        entries = [{"simp": "玉石俱焚", "trad": "玉石俱焚", "pinyin": "yù", "short": "比喻/好壞", "view": "v",
                    "short_simp": "比喻/好坏", "view_simp": "v"},
                   {"simp": "一毛不拔", "trad": "一毛不拔", "pinyin": "yī", "short": "吝嗇", "view": "",
                    "short_simp": "吝啬", "view_simp": ""},
                   {"simp": "首鼠两端", "trad": "首鼠兩端", "pinyin": "shǒu", "short": "犹豫", "view": ""}]
        fallback, idioms = chengyu.tables(entries, "idioms", {"一毛不拔", "首鼠两端"}, stats)
        self.assertEqual(fallback, [("玉石俱焚", "玉石俱焚", "yù", "", "比喻／好壞", "idioms", "比喻／好坏")])
        self.assertEqual(len(idioms), 3)
        con = sqlite3.connect(":memory:")
        chengyu.write_idioms(con, idioms)
        got = con.execute(chengyu.idioms_sql(2, simp=True), ["一毛不拔", "首鼠两端", "", ""]).fetchall()
        self.assertEqual(got, [("一毛不拔", "一毛不拔", "吝嗇", "", "吝啬", None),
                               ("首鼠两端", "首鼠兩端", "犹豫", "", None, None)])
        got = con.execute(chengyu.idioms_sql(1), ["玉石俱焚", ""]).fetchall()
        self.assertEqual(got, [("玉石俱焚", "玉石俱焚", "比喻/好壞", "v")])


if __name__ == "__main__":
    unittest.main()
