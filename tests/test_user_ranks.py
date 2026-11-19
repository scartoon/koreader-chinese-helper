"""Unit tests for tools/build_user_ranks.py (#42): counting, ranking, the
fallback, traditional forms and 〇, work grouping, the exact cut-off and
--push (adb mocked). python3 -m unittest tests/test_user_ranks.py."""
import os
import sys
import tempfile
import unittest
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import build_user_ranks as U  # noqa: E402

# Bundled ranks: 的 1, 是 2, 了 3, 这 11 (這 its traditional form, same rank),
# 零 1244 (〇 too), 饕 4396, 餮 4900, 龘 0 (unranked), 乾/干 390.
RANKS = {"的": 1, "是": 2, "了": 3, "这": 11, "這": 11, "零": 1244, "〇": 1244,
         "饕": 4396, "餮": 4900, "龘": 0, "乾": 390, "干": 390, "甲": 500, "乙": 600}
PUBLIC = U.Public(RANKS, {"這": "这", "乾": "干"})


def filler(seed, n=40):
    """A distinct text of n anchor windows (no 甲乙饕餮), for copy tests."""
    import random
    rng = random.Random(seed)
    pool = "天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈"
    return "".join("的" + "".join(rng.choice(pool) for _ in range(9)) for _ in range(n))


class Mapping(unittest.TestCase):
    def test_traditional_takes_simplified_rank(self):
        counts = {"這": Counter({"这": 5}), "乾": Counter({"干": 3, "乾": 1}), "著": Counter({"着": 5})}
        ranks = dict(RANKS, 著=900, 着=100)
        t2s = U.Public.mapping(ranks, counts, simplified={"这", "干", "乾", "着", "著"})
        self.assertEqual(t2s["這"], "这")
        self.assertEqual(t2s["乾"], "干")
        self.assertNotIn("著", t2s, "著 is ranked in its own right")

    def test_unranked_traditional_only_when_never_simplified(self):
        ranks = {"龘": 0, "x": 0, "y": 0}
        counts = {"龘": Counter({"x": 1}), "y": Counter({"x": 1})}
        t2s = U.Public.mapping(ranks, counts, simplified={"x", "y"})
        self.assertEqual(t2s, {"龘": "x"})

    def test_ling(self):
        self.assertEqual(PUBLIC.key("〇"), "零")
        self.assertEqual(PUBLIC.key("這"), "这")


class Ranking(unittest.TestCase):
    def build(self, files, texts, overrides=None):
        return U.build(files, texts, PUBLIC, overrides, date="2026-11-19")

    def test_spread_first_then_occurrences_then_bundled_rank(self):
        files = [("001", "A"), ("002", "B"), ("003", "C")]
        texts = {"001": "饕" * 50 + "甲乙的", "002": "甲乙的", "003": "的是"}
        ranked, header, *_ = self.build(files, texts)
        order = [r[0] for r in ranked]
        # 的: 3 works. 甲, 乙: 2 works, 1+1 each: tie, bundled rank 甲 500 < 乙 600.
        # 饕 (1 work, 50) before 是 (1 work, 1).
        self.assertEqual(order, ["的", "甲", "乙", "饕", "是"])
        self.assertEqual(ranked[0][1:], (1, 3, 3))
        self.assertEqual(header["works"], 3)
        self.assertEqual(header["ranked"], 5)

    def test_unranked_bundled_sorts_last_in_a_tie(self):
        ranked, *_ = self.build([("001", "A")], {"001": "龘餮"})
        self.assertEqual([r[0] for r in ranked], ["餮", "龘"])

    def test_absent_characters_not_listed(self):
        ranked, *_ = self.build([("001", "A")], {"001": "的的是"})
        listed = {r[0] for r in ranked}
        self.assertEqual(listed, {"的", "是"})
        self.assertNotIn("饕", listed, "absent: falls back to the bundled rank in the plugin")

    def test_unknown_characters_not_ranked(self):
        ranked, *_ = self.build([("001", "A")], {"001": "的㐀"})
        self.assertEqual([r[0] for r in ranked], ["的"])

    def test_traditional_and_ling_count_as_simplified(self):
        ranked, *_ = self.build([("001", "A")], {"001": "這这〇零乾"})
        stats = {r[0]: r for r in ranked}
        self.assertEqual(stats["这"][3], 2)
        self.assertEqual(stats["零"][3], 2)
        self.assertEqual(stats["干"][3], 1)
        self.assertNotIn("這", stats)
        rows = U.with_forms(ranked, PUBLIC)
        by = {r[0]: r for r in rows}
        self.assertEqual(by["這"][1:], by["这"][1:], "traditional form listed with its simplified rank")
        self.assertEqual(by["〇"][1:], by["零"][1:])
        self.assertEqual(by["乾"][1:], by["干"][1:])

    def test_exact_cutoff(self):
        ranked = [(str(i), i, 3 if i <= 250 else 2, 10) for i in range(1, 400)]
        self.assertEqual(U.exact_cutoff(ranked, 40), 200, "rounded down to a hundred")
        self.assertEqual(U.exact_cutoff(ranked[:50], 40), 50, "under 100: as is")
        self.assertEqual(U.exact_cutoff([("a", 1, 1, 5), ("b", 2, 1, 1)], 1), 2, "one work: every rank")

    def test_file_round_trip(self):
        ranked, header, *_ = self.build([("001", "A")], {"001": "的是是"})
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "r.tsv")
            U.write(path, U.with_forms(ranked, PUBLIC), header)
            with open(path, encoding="utf-8") as f:
                lines = f.read().splitlines()
        self.assertIn("# date\t2026-11-19", lines)
        self.assertIn("# works\t1", lines)
        self.assertIn("# exact\t2", lines)
        self.assertIn("是\t1\t1\t2", lines)
        self.assertIn("的\t2\t1\t1", lines)


