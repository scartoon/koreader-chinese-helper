"""Wiktionary readings in the fallback table (tools/fallback_sources.py, #15):
only Standard Chinese pinyin, never a regional romanization. The fixture
entries copy the shapes of kaikki.org's `sounds` lists."""
import collections
import gzip
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import fallback_sources as fs  # noqa: E402


def snd(text, *tags):
    return {"zh_pron": text, "tags": list(tags)}


# 搛菜: only a Nanjing romanization (with Nanjing's tones) and Wu.
JIANCAI = {"word": "搛菜", "lang_code": "zh", "pos": "verb", "sounds": [
    snd("jiǎncāi", "Mandarin", "Nanjing", "Nanjing", "Pinyin"),
    snd("¹ci-tshe₅", "Wu", "Northern"),
    snd("jian³ cai⁴", "Mandarin", "Nanjing", "Nanjing", "Pinyin")],
    "senses": [{"glosses": ["to get food using chopstick"],
                "raw_glosses": ["(dialectal Mandarin, Northern Wu) to get food using chopstick"]}]}
# 挟菜: regional only, and 挟 is jiā or xié.
XIECAI = {"word": "挟菜", "lang_code": "zh", "pos": "verb", "sounds": [
    snd("jiácài", "Mandarin", "Pinyin"), snd("jiácài", "Mandarin", "Beijing", "dialectal", "Pinyin")],
    "senses": [{"glosses": ["to get food using chopsticks"], "raw_glosses": ["(dialectal) to get food using chopsticks"]}]}
# 媳妇子: 子 is zǐ or zi.
XIFUZI = {"word": "媳妇子", "lang_code": "zh", "pos": "noun", "sounds": [
    snd("xǐfuzi", "Mandarin", "Pinyin", "Xi'an")],
    "senses": [{"glosses": ["daughter-in-law"], "raw_glosses": ["(dialectal Mandarin, Jin) daughter-in-law"]}]}
# A Xi'an sound listed before the Standard one.
SHANGJI = {"word": "上集", "lang_code": "zh", "pos": "noun", "sounds": [
    snd("shāngjí", "Mandarin", "Pinyin", "Xi'an"),
    snd("shàngjí", "Mandarin", "Pinyin"),
    snd("shàngjí", "Mandarin", "Standard-Chinese", "Pinyin")],
    "senses": [{"glosses": ["first volume"]}]}
# Taiwan only.
TAIWAN = {"word": "跇", "lang_code": "zh", "pos": "character", "sounds": [
    snd("chì", "Mandarin", "Taiwan", "Pinyin")], "senses": [{"glosses": ["to leap over"]}]}
# Mainland before Taiwan, numbered form and sandhi form stripped.
MAINLAND = {"word": "三角尺", "lang_code": "zh", "pos": "noun", "sounds": [
    snd("sānjiǎochí (san¹ jiao³ chi²)", "Mandarin", "Standard-Chinese", "Taiwan", "Pinyin"),
    snd("sānjiǎochǐ [Phonetic: sānjiáochǐ", "Mandarin", "Standard-Chinese", "Mainland-China", "Pinyin", "phonetic"),
    snd("sānjiǎochǐ", "Mandarin", "Standard-Chinese", "Mainland-China", "Pinyin")],
    "senses": [{"glosses": ["set square"]}]}
# The summary line keeps its spelling when every detailed sound is Standard.
OK = {"word": "歐克", "lang_code": "zh", "pos": "intj", "sounds": [
    snd("ōukèi", "Mandarin", "Pinyin"), snd("OK", "Mandarin", "Standard-Chinese", "Pinyin")],
    "senses": [{"glosses": ["OK"]}]}
# No Standard marker at all: Wiktionary left the region (Harbin) untagged.
MODOUZI = {"word": "墨斗子", "lang_code": "zh", "pos": "noun", "sounds": [
    snd("mìdǒuzi", "Mandarin", "Pinyin"), snd("mìdǒuzi", "Mandarin", "Pinyin")],
    "senses": [{"glosses": ["cuttlefish"], "raw_glosses": ["(Harbin Mandarin) cuttlefish"]}]}

