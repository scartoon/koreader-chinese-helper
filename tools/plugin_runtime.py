"""Run the plugin's own Lua code (ch_readings.lua, ch_resolve.lua) from Python,
with the reading tables from the build's TSV files (build/data/ and data/).

Fallback dictionaries' words (Plugin(fallback=("wikt", "moe"))) come from
the plugin database's fallback table and build/chinesehelper-moe.sqlite, one
source per word, as main.lua's fallbackLookup gives them to the resolver.

Also runs a koreader-interlinear-pinyin 0.5.0 copy (pinyin_data.lua,
pinyin_resolve.lua, with its own data/ folder), for before/after comparisons:
    Plugin("path/to/interlinearpinyin.koplugin")
"""
import os
import sqlite3

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some lupa wheels (macOS arm64) have no LuaJIT; it implements Lua 5.1
    from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PLUGIN = os.path.join(ROOT, "chinesehelper.koplugin")
BUILD_DATA = os.path.join(ROOT, "build", "data")
DATA_DIR = os.path.join(ROOT, "data")
FALLBACK_DBS = {
    "wikt": os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite"),
    "moe": os.path.join(ROOT, "build", "chinesehelper-moe.sqlite"),
}

HELPERS = r'''
local Resolve = ...
local function is_item(ch)
    -- Han characters are items; punctuation and anything else breaks a word,
    -- as in the rendering engine.
    return Resolve.single_char(ch) and not ch:match("^\227\128") and not ch:match("^\239\188")
end
local function items_of(text, target)
    local items, joined, pos, target_index = {}, false, 0, nil
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if pos == target and is_item(ch) then target_index = #items + 1 end
        if is_item(ch) then
            items[#items + 1] = { text = ch, joined = joined, on_page = true, pos = pos }
            joined = true
        else
            joined = false
        end
        pos = pos + 1
    end
    return items, target_index
end
local H = {}
-- Full resolution: reading the plugin would show (may be "a/b"), or nil.
-- Only characters with a rank (annotatable at some threshold) count, as
-- before special words existed: a special reading of a common character has
-- no rank and is left out here (see H.special).
function H.reading(data, text, target, mode, special)
    local items, i = items_of(text, target)
    if not i then return nil end
    if Resolve.reading then
        -- reading and rank only (0.4.0 adds a third value, the matched word)
        local reading, rank = Resolve.reading(data, items, i, mode, special)
        if not rank then return nil end
        return reading, rank
    end
    -- plugin versions before Resolve.reading existed
    local rank, default = data:char(items[i].text)
    if not rank then return nil end
    return Resolve.word_reading(data, items, i) or default, rank
end
-- The pieces: word reading and word, joined neighbours, default, rank.
function H.analyze(data, text, target)
    local items, i = items_of(text, target)
    if not i then return nil end
    local rank, default = data:char(items[i].text)
    if not rank then return nil end
    local word_reading, word = Resolve.word_reading(data, items, i)
    local left = items[i].joined and items[i - 1] and items[i - 1].text or false
    local right = items[i + 1] and items[i + 1].joined and items[i + 1].text or false
    return { word_reading = word_reading or false, word = word or false, left = left,
             right = right, default = default, rank = rank }
end
-- "char=reading ..." for what would be drawn ("char=reading*" for an
-- unusual reading from a special word when mark_special is set).
function H.annotate(data, text, threshold, mode, special, mark_special)
    local items = items_of(text, -1)
    local out = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold, mode, special)) do
        out[#out + 1] = items[a.index].text .. "=" .. a.reading .. ((mark_special and a.special) and "*" or "")
    end
    return table.concat(out, " ")
end
-- Every annotation as { pos (0-based character index in text), char, reading,
-- special (bool), word (the word that decided it, or false) }.
function H.details(data, text, threshold, mode, special)
    local items = items_of(text, -1)
    local out = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold, mode, special)) do
        out[#out + 1] = { items[a.index].pos, items[a.index].text, a.reading, a.special or false,
                          a.match and a.match.word or false }
    end
    return out
end
-- The special word covering the character at `target`: word, reading, marked.
function H.special(special, text, target)
    if not special or not Resolve.special_at then return nil end
    local items, i = items_of(text, target)
    if not i then return nil end
    local sp = Resolve.special_at(special, items, i)
    if not sp then return nil end
    return sp.entry.word, sp.entry.syllables[sp.pos], sp.entry.marks[sp.pos] or false
end
return H
'''