class Works(unittest.TestCase):
    def test_title_stem(self):
        self.assertEqual(U.title_stem("临高启明 第七卷 7 -- 吹牛者 -- 2022.epub"), "临高启明")
        self.assertEqual(U.title_stem("x.zip:临高启明六卷 -- 吹牛者 -- 2016.epub"), "临高启明")
        self.assertEqual(U.title_stem("明朝那些事儿（第3部） - 当年明月.epub"), None, "volume in brackets after the title")
        self.assertEqual(U.title_stem("明朝那些事儿 3 - 当年明月.epub"), "明朝那些事儿")
        self.assertEqual(U.title_stem("长安十二时辰 (马伯庸).epub"), None)
        self.assertEqual(U.title_stem("Hua Wei Wang Shi  - Liu Ping.epub"), None)

    def test_local_run_is_one_work(self):
        files = [("linggao-1", "a"), ("linggao-2", "b"), ("001", "c")]
        texts = {"linggao-1": filler(1) + "饕", "linggao-2": filler(2) + "饕", "001": filler(3)}
        ranked, header, works, *_ = U.build(files, texts, PUBLIC)
        self.assertEqual(header["works"], 2)
        self.assertEqual({r[0]: r[2] for r in ranked}["饕"], 1, "two files of one work: one vote")

    def test_volumes_are_one_work(self):
        files = [("158", "临高启明 第七卷 7 -- x.epub"), ("159", "临高启明六卷 -- x.epub"), ("160", "别的书.epub")]
        texts = {"158": filler(1) + "饕", "159": filler(2) + "饕", "160": filler(3)}
        ranked, header, *_ = U.build(files, texts, PUBLIC)
        self.assertEqual(header["works"], 2)
        stats = {r[0]: r for r in ranked}
        self.assertEqual(stats["饕"][2:], (1, 2), "one work, both volumes' occurrences")

    def test_device_and_local_copy_counts_once(self):
        book = filler(7) + "饕饕"
        files = [("158", "临高启明 第七卷 7.epub"), ("linggao-1", "z.zip:临高启明 第七卷 7.epub"), ("001", "x")]
        texts = {"158": book, "linggao-1": book, "001": filler(8)}
        ranked, header, works, copies, report = U.build(files, texts, PUBLIC)
        self.assertEqual(header["works"], 2)
        self.assertEqual({r[0]: r for r in ranked}["饕"][2:], (1, 2), "the copy is not counted twice")
        self.assertEqual(len(report["copies"]), 1)
        self.assertEqual(header["han"], len(book) + len(texts["001"]))

    def test_override(self):
        files = [("001", "a"), ("002", "b")]
        texts = {"001": filler(1) + "饕", "002": filler(2) + "饕"}
        _, header, *_ = U.build(files, texts, PUBLIC, {"001": "w", "002": "w"})
        self.assertEqual(header["works"], 1)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "works.tsv")
            with open(path, "w", encoding="utf-8") as f:
                f.write("# comment\n001\tmingchao\n\n002\tmingchao\n")
            self.assertEqual(U.read_overrides(path), {"001": "mingchao", "002": "mingchao"})


class Push(unittest.TestCase):
    def test_push_copies_without_rebuilding(self):
        calls = []
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "user-ranks.tsv")
            with open(path, "w") as f:
                f.write("# date\t2026-11-19\n的\t1\t1\t1\n")
            before = os.path.getmtime(path)
            U.push(path, run=lambda cmd, **kw: calls.append(cmd))
            self.assertEqual(os.path.getmtime(path), before, "not rebuilt")
        self.assertEqual(calls, [["adb", "push", path, U.DEVICE_PATH]])
        self.assertTrue(U.DEVICE_PATH.endswith("/koreader/settings/chinesehelper_ranks.tsv"))

    def test_push_without_file(self):
        with self.assertRaises(SystemExit):
            U.push("/nonexistent/user-ranks.tsv", run=lambda *a, **k: None)


if __name__ == "__main__":
    unittest.main()
