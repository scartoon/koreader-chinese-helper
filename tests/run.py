#!/usr/bin/env python3
"""Run the offline Lua tests under LuaJIT (the Lua KOReader uses).

    pip install lupa
    python3 tools/build_db.py ...      # first: the database the data tests use
    python3 tests/run.py               # all tests
    python3 tests/run.py test_text     # some of them

The plugin's database code (ch_db.lua) runs unchanged: in place of KOReader's
SQLite binding it gets a small stand-in backed by Python's sqlite3
(tests/sq3_shim.lua), so the real SQL runs against the real database.
"""
import os
import sqlite3
import sys

try:
    from lupa.luajit21 import LuaRuntime
    RUNTIME = "LuaJIT 2.1"
except ImportError:
    # Some lupa wheels (e.g. macOS arm64) ship without LuaJIT. LuaJIT
    # implements Lua 5.1, so that is the closest stand-in.
    from lupa.lua51 import LuaRuntime
    RUNTIME = "Lua 5.1 (LuaJIT not available in this lupa build)"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "chinesehelper.koplugin")
DB_PATH = os.path.join(PLUGIN, "data", "chinesehelper.sqlite")
sys.path.insert(0, os.path.join(ROOT, "tools"))

TESTS = [
    "test_text.lua", "test_context.lua", "test_pinyin.lua", "test_settings.lua",
    "test_layout.lua", "test_hit.lua", "test_popup_model.lua", "test_edge.lua",
    "test_db.lua", "test_resolve.lua", "test_special.lua", "test_page.lua",
    "test_integration.lua", "test_menu.lua", "test_sentence.lua", "test_translate.lua", "test_components.lua",
    "test_snippet.lua", "test_popup_sentence.lua", "test_glyphs.lua", "test_stack.lua", "test_area.lua", "test_bookfont.lua", "test_always.lua", "test_marks.lua", "test_sandhi.lua", "test_ranks.lua", "test_moe.lua", "test_cbdb.lua",
]


class SQLiteBridge:
    """What tests/sq3_shim.lua calls: connections and statements by id."""

    def __init__(self, lua):
        self.lua = lua
        self.conns, self.stmts, self.next_id = {}, {}, 1

    def _id(self):
        self.next_id += 1
        return self.next_id

    def open(self, path):
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        cid = self._id()
        self.conns[cid] = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        return cid

    def close(self, cid):
        conn = self.conns.pop(cid, None)
        if conn:
            conn.close()

    def prepare(self, cid, sql):
        sid = self._id()
        self.stmts[sid] = {"conn": cid, "sql": sql, "args": [], "cursor": None}
        return sid

    def bind(self, sid, args):
        self.stmts[sid]["args"] = [args[i] for i in range(1, len(args) + 1)]

    def reset(self, sid):
        self.stmts[sid]["cursor"] = None

    def clearbind(self, sid):
        self.stmts[sid]["args"] = []

    def step(self, sid):
        st = self.stmts[sid]
        if st["cursor"] is None:
            st["cursor"] = self.conns[st["conn"]].execute(st["sql"], st["args"])
        row = st["cursor"].fetchone()
        if row is None:
            return None
        return self.lua.table_from(list(row))


