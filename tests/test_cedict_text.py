"""CC-CEDICT's cross-references (tools/build_db.py clean_sense): as CC-CEDICT
writes them for the popup's default text, simplified for Dictionary text:
Simplified (#48); and the measure words read from either (fallback_sources).

    python3 -m unittest tests/test_cedict_text.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import build_db  # noqa: E402
import fallback_sources as fs  # noqa: E402


class CleanSense(unittest.TestCase):
    CASES = [
        ("variant of 夠|够[gou4]", "variant of 夠|够 gòu", "variant of 够 gòu"),
        ("CL:個|个[ge4],隻|只[zhi1]", "CL: 個|个 gè, 隻|只 zhī", "CL: 个 gè, 只 zhī"),
        ("branch of Xianbei 鮮卑|鲜卑", "branch of Xianbei 鮮卑|鲜卑", "branch of Xianbei 鲜卑"),
        ("Taiwan pr. [jue2]", "Taiwan pr. jué", "Taiwan pr. jué"),
        ("see 東西[dong1 xi5]", None, None),
        ("used in 95後|95后[jiu3 wu3 hou4]", "used in 95後|95后 jiǔwǔhòu", "used in 95后 jiǔwǔhòu"),
    ]

    def test_both_texts(self):
        for raw, original, simplified in self.CASES:
            if original is None:
                self.assertEqual(build_db.clean_sense(raw, simplified=False), build_db.clean_sense(raw), raw)
                continue
            self.assertEqual(build_db.clean_sense(raw, simplified=False), original, raw)
            self.assertEqual(build_db.clean_sense(raw), simplified, raw)

    def test_measure_words_from_either(self):
        self.assertEqual(fs.measure_words("CL: 個|个 gè, 隻|只 zhī/thing"), {"个", "只"})
        self.assertEqual(fs.measure_words("CL: 个 gè, 件 jiàn"), {"个", "件"})


if __name__ == "__main__":
    unittest.main()
