"""Neutral-tone overrides (tools/pinyin_util.neutral_override, #60/#64).

    python3 -m unittest tests/test_neutral_override.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import pinyin_util as P  # noqa: E402


class NeutralOverride(unittest.TestCase):
    TABLE = {"下面": ["xia4", "mian5"], "喷嚏": ["pen1", "ti5"]}

    def test_applied(self):
        self.assertEqual(P.neutral_override("下面", "xia4 mian4", self.TABLE, trad="下面"), "xia4 mian5")
        self.assertEqual(P.neutral_override("喷嚏", "pen1 ti4", self.TABLE, trad="噴嚏"), "pen1 ti5")

    def test_other_word_with_same_simplified_form(self):
        # 下麵 xià miàn "to boil noodles" keeps its full tone.
        self.assertEqual(P.neutral_override("下面", "xia4 mian4", self.TABLE, trad="下麵"), "xia4 mian4")


if __name__ == "__main__":
    unittest.main()