def make_test_files(data_dir):
    """Tiny files in the format of the user's own files (tools/build_moe.py,
    build_cbdb.py, build_moegirl.py), written the way those scripts write
    them, for the tests: <data_dir>/data/chinesehelper/chinesehelper-*.sqlite.

    Which source has which word (the plugin database has Wiktionary's 尚书省
    and Wikipedia's 红夷大炮; CC-CEDICT has 东西):
        尚书省   wikt, cbdb, moe        -> Wiktionary
        典史     cbdb, moe              -> CBDB (before MOE)
        试百户   cbdb                   -> CBDB
        王安石, 曾国藩  CC-CEDICT; cbdb covered rows (people)
        隋书     cbdb_books only (shown for 《隋书》)
        丁匠     moe                    -> MOE
        红夷大炮 wp, moegirl            -> Wikipedia (before Moegirlpedia)
        问题不大 moegirl                -> Moegirlpedia
        东西     CC-CEDICT, moegirl     -> CC-CEDICT only (a stray row in a
                                           user file never shows)
    Idioms (fallback rows, and the idioms table's short line and view):
        玉石俱碎 idioms, xinhua         -> the 成語典 (before Xinhua)
        精兵强将 xinhua                 -> Xinhua
        一毛不拔 CC-CEDICT; idioms and xinhua short line and view -> 成語典's
        首鼠两端 CC-CEDICT; xinhua short line and view only"""
    import chengyu
    import fallback_sources
    folder = os.path.join(data_dir, "data", "chinesehelper")
    os.makedirs(folder, exist_ok=True)
    files = {
        "cbdb": ([
            ("尚书省", "尚書省", "shang shu sheng", "", "Department of State Affairs (Ming office title)", "cbdb"),
            ("典史", "典史", "dian shi", "", "Clerk／District Jailor (Ming office title)", "cbdb"),
            ("试百户", "試百戶", "shi bai hu", "", "office title (Ming)", "cbdb"),
        ], {"fallback_sources": "cbdb", "cbdb_rows": "5", "cbdb_people": "2", "cbdb_offices": "3",
            "cbdb_books": "1", "cbdb_date": "2026-11-07T19:14:55Z"}),
        "moegirl": ([
            ("红夷大炮", "紅夷大炮", "hóng yí dà pào", "", "不是网络用语。", "moegirl"),
            ("问题不大", "問題不大", "wèn tí bù dà", "", "问题不大是一句网络流行语，现在十分常用。", "moegirl"),
            ("东西", "東西", "dōng xī", "", "不该出现。", "moegirl"),
        ], {"fallback_sources": "moegirl", "moegirl_rows": "3", "moegirl_snapshot": "2023-05-07"}),
        "xinhua": ([
            ("玉石俱碎", "玉石俱碎", "yù shí jù suì", "", "犹玉石俱焚。", "xinhua"),
            ("精兵强将", "精兵強將", "jīng bīng qiáng jiàng", "", "精良的士兵，勇猛的将领。", "xinhua"),
        ], {"fallback_sources": "xinhua", "xinhua_rows": "4", "xinhua_fallback_rows": "2",
            "xinhua_commit_date": "2018-12-16T05:00:00Z"}),
    }
    idioms = {
        "xinhua": [("玉石俱碎", "玉石俱碎", "犹玉石俱焚。", ""),
                   ("精兵强将", "精兵強將", "精良的士兵，勇猛的将领。", "释义\n精良的士兵。\n\n出处\n《水浒传》"),
                   ("一毛不拔", "一毛不拔", "一根汗毛也不肯拔。", "释义\n一根汗毛也不肯拔。"),
                   ("首鼠两端", "首鼠兩端", "首鼠：鼠性多疑；两端：拿不定主意。", "释义\n首鼠：鼠性多疑。\n\n出处\n《史记》")],
    }
    # CBDB (tools/build_cbdb.py): people for words CC-CEDICT has are covered
    # rows (shown only Always), book titles in their own table.
    import build_cbdb
    from simplify import Simplifier
    cbdb_covered = [
        ("王安石", "王安石", "Wáng Ānshí", "", "Song · 1021–1086 · 字 介甫 · 號 半山老人 · 臨川 · 進士 1042", "cbdb"),
        ("曾国藩", "曾國藩", "Zēng Guófān", "", "Qing · 1811–1872 · 字 伯涵 · 湘鄉 · 進士 1838", "cbdb"),
    ]
    cbdb_books = [("隋书", "隋書", "Suí Shū", "book title")]
    for source, (rows, meta) in files.items():
        path = os.path.join(folder, f"chinesehelper-{source}.sqlite")
        if os.path.exists(path):
            os.remove(path)
        extra = (lambda con, r=idioms[source]: chengyu.write_idioms(con, r)) if source in idioms else None
        if source == "cbdb":
            fallback_sources.write_local_file(path, rows, meta, source,
                                              extra=build_cbdb.write_books(cbdb_books, Simplifier("t2s")),
                                              covered=cbdb_covered)
            continue
        fallback_sources.write_local_file(path, rows, meta, source, extra=extra)
    # MOE's files as users built them before 2.28.0 (now ignored): none here.
    for old in ("chinesehelper-moe.sqlite", "chinesehelper-idioms.sqlite"):
        if os.path.exists(os.path.join(folder, old)):
            os.remove(os.path.join(folder, old))
    if os.path.exists(os.path.join(data_dir, "moe-old.sqlite")):
        os.remove(os.path.join(data_dir, "moe-old.sqlite"))
    make_test_moe(os.path.join(data_dir, "moe", "moe.sqlite"))
    return data_dir


