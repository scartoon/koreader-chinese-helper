"""Unit tests for tools/simplify.py (python3 -m unittest tests/test_simplify.py;
tools/check.sh runs them). Needs OpenCC: pip install opencc."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
from simplify import Simplifier  # noqa: E402

TW, T = Simplifier("tw2s"), Simplifier("t2s")


class OpenCCBase(unittest.TestCase):
    def test_plain_prose(self):
        self.assertEqual(TW.convert("唱歌和遊戲。幼稚園和國民小學常排有此項課程。"),
                         "唱歌和游戏。幼稚园和国民小学常排有此项课程。")

    def test_aspect_zhe_still_converted(self):
        self.assertEqual(TW.convert("低著頭，皺著眉"), "低着头，皱着眉")
        self.assertEqual(TW.convert("附著在牆上"), "附着在墙上")

    def test_not_tw2sp(self):
        self.assertEqual(TW.convert("滑鼠"), "滑鼠")
        with self.assertRaises(ValueError):
            Simplifier("tw2sp")

    def test_unchanged_text_returned_as_is(self):
        self.assertEqual(T.convert("to look at; 观"), "to look at; 观")
        self.assertEqual(T.convert(""), "")


class WriteZhe(unittest.TestCase):
    """Fix 1: 著 "to write; notable" stays 著."""

    def test_opencc_gets_it_wrong(self):
        self.assertEqual(TW.opencc("著有"), "着有")

    def test_phrases(self):
        cases = {
            "清代學者。著有《說文解字注》。": "清代学者。著有《说文解字注》。",
            "司馬遷所著的史書": "司马迁所著的史书",
            "所著《史記》": "所著《史记》",
            "撰著": "撰著", "編著": "编著", "原著": "原著", "遺著": "遗著", "論著": "论著",
            "譯著": "译著", "專著": "专著", "土著": "土著", "卓著": "卓著", "拙著": "拙著",
            "著書立說": "著书立说", "不著撰人": "不著撰人", "著〈出師表〉": "著〈出师表〉",
            "合著": "合著", "著作": "著作", "著名": "著名", "顯著": "显著",
        }
        for src, want in cases.items():
            self.assertEqual(TW.convert(src), want, src)

    def test_zhe_you_after_a_verb_is_aspect(self):
        self.assertEqual(TW.convert("比喻趁著有利的形勢做事"), "比喻趁着有利的形势做事")
        self.assertEqual(TW.convert("以小毛驢拉著有兩個輪子的小車"), "以小毛驴拉着有两个轮子的小车")
        self.assertEqual(TW.convert("東漢名醫張機著有《傷寒雜病論》"), "东汉名医张机著有《伤寒杂病论》")
        self.assertEqual(TW.convert("並著有《小倉山房詩集》"), "并著有《小仓山房诗集》")

    def test_aspect_after_listed_characters(self):
        self.assertEqual(TW.convert("相如身自著犢鼻褌"), "相如身自着犊鼻裈")
        self.assertEqual(TW.convert("論著眼於"), "论着眼于")

    def test_author_of_a_book(self):
        self.assertEqual(TW.convert("書名。清王國維著。論詞以境界為尚"), "书名。清王国维著。论词以境界为尚")
        self.assertEqual(TW.convert("書名。宋周邦彥著，二卷，補遺一卷。"), "书名。宋周邦彦著，二卷，补遗一卷。")
        self.assertEqual(TW.convert("佛教典籍。龍樹著。後秦鳩摩羅什譯。"), "佛教典籍。龙树著。后秦鸠摩罗什译。")
        self.assertEqual(TW.convert("義大利亞米契斯（Edmondo de Amicis）著。"), "义大利亚米契斯（Edmondo de Amicis）著。")
        # not a book: the aspect particle stays converted
        self.assertEqual(TW.convert("傻傻地坐著。"), "傻傻地坐着。")

    def test_jian_wei_zhi_zhu(self):
        self.assertEqual(TW.convert("見微知著"), "见微知著")

    def test_aspect_next_to_write_sense(self):
        self.assertEqual(TW.convert("他拿著所著的書"), "他拿着所著的书")


class NoteZhi(unittest.TestCase):
    """Fix 1 (rarer): 徵 the musical note stays; 徵 elsewhere is 征."""

    def test_note(self):
        self.assertEqual(TW.opencc("徵羽"), "征羽")
        self.assertEqual(TW.convert("徵羽"), "徵羽")
        self.assertEqual(TW.convert("宮、商、角、徵、羽"), "宫、商、角、徵、羽")
        self.assertEqual(TW.convert("宮商角徵羽"), "宫商角徵羽")

    def test_other_senses(self):
        self.assertEqual(TW.convert("特徵。象徵。徵收"), "特征。象征。征收")


class SingleQuoted(unittest.TestCase):
    """Fix 2: one character in 「」 stays as written; longer quotations convert."""

    def test_single(self):
        self.assertEqual(TW.convert("澤，通「襗」。"), "泽，通「襗」。")
        self.assertEqual(TW.convert("同「髮」"), "同「髮」")

    def test_longer_quotation(self):
        self.assertEqual(TW.convert("如唐．張志和〈漁歌子〉「青蒻笠，綠簑衣」"),
                         "如唐．张志和〈渔歌子〉「青蒻笠，绿蓑衣」")
        self.assertEqual(TW.convert("「頭髮」"), "「头发」")


class OutsideBMP(unittest.TestCase):
    """Fix 3: keep the traditional character when the simplified one is outside the BMP."""

    def test_kept(self):
        for trad in "顗餔鑪":
            self.assertGreater(ord(TW.opencc(trad)), 0xFFFF, trad)
            self.assertEqual(TW.convert(trad), trad)

    def test_rest_of_text_converted(self):
        self.assertEqual(TW.convert("鑪灶。顗，安靜。"), "鑪灶。顗，安静。")


class Shenme(unittest.TestCase):
    """Fix 4: 甚麼 -> 甚么, as OpenCC gives it."""

    def test(self):
        self.assertEqual(TW.convert("甚麼"), "甚么")


class Japanese(unittest.TestCase):
    def test_japanese_left_alone(self):
        s = "源自宣传语“君は刻のなみだをみる”"
        self.assertEqual(T.convert(s), s)
        self.assertEqual(T.convert("（日语：特別な気分）"), "（日语：特別な気分）")

    def test_chinese_around_japanese_converted(self):
        self.assertEqual(TW.convert("用來拔釘子的工具。日語バール的音譯。"), "用来拔钉子的工具。日语バール的音译。")
        self.assertEqual(TW.convert("為日語おばさん的音譯。"), "为日语おばさん的音译。")
        self.assertEqual(TW.convert("再見。為日語さようなら的音譯。"), "再见。为日语さようなら的音译。")
        self.assertEqual(TW.convert("唐・劉禹錫〈為裴相公賀冊魯王表〉"), "唐・刘禹锡〈为裴相公贺册鲁王表〉")


class Wiktionary(unittest.TestCase):
    def test_pair_collapsed(self):
        self.assertEqual(T.wiktionary("original form of 廩／廪"), "original form of 廪")
        self.assertEqual(T.wiktionary("Milky Way/synonym of 鵲洲 ／鹊洲"), "Milky Way/synonym of 鹊洲")
        self.assertEqual(T.wiktionary("used in 貑羆／貑罴 (“a type of bear”)"), "used in 貑罴 (“a type of bear”)")
        self.assertEqual(T.wiktionary("synonym of 怎麼／怎么."), "synonym of 怎么.")

    def test_pair_opencc_disagrees_kept(self):
        self.assertEqual(T.wiktionary("radical 糹／纟."), "radical 纟.")  # OpenCC agrees: collapsed
        self.assertEqual(T.wiktionary("used in 髼鬆／髼鬙"), "used in 髼鬆／髼鬙")

    def test_chain_and_saying(self):
        self.assertEqual(T.wiktionary("synonym of 煙袋鍋 ／菸袋鍋 ／烟袋锅 (yāndàiguō)"), "synonym of 烟袋锅 (yāndàiguō)")
        self.assertEqual(T.wiktionary("synonym of 寧為雞口，無為牛後 ／宁为鸡口，无为牛后 (níng wéi)"),
                         "synonym of 宁为鸡口，无为牛后 (níng wéi)")
        self.assertEqual(T.wiktionary("鸡，鴨／鸭"), "鸡，鸭")

    def test_pair_outside_bmp(self):
        self.assertEqual(T.wiktionary("used in 顗／𫖮"), "used in 顗")

    def test_prose_converted(self):
        self.assertEqual(T.wiktionary("variant of 伊斯蘭曆"), "variant of 伊斯兰历")
        self.assertEqual(T.wiktionary("(～屬) Leucania"), "(～属) Leucania")

    def test_relation_character_kept(self):
        self.assertEqual(T.wiktionary("graphic variant of 擴"), "graphic variant of 擴")
        self.assertEqual(T.wiktionary("a fish/(same as 鰭) fin"), "a fish/(same as 鰭) fin")
        # a word after "variant of" is prose
        self.assertEqual(T.wiktionary("variant of 雞皮疙瘩"), "variant of 鸡皮疙瘩")


if __name__ == "__main__":
    unittest.main()
