"""The cross-reference resolver (tools/cedict_xrefs.py, #61) and the build's
xref_* columns (tools/build_db.py xref_columns).

    python3 -m unittest tests/test_cedict_xrefs.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import build_db  # noqa: E402
import cedict_xrefs as cx  # noqa: E402


def E(trad, simp, py, *senses):
    return (trad, simp, py, list(senses))


class ParseXref(unittest.TestCase):
    def test_kinds(self):
        self.assertEqual(cx.parse_xref("variant of 賢慧|贤慧[xian2 hui4]"),
                         ("variant of", [("賢慧", "贤慧", "xian2 hui4")]))
        self.assertEqual(cx.parse_xref("old variant of 五[wu3]"), ("old variant of", [("五", "五", "wu3")]))
        self.assertEqual(cx.parse_xref("erhua variant of 一股腦|一股脑[yi1 gu3 nao3]")[0], "erhua variant of")
        self.assertEqual(cx.parse_xref("see 東西[dong1 xi5]")[0], "see")
        self.assertEqual(cx.parse_xref("see also 東西[dong1 xi5]")[0], "see also")
        self.assertEqual(cx.parse_xref("used in 葡萄[pu2 tao5]")[0], "used in")

    def test_not_only_a_reference(self):
        self.assertIsNone(cx.parse_xref("thing; see 東西[dong1 xi5]"))
        self.assertIsNone(cx.parse_xref("(of a wife) wise and kind"))
        self.assertIsNone(cx.parse_xref("variant of a word"))

    def test_xref_only(self):
        self.assertIsNotNone(cx.Resolver.xref_only(["variant of 五[wu3]", "CL:個|个[ge4]"]))
        self.assertIsNone(cx.Resolver.xref_only(["variant of 五[wu3]", "five"]))
        self.assertIsNone(cx.Resolver.xref_only(["CL:個|个[ge4]"]))


class Resolve(unittest.TestCase):
    def resolve(self, entries, i=0):
        status, rows = cx.Resolver(entries).target(i)
        return status, rows

    def test_simple_variant(self):
        es = [E("賢惠", "贤惠", "xian2 hui4", "variant of 賢慧|贤慧[xian2 hui4]"),
              E("賢慧", "贤慧", "xian2 hui4", "(of a wife) wise and kind")]
        self.assertEqual(self.resolve(es), ("exact", [1]))

    def test_pinyin_picks_among_readings(self):
        es = [E("佮", "佮", "ge2", "see 合[ge2]"),
              E("合", "合", "he2", "to close"),
              E("合", "合", "ge3", "100 ml"),
              E("合", "合", "ge2", "variant of 閤|阁[ge2]"),
              E("合", "合", "ge2", "(rare) a measure")]
        # 合 ge2: the row that is not only a reference.
        self.assertEqual(self.resolve(es), ("exact", [4]))
        es[0] = E("佮", "佮", "ge3", "see 合[ge3]")
        self.assertEqual(self.resolve(es), ("exact", [2]))

    def test_pinyin_differs_one_row(self):
        es = [E("吐嘈", "吐嘈", "tu4 cao2", "variant of 吐槽[tu4 cao2]"),
              E("吐槽", "吐槽", "tu3 cao2", "to complain")]
        self.assertEqual(self.resolve(es), ("only", [1]))

    def test_pinyin_differs_several_rows(self):
        es = [E("佮", "佮", "ge4", "see 合[ge4]"),
              E("合", "合", "he2", "to close"),
              E("合", "合", "ge3", "100 ml")]
        self.assertEqual(self.resolve(es), ("ambiguous", None))

    def test_chain(self):
        es = [E("利是", "利是", "li4 shi4", "variant of 利事[li4 shi4]"),
              E("利事", "利事", "li4 shi4", "see 紅包|红包[hong2 bao1]"),
              E("紅包", "红包", "hong2 bao1", "money wrapped in red")]
        self.assertEqual(self.resolve(es), ("chain", [2]))

    def test_chain_too_long(self):
        es = [E(f"字{k}", f"字{k}", "zi4", f"variant of 字{k + 1}[zi4]") for k in range(5)]
        es.append(E("字5", "字5", "zi4", "word"))
        self.assertEqual(self.resolve(es), ("too-long", None))
        self.assertEqual(self.resolve(es, 2), ("chain", [5]))

    def test_cycle(self):
        es = [E("甲", "甲", "jia3", "variant of 乙[jia3]"),
              E("乙", "乙", "jia3", "variant of 甲[jia3]")]
        self.assertEqual(self.resolve(es), ("cycle", None))

    def test_missing(self):
        es = [E("萣", "萣", "ding4", "see 茄萣[Qie2 ding4]")]
        self.assertEqual(self.resolve(es), ("missing", None))

    def test_self_row_never_its_own_target(self):
        # 㑺|俊 is "old variant of 俊": the row keyed 俊 as simplified is not
        # the target, 俊|俊 is.
        es = [E("㑺", "俊", "jun4", "old variant of 俊[jun4]"),
              E("俊", "俊", "jun4", "handsome")]
        self.assertEqual(self.resolve(es), ("exact", [1]))

    def test_unresolved_kinds(self):
        es = [E("萄", "萄", "tao2", "used in 葡萄[pu2 tao5]"),
              E("葡萄", "葡萄", "pu2 tao5", "grape")]
        self.assertEqual(self.resolve(es), ("kind", None))
        es[0] = E("萄", "萄", "tao2", "see also 葡萄[pu2 tao5]")
        self.assertEqual(self.resolve(es), ("kind", None))

    def test_several_targets(self):
        es = [E("伭", "伭", "xuan2", "variant of 玄[xuan2]", "variant of 懸|悬[xuan2]"),
              E("玄", "玄", "xuan2", "black"), E("懸", "悬", "xuan2", "to hang")]
        self.assertEqual(self.resolve(es), ("several", None))

    def test_pinyin_written_with_spaces(self):
        es = [E("呂梁", "吕梁", "Lu:3 liang2", "see 呂梁市|吕梁市[Lu : 3 liang2 Shi4]"),
              E("呂梁市", "吕梁市", "Lu:3 liang2 Shi4", "Lüliang, prefecture-level city")]
        self.assertEqual(self.resolve(es), ("exact", [1]))


class Columns(unittest.TestCase):
    def test_columns(self):
        raw = [E("賢惠", "贤惠", "xian2 hui4", "variant of 賢慧|贤慧[xian2 hui4]"),
               E("賢慧", "贤慧", "xian2 hui4", "(of a wife) wise and kind", "see also 賢人|贤人[xian2 ren2]"),
               E("賢人", "贤人", "xian2 ren2", "great person")]
        entries, originals = [], []
        for trad, simp, py, senses in raw:
            entries.append((simp, trad, build_db.joined_pinyin(py), build_db.syllable_pinyin(py),
                            "/".join(build_db.clean_sense(s) for s in senses)))
            originals.append("/".join(build_db.clean_sense(s, simplified=False) for s in senses))
        cols = build_db.xref_columns(raw, entries, originals)
        self.assertEqual(cols[0], ("贤慧", "賢慧", "xiánhuì", "(of a wife) wise and kind/see also 賢人|贤人 xiánrén",
                                   "(of a wife) wise and kind/see also 贤人 xiánrén"))
        self.assertEqual(cols[1], (None,) * 5)
        self.assertEqual(cols[2], (None,) * 5)


if __name__ == "__main__":
    unittest.main()
