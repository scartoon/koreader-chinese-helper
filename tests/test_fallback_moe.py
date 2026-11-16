"""MOE's covered rows (tools/fallback_sources.py, moe_rows' covered option and
write_local_file): headwords CC-CEDICT has are kept, flagged covered = 1,
without changing anything else in the file; the release database's table
keeps its schema.

    python3 -m unittest tests/test_fallback_moe.py
"""
import collections
import json
import lzma
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import fallback_sources as fs  # noqa: E402


def het(pinyin, *defs):
    return {"pinyin": pinyin, "definitions": [{"def": d} for d in defs]}


ENTRIES = [
    {"title": "丁匠", "heteronyms": [het("dīng jiàng", "官府的工匠。")]},              # MOE only
    {"title": "和", "heteronyms": [het("hé", "平靜。", "連帶。"), het("hàn", "連詞。")]},  # CC-CEDICT has it
    {"title": "涓", "heteronyms": [het("juān", "細小的流水。")]},                     # CC-CEDICT has it
    {"title": "颱風", "heteronyms": [het("tái fēng", "熱帶氣旋。")]},                   # traditional form in CC-CEDICT
    {"title": "這東西", "heteronyms": [het("zhè dōng xī", "指物。")]},               # everyday, uncovered
    {"title": "很好", "heteronyms": [het("hěn hǎo", "非常好。")]},                   # everyday, covered
]
CEDICT = {"和", "涓", "台风", "颱風", "东西", "東西", "好", "很好", "很"}


class CoveredRows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.src = os.path.join(cls.tmp.name, "dict-revised.json.xz")
        with lzma.open(cls.src, "wt", encoding="utf-8") as f:
            json.dump(ENTRIES, f, ensure_ascii=False)
        cls.stats_plain, cls.stats_kept = collections.Counter(), collections.Counter()
        cls.plain = fs.moe_rows(cls.src, CEDICT, set(), cls.stats_plain)
        cls.covered = []
        cls.kept = fs.moe_rows(cls.src, CEDICT, set(), cls.stats_kept, covered=cls.covered)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_uncovered_rows_unchanged(self):
        self.assertEqual(self.kept, self.plain)
        self.assertEqual([r[0] for r in self.plain], ["丁匠"])

    def test_covered_rows(self):
        self.assertEqual(sorted((r[0], r[1], r[2], r[4]) for r in self.covered), [
            ("台风", "颱風", "tái fēng", "热带气旋。"),
            ("和", "和", "hàn", "连词。"),
            ("和", "和", "hé", "平静。/连带。"),
            ("涓", "涓", "juān", "细小的流水。"),
        ])
        self.assertTrue(all(r[5] == "moe" and r[3] == "" for r in self.covered))

    def test_everyday_filter_applies_to_covered_rows(self):
        self.assertNotIn("很好", [r[0] for r in self.covered])
        self.assertEqual(self.stats_kept["moe covered: everyday combinations (dropped): degree adverb + word"], 1)
        self.assertEqual(self.stats_kept["moe: everyday combinations (dropped): demonstrative + word"],
                         self.stats_plain["moe: everyday combinations (dropped): demonstrative + word"])

    def _write(self, name, covered):
        path = os.path.join(self.tmp.name, name)
        fs.write_local_file(path, self.plain, {"fallback_sources": "moe"}, "MOE", covered=covered)
        return sqlite3.connect(path)

    def test_file(self):
        with_cov, without = self._write("with.sqlite", self.covered), self._write("without.sqlite", ())
        self.assertTrue(fs.has_covered(with_cov))
        rows = with_cov.execute("SELECT simp, covered FROM fallback ORDER BY rowid").fetchall()
        self.assertEqual(sum(c for _, c in rows), 4)
        self.assertEqual({s for s, c in rows if c == 0}, {"丁匠"})
        cols = "simp, trad, pinyin, syllables, defs, source"
        self.assertEqual(with_cov.execute(f"SELECT {cols} FROM fallback WHERE covered = 0 ORDER BY rowid").fetchall(),
                         without.execute(f"SELECT {cols} FROM fallback ORDER BY rowid").fetchall())
        # The plugin's query leaves covered rows out, whichever form matches.
        words = ["丁匠", "和", "涓", "台风", "颱風", "台風"]
        got = with_cov.execute(fs.fallback_sql(len(words), uncovered=True), words + words).fetchall()
        self.assertEqual([r[0] for r in got], ["丁匠"])
        with_cov.close()
        without.close()

    def test_release_table_unchanged(self):
        con = sqlite3.connect(":memory:")
        fs.write_fallback(con, self.plain)
        self.assertEqual([r[1] for r in con.execute("PRAGMA table_info(fallback)")],
                         ["simp", "trad", "pinyin", "syllables", "defs", "source"])
        self.assertFalse(fs.has_covered(con))
        self.assertEqual(fs.uncovered_rows(con), "1")


if __name__ == "__main__":
    unittest.main()