class Plugin:
    def __init__(self, plugin_dir=DEFAULT_PLUGIN, data_dir=None, special=True, fallback=()):
        """special: load data/special.tsv (the "unusual readings" setting, on
        by default in the plugin) when this copy of the plugin has it.
        fallback: the fallback dictionaries to let decide readings, in
        priority order ("wikt", "moe"), when this copy supports them."""
        plugin_dir = os.path.abspath(plugin_dir)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f'package.path = "{plugin_dir}/?.lua;" .. package.path')
        self.special = None
        if os.path.exists(os.path.join(plugin_dir, "ch_readings.lua")):
            Readings = self.lua.require("ch_readings")
            build = data_dir or BUILD_DATA
            tables = self.lua.table_from({
                "chars": os.path.join(build, "chars.tsv"), "words": os.path.join(build, "words.tsv"),
                "rules": os.path.join(DATA_DIR, "rules.tsv"), "uncertain": os.path.join(DATA_DIR, "uncertain.tsv")})
            self.data = Readings.fromTsv(tables)
            if isinstance(self.data, tuple) or self.data is None:
                raise SystemExit(f"cannot load {build}/chars.tsv: run tools/build_data.py first")
            if special:
                self.special = Readings.specialFromTsv(self.lua.table_from({
                    "special": os.path.join(build, "special.tsv"),
                    "guard": os.path.join(build, "special_guard.tsv")}))
            resolve = "ch_resolve"
        else:  # koreader-interlinear-pinyin 0.5.0
            data_mod = self.lua.require("pinyin_data")
            data_dir = data_dir or os.path.join(plugin_dir, "data")
            self.data = data_mod.load(data_dir)
            if special and data_mod.loadSpecial:
                self.special = data_mod.loadSpecial(data_dir)
            resolve = "pinyin_resolve"
        if isinstance(self.special, tuple):  # nil, err
            self.special = None
        self.h = self.lua.execute(HELPERS, self.lua.require(resolve))
        self.fallback = tuple(fallback or ())
        if self.fallback:
            if self.lua.eval("function(d) return d.setFallback end")(self.data) is None:
                raise SystemExit(f"{plugin_dir} cannot use fallback dictionaries")
            conns = []
            for src in self.fallback:
                if not os.path.exists(FALLBACK_DBS[src]):
                    raise SystemExit(f"missing {FALLBACK_DBS[src]} for fallback source {src}")
                conns.append((src, sqlite3.connect(f"file:{FALLBACK_DBS[src]}?mode=ro", uri=True)))
            lua = self.lua

            def lookup(words):
                remaining = list(words.values())
                out = []
                for src, conn in conns:
                    if not remaining:
                        break
                    marks = ",".join("?" * len(remaining))
                    got = conn.execute(f"SELECT simp, trad, pinyin FROM fallback WHERE (simp IN ({marks}) "
                                       f"OR trad IN ({marks})) AND source = ? ORDER BY rowid",
                                       remaining + remaining + [src]).fetchall()
                    taken = set()
                    for simp, trad, pinyin in got:
                        taken.update((simp, trad))
                        out.append(lua.table_from({"simp": simp, "trad": trad, "pinyin": pinyin, "source": src}))
                    remaining = [w for w in remaining if w not in taken]
                return lua.table_from(out)
            self.lua.eval("function(d, f, k) d:setFallback(f, k) end")(self.data, lookup, ",".join(self.fallback))

    def reading(self, text, pos, mode="both"):
        """(reading, rank) the plugin gives the character at pos, or None."""
        r = self.h.reading(self.data, text, pos, mode, self.special)
        if r is None or (isinstance(r, tuple) and r[0] is None):
            return None
        return r if isinstance(r, tuple) else (r, None)

    def analyze(self, text, pos):
        a = self.h.analyze(self.data, text, pos)
        return None if a is None else {k: (v if v is not False else None) for k, v in a.items()}

    def annotate(self, text, threshold, mode="both", mark_special=False):
        return self.h.annotate(self.data, text, threshold, mode, self.special, mark_special)

    def details(self, text, threshold, mode="both"):
        """[(pos, char, reading, special, word or None)] for what would be drawn."""
        out = []
        for row in self.h.details(self.data, text, threshold, mode, self.special).values():
            pos, ch, reading, special, word = (row[k] for k in range(1, 6))
            out.append((int(pos), ch, reading, bool(special), word or None))
        return out

    def special_at(self, text, pos):
        """(word, reading, marked) of the special word covering pos, or None."""
        r = self.h.special(self.special, text, pos)
        if r is None or (isinstance(r, tuple) and r[0] is None):
            return None
        return r
