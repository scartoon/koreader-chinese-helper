"""The bundled MOE data is MOE's, unmodified (#86).

tools/build_moe.py's own pieces (the OOXML escapes, empty cells, the related-
idiom flag), then the built folder chinesehelper.koplugin/data/moe/ against
MOE's official downloads in build/sources/moe-official/, read with an
independent .xlsx reader (openpyxl, with only OOXML's _xHHHH_ escapes decoded): for 1,000 random records of each
dictionary and every record with a character MOE could not encode, every
field equals the official file's. Also: no MOE table has a simplified
column, the usage notes are byte for byte MOE's, and meta's SHA-256 is the
download's. The data checks are skipped when the folder, the downloads or
openpyxl are missing (CI has neither the downloads nor openpyxl)."""
import hashlib
import io
import os
import random
import re
import sqlite3
import sys
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import build_moe  # noqa: E402

OUT = os.path.join(ROOT, "chinesehelper.koplugin", "data", "moe")
DB = os.path.join(OUT, build_moe.DB_NAME)
CODED = re.compile("[-\U000f0000-\U0010ffff]|&[0-9A-Za-z._]+;")


def tiny_xlsx(rows):
    """A workbook with shared strings, a number and an empty cell."""
    shared = ['<si><t xml:space="preserve">甲_x000D_\n乙 </t></si>', "<si><t>字詞名</t></si>",
              "<si><t>字數</t></si>", "<si><t>釋義</t></si>", "<si><t>八</t></si>",
              "<si><r><t>富</t></r><r><t>文本</t></r></si>"]
    sheet = ('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
             '<row r="1"><c r="A1" t="s"><v>1</v></c><c r="B1" t="s"><v>2</v></c><c r="C1" t="s"><v>3</v></c></row>'
             '<row r="2"><c r="A2" t="s"><v>4</v></c><c r="B2"><v>1</v></c><c r="C2" t="s"><v>0</v></c></row>'
             '<row r="3"><c r="A3" t="s"><v>5</v></c><c r="C3" t="str"><f>"x"</f><v>x</v></c></row>'
             "</sheetData></worksheet>")
    sst = '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' + "".join(shared) + "</sst>"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("xl/worksheets/sheet1.xml", sheet)
        z.writestr("xl/sharedStrings.xml", sst)
    return buf.getvalue()


class Reader(unittest.TestCase):
    def test_sheet(self):
        header, body = build_moe.read_sheet(tiny_xlsx(None))
        self.assertEqual(header, ["字詞名", "字數", "釋義"])
        self.assertEqual(body, [(2, ["八", "1", "甲\r\n乙 "]), (3, ["富文本", None, "x"])])

    def test_unescape(self):
        self.assertEqual(build_moe.unescape("a_x000D_b_x005F_c"), "a\rb_c")

    def test_only_equals(self):
        self.assertTrue(build_moe.ONLY_EQUALS.match("猶「玉石俱焚」。"))
        self.assertTrue(build_moe.ONLY_EQUALS.match("㕙，兔。盧，黑色獵犬。「㕙盡盧烹」猶「兔死狗烹」。"))
        self.assertFalse(build_moe.ONLY_EQUALS.match("比喻有限的本領。"))
        self.assertEqual(build_moe.own_explanation("猶「玉石俱焚」。見「玉石俱焚」條。01.陳琳〈檄〉：「大兵一放。」"),
                         "猶「玉石俱焚」。")


def _available():
    if not os.path.exists(DB):
        return None, f"no {DB}"
    try:
        import openpyxl  # noqa: F401
    except ImportError:
        return None, "openpyxl not installed"
    con = sqlite3.connect(DB)
    meta = dict(con.execute("SELECT key, value FROM meta"))
    con.close()
    zips = {k: os.path.join(build_moe.SRC_DIR, meta[f"{k}_file"]) for k in ("revised", "idioms")}
    if not all(os.path.exists(z) for z in zips.values()):
        return None, f"MOE's downloads not in {build_moe.SRC_DIR}"
    return (meta, zips), ""


AVAILABLE, WHY = _available()


@unittest.skipUnless(AVAILABLE, WHY)
class Verbatim(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.meta, cls.zips = AVAILABLE
        cls.con = sqlite3.connect(DB)

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    def official(self, kind):
        """{sheet row: [values]} and the header, read with openpyxl."""
        import openpyxl
        name, data = build_moe.xlsx_bytes(self.zips[kind])
        # data_only: a formula cell's value as the sheet shows it (字詞號 is ="00083": 00083).
        wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
        ws = wb.worksheets[0]
        rows = {}
        header = None
        for k, vals in enumerate(ws.iter_rows(values_only=True), 1):
            if k == 1:
                header = list(vals)
                continue
            rows[k] = vals
        wb.close()
        return header, rows

    def check(self, kind):
        header, rows = self.official(kind)
        cols = [r[1] for r in self.con.execute(f"PRAGMA table_info({kind})")]
        self.assertEqual(cols, header, "MOE's columns, in MOE's order")
        self.assertFalse(any("simp" in c for c in cols))
        stored = {r[0]: r[1:] for r in self.con.execute(f"SELECT rowid, * FROM {kind}")}
        self.assertEqual(len(stored), len(rows), "every record")
        self.assertEqual(int(self.meta[f"{kind}_records"]), len(rows))
        coded = [n for n, vals in rows.items() if any(isinstance(v, str) and CODED.search(v) for v in vals)]
        rng = random.Random(86)
        sample = sorted(set(rng.sample(sorted(rows), 1000)) | set(coded))
        for n in sample:
            # The one conversion besides the format: OOXML's _xHHHH_ escapes,
            # which openpyxl leaves as written (_x000D_ is a carriage return).
            want = [None if v is None else (build_moe.unescape(v) if isinstance(v, str) else str(v))
                    for v in rows[n]]
            want += [None] * (len(header) - len(want))
            self.assertEqual(list(stored[n]), want, f"{kind} row {n}")
        return len(sample), len(coded)

    def test_revised(self):
        n, coded = self.check("revised")
        self.assertGreater(coded, 100)

    def test_idioms(self):
        n, coded = self.check("idioms")
        self.assertGreater(coded, 50)

    def test_sources_and_notes(self):
        for kind in ("revised", "idioms"):
            with open(self.zips[kind], "rb") as f:
                self.assertEqual(hashlib.sha256(f.read()).hexdigest(), self.meta[f"{kind}_sha256"])
        for name in build_moe.NOTES["revised"] + build_moe.NOTES["idioms"]:
            with open(os.path.join(OUT, name), "rb") as a, open(os.path.join(build_moe.SRC_DIR, name), "rb") as b:
                self.assertEqual(a.read(), b.read(), name)
        with open(os.path.join(OUT, "LICENSE.txt"), encoding="utf-8") as f:
            text = f.read()
        self.assertIn("https://creativecommons.org/licenses/by-nd/3.0/tw/", text)
        for kind in ("revised", "idioms"):
            self.assertIn(self.meta[f"{kind}_attribution"], text)

    def test_no_simplified_anywhere(self):
        for (table,) in self.con.execute("SELECT name FROM sqlite_master WHERE type = 'table'"):
            cols = [r[1] for r in self.con.execute(f"PRAGMA table_info({table})")]
            self.assertFalse(any(c.endswith("_simp") for c in cols), table)


if __name__ == "__main__":
    unittest.main()
