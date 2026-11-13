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
        丁匠     moe                    -> MOE
        红夷大炮 wp, moegirl            -> Wikipedia (before Moegirlpedia)
        问题不大 moegirl                -> Moegirlpedia
        东西     CC-CEDICT, moegirl     -> CC-CEDICT only (a stray row in a
                                           user file never shows)"""
    import fallback_sources
    folder = os.path.join(data_dir, "data", "chinesehelper")
    os.makedirs(folder, exist_ok=True)
    files = {
        "moe": ([
            ("尚书省", "尚書省", "shàng shū shěng", "", "官署名。", "moe"),     # Wiktionary has it too
            ("丁匠", "丁匠", "dīng jiàng", "", "官府的工匠。", "moe"),           # MOE only
            ("典史", "典史", "diǎn shǐ", "", "官名。", "moe"),                  # CBDB has it too
        ], {"fallback_sources": "moe", "moe_rows": "3", "moe_commit_date": "2026-07-11T09:55:26Z",
            "moe_text": "simplified"}),
        "cbdb": ([
            ("尚书省", "尚書省", "shang shu sheng", "", "Department of State Affairs (Ming office title)", "cbdb"),
            ("典史", "典史", "dian shi", "", "Clerk／District Jailor (Ming office title)", "cbdb"),
            ("试百户", "試百戶", "shi bai hu", "", "office title (Ming)", "cbdb"),
        ], {"fallback_sources": "cbdb", "cbdb_rows": "3", "cbdb_date": "2026-11-07T19:14:55Z"}),
        "moegirl": ([
            ("红夷大炮", "紅夷大炮", "hóng yí dà pào", "", "不是网络用语。", "moegirl"),
            ("问题不大", "問題不大", "wèn tí bù dà", "", "问题不大是一句网络流行语，现在十分常用。", "moegirl"),
            ("东西", "東西", "dōng xī", "", "不该出现。", "moegirl"),
        ], {"fallback_sources": "moegirl", "moegirl_rows": "3", "moegirl_snapshot": "2023-05-07"}),
    }
    for source, (rows, meta) in files.items():
        path = os.path.join(folder, f"chinesehelper-{source}.sqlite")
        if os.path.exists(path):
            os.remove(path)
        fallback_sources.write_local_file(path, rows, meta, source)
    return data_dir


def main():
    print(f"Running tests under {RUNTIME}")
    test_data = make_test_files(os.path.join(ROOT, "build", "test-koreader"))
    if not os.path.exists(DB_PATH):
        sys.exit(f"missing {DB_PATH}: build it first with tools/build_db.py")
    import build_db  # the SQL the build checks, compared in test_db.lua

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
        g.PY_FALLBACK_SQL = build_db.fallback_sources.fallback_sql
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