READINGS = {"搛": {"jiān"}, "菜": {"cài"}, "挟": {"jiā", "xié"}, "挾": {"jiā", "xié"},
            "媳": {"xí"}, "妇": {"fù"}, "婦": {"fù"}, "子": {"zǐ", "zi"}, "上": {"shàng", "shǎng"}, "集": {"jí"}}


class MandarinPinyin(unittest.TestCase):
    def test_standard_after_dialect(self):
        self.assertEqual(fs.mandarin_pinyin(SHANGJI), "shàngjí")

    def test_regional_only(self):
        for e in (JIANCAI, XIECAI, XIFUZI, MODOUZI):
            self.assertIsNone(fs.mandarin_pinyin(e), e["word"])
            self.assertTrue(fs.regional_only(e), e["word"])

    def test_taiwan_only(self):
        self.assertEqual(fs.mandarin_pinyin(TAIWAN), "chì")
        self.assertFalse(fs.regional_only(TAIWAN))

    def test_mainland_first_forms_stripped(self):
        self.assertEqual(fs.mandarin_pinyin(MAINLAND), "sānjiǎochǐ")

    def test_summary_spelling(self):
        self.assertEqual(fs.mandarin_pinyin(OK), "ōukèi")


class CharacterPinyin(unittest.TestCase):
    def test_tiers(self):
        self.assertEqual(fs.character_pinyin("搛菜", "搛菜", READINGS), "jiāncài")
        self.assertEqual(fs.character_pinyin("挟菜", "挾菜", READINGS), "")
        self.assertEqual(fs.character_pinyin("媳妇子", "媳婦子", READINGS), "", "子 zǐ / zi is ambiguous")
        self.assertEqual(fs.character_pinyin("搛菜", "搛菜", None), "")

    def test_apostrophe(self):
        self.assertEqual(fs.join_syllables(["xī", "ān"]), "xī'ān")

    def test_char_readings_from_entries(self):
        entries = [("子", "子", "zǐ", "zǐ", "x"), ("子", "子", "zi", "zi", "x"), ("儿", "兒", "r", "r", "x"),
                   ("儿", "兒", "ér", "ér", "x"), ("搛", "搛", "jiān", "jiān", "x"), ("搛菜", "搛菜", "x", "x y", "x")]
        r = fs.char_readings_from_entries(entries)
        self.assertEqual(r["子"], {"zǐ", "zi"})
        self.assertEqual(r["兒"], {"ér", "r"})
        self.assertEqual(r["搛"], {"jiān"})

    def test_split_and_mismatch(self):
        self.assertEqual(fs.split_joined("lěishì", 2), ["lěi", "shì"])
        self.assertEqual(fs.split_joined("yīdiǎnr", 3), ["yī", "diǎn", "r"])
        self.assertIsNone(fs.split_joined("ji¹ zi³", 2))
        self.assertTrue(fs.reading_mismatch("搛菜", "搛菜", "jiǎncāi", READINGS))
        self.assertFalse(fs.reading_mismatch("搛菜", "搛菜", "jiāncài", READINGS))


class Rows(unittest.TestCase):
    def rows(self, entries):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "w.jsonl.gz")
            with gzip.open(path, "wt", encoding="utf-8") as f:
                for e in entries:
                    f.write(json.dumps(e, ensure_ascii=False) + "\n")
            stats = collections.Counter()
            rows = fs.wiktionary_rows(path, set(), set(), stats, readings=READINGS)
        return {r[0]: r[2] for r in rows}, rows, stats

    def test_rows(self):
        got, rows, stats = self.rows([JIANCAI, XIECAI, XIFUZI, SHANGJI, TAIWAN])
        self.assertEqual(got, {"搛菜": "jiāncài", "挟菜": "", "媳妇子": "", "上集": "shàngjí", "跇": "chì"})
        self.assertEqual(stats["wikt: regional-only, pinyin from characters"], 1)
        self.assertEqual(stats["wikt: regional-only, no pinyin"], 2)
        jian = next(r for r in rows if r[0] == "搛菜")
        self.assertIn("(dialectal Mandarin, Northern Wu)", jian[4], "the regional qualifier stays")


if __name__ == "__main__":
    unittest.main()
