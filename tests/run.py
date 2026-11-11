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
    "test_layout.lua", "test_hit.lua", "test_popup_model.lua",
    "test_db.lua", "test_resolve.lua", "test_special.lua", "test_page.lua",
    "test_integration.lua", "test_menu.lua",
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


def main():
    print(f"Running tests under {RUNTIME}")
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