REVISED_HEADER = ["字詞名", "辭條別名", "字數", "字詞號", "部首字", "總筆畫數", "部首外筆畫數", "多音排序", "注音一式",
                  "變體類型 1:變 2:又音 3:語音 4:讀音 5:或讀", "變體注音", "漢語拼音", "變體漢語拼音", "相似詞",
                  "相反詞", "釋義", "多音參見訊息", "異體字"]
IDIOMS_HEADER = ["編號", "成語", "注音", "漢語拼音", "釋義", "典源文獻名稱", "典源文獻內容", "典源注解", "典源參考資料",
                 "典故說明", "書證", "用法說明-語義說明", "用法說明-使用類別", "用法說明-例句", "辨識-形音辨誤", "辨識-同",
                 "辨識-異", "辨識-例句", "近義成語", "反義成語", "參考詞語", "主條成語／非主條成語"]


def make_test_moe(path):
    """A tiny file in the format of the bundled MOE data (tools/build_moe.py),
    written by the build's own functions from sheet rows shaped like MOE's.

    重編國語辭典 (CC-CEDICT has 和, 涓 and 颶風: keys with covered = 1):
        尚書省  Wiktionary has it too        丁匠  MOE only
        典史    CBDB has it too              和    two readings, hé and hàn
        涓      one reading                  颶風  a word
        很大    an everyday combination (no key)
        &98ab._104_0.gif;佬族  a headword with MOE's image code (no key)
        𤆬     a private-use character in its text (drawn as □)
    成語典: 一毛不拔 and 玉石俱焚 main entries (CC-CEDICT has 一毛不拔), 玉石俱碎
    a related entry that only says which idiom it equals."""
    import opencc
    import build_moe
    import fallback_sources
    if os.path.exists(path):
        os.remove(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    def sheet(header, records):
        return [(k + 2, [rec.get(h) for h in header]) for k, rec in enumerate(records)]
    revised = sheet(REVISED_HEADER, [
        {"字詞名": "尚書省", "字數": "3", "漢語拼音": "shàng shū shěng", "釋義": "官署名。"},
        {"字詞名": "丁匠", "字數": "2", "漢語拼音": "dīng jiàng", "釋義": "官府徵調的工匠。"},
        {"字詞名": "典史", "字數": "2", "漢語拼音": "diǎn shǐ", "釋義": "官名。"},
        {"字詞名": "和", "字數": "1", "多音排序": "1", "漢語拼音": "hé", "釋義": "[動]\r\n1.連帶。\r\n2.平靜。"},
        {"字詞名": "和", "字數": "1", "多音排序": "2", "漢語拼音": "hàn ", "釋義": "[連]\n連詞。"},
        {"字詞名": "涓", "字數": "1", "漢語拼音": "juān", "釋義": "細小的流水。"},
        {"字詞名": "颶風", "字數": "2", "漢語拼音": "jù fēng", "釋義": "熱帶氣旋。/風暴。"},
        {"字詞名": "很大", "字數": "2", "漢語拼音": "hěn dà", "釋義": "非常大。"},
        {"字詞名": "&98ab._104_0.gif;佬族", "字數": "3", "漢語拼音": "gē lǎo zú", "釋義": "民族名。"},
        {"字詞名": "𤆬", "字數": "1", "漢語拼音": "chuā", "釋義": "火聲。見\U000fa7d1字。"},
    ])
    idioms = sheet(IDIOMS_HEADER, [
        {"編號": "1", "成語": "一毛不拔", "漢語拼音": "yī máo bù bá （變） yì máo bù bá",
         "釋義": "一根毫毛也不願意拔取。\r\n△「愛財如命」", "典源文獻名稱": "《孟子．盡心上》",
         "典源文獻內容": "孟子曰：「\r\n*1*楊子\r\n取為我，拔一毛而利天下，不為也。」", "典源注解": "楊子：楊朱。",
         "用法說明-語義說明": "形容人非常吝嗇。貶義。", "近義成語": "愛財如命", "主條成語／非主條成語": "主條成語"},
        {"編號": "2", "成語": "玉石俱焚", "漢語拼音": "yù shí jù fén", "釋義": "美玉和石頭一起焚毀。",
         "用法說明-語義說明": "比喻好壞同時受害。", "主條成語／非主條成語": "主條成語"},
        {"編號": "3", "成語": "玉石俱碎", "漢語拼音": "yù shí jù suì", "釋義": "猶「玉石俱焚」。見「玉石俱焚」條。",
         "書證": "01.《晉書》：「玉石俱碎。」", "主條成語／非主條成語": "非主條成語"},
    ])
    tw2s = opencc.OpenCC("tw2s")
    cedict, measure = fallback_sources.cedict_forms(DB_PATH)
    from collections import Counter
    stats = Counter()
    con = sqlite3.connect(path)
    con.executescript(build_moe.KEYS_SCHEMA)
    build_moe.write_moe_table(con, "revised", REVISED_HEADER, revised)
    build_moe.write_moe_table(con, "idioms", IDIOMS_HEADER, idioms)
    keys, hidden = build_moe.revised_keys(REVISED_HEADER, revised, tw2s, cedict, measure, stats)
    con.executemany("INSERT INTO revised_keys VALUES (?, ?, ?, ?)", keys)
    con.executemany("INSERT INTO revised_hidden VALUES (?, ?)", hidden)
    con.executemany("INSERT INTO idioms_keys VALUES (?, ?, ?, ?, ?, ?)",
                    build_moe.idioms_keys(IDIOMS_HEADER, idioms, tw2s, cedict, stats))
    for table in ("revised_keys", "idioms_keys"):
        con.execute(f"CREATE INDEX {table}_simp ON {table}(simp)")
        con.execute(f"CREATE INDEX {table}_trad ON {table}(trad)")
    meta = {"license_uri": build_moe.LICENSE_URI, "revised_version": "2026-09-29", "revised_records": "10",
            "idioms_version": "2026-09-29", "idioms_records": "3",
            "revised_attribution": build_moe.attribution("revised", "2026-09-29"),
            "idioms_attribution": build_moe.attribution("idioms", "2026-09-29")}
    con.executemany("INSERT INTO meta VALUES (?, ?)", sorted(meta.items()))
    con.commit()
    con.close()
    return path


def main():
    print(f"Running tests under {RUNTIME}")
    test_data = make_test_files(os.path.join(ROOT, "build", "test-koreader"))
    if not os.path.exists(DB_PATH):
        sys.exit(f"missing {DB_PATH}: build it first with tools/build_db.py")
    import build_db  # the SQL the build checks, compared in test_db.lua
    import chengyu
    import build_moe

    wanted = [n if n.endswith(".lua") else n + ".lua" for n in sys.argv[1:]] or TESTS
    failed = 0
    for name in wanted:
        lua = LuaRuntime(unpack_returned_tuples=True)
        g = lua.globals()
        g.PLUGIN_DIR = PLUGIN
        g.DB_PATH = DB_PATH
        g.BUILD_DATA = os.path.join(ROOT, "build", "data")
        g.DATA_DIR = os.path.join(ROOT, "data")
        g.PY_SQLITE = SQLiteBridge(lua)
        g.PY_ENTRIES_SQL = build_db.entries_sql
        g.PY_WORDS_SQL = build_db.words_sql
        g.PY_SEG_SQL = build_db.seg_sql
        g.PY_FALLBACK_SQL = build_db.fallback_sources.fallback_sql
        g.PY_FALLBACK_ALL_SQL = build_db.fallback_sources.fallback_all_sql
        g.PY_IDIOMS_SQL = chengyu.idioms_sql
        g.PY_MOE_REVISED_SQL = build_moe.revised_sql
        g.PY_MOE_IDIOMS_SQL = build_moe.idioms_sql
        g.TEST_MOE_PATH = os.path.join(test_data, "moe", "moe.sqlite")
        g.PY_COMPONENTS_SQL = build_db.COMPONENTS_SQL
        g.PY_NOTES_SQL = build_db.NOTES_SQL
        g.TEST_KOREADER_DIR = test_data
        g.BUILD_DIR = os.path.join(ROOT, "build")
        lua.execute(f'package.path = "{PLUGIN}/?.lua;{ROOT}/tests/?.lua;" .. package.path')
        try:
            lua.execute(open(os.path.join(ROOT, "tests", name), encoding="utf-8").read())
            print(f"ok    {name}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {name}: {e}")
    print("all tests passed" if failed == 0 else f"{failed} test file(s) failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
