#!/usr/bin/env python3
"""The screenshot gate: what the plugin's own Lua code draws on a page of
text, and what its popup shows for a tap, with every fallback dictionary
installed (the plugin database plus the files in --files, as on the device).

    .venv/bin/python tools/shot_gate.py --threshold 3500 --text "...页面文字..." --tap 涓
    .venv/bin/python tools/shot_gate.py --threshold 3500 --text-file page.txt --tap 茴:2

--text is the page's text exactly as it is on screen. "|" toggles between
the page and context off the page (as tests/sq3_shim.lua's H.items): text
before the first "|" is the end of the previous page, so "前页|本页|后页".
--tap X:N taps the N-th X on the page (default the first).

It prints the drawn pinyin ("char=reading" in page order) and each popup as
labelled blocks, markers included. tools/make_screenshots.py calls gate()
and compares the result with what each shot expects before saving it.

The code path is ch_tap.lua's showPopup/present, rebuilt from the same
modules (ch_resolve, ch_popup_model, ch_components, ch_db, ch_text) as
tests/test_integration.lua does, with main.lua's fallback lookup: every
source in Settings' default order, one source per word, readings decided by
the sources in main.lua's READING_SOURCES only.
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from run import DB_PATH, PLUGIN, LuaRuntime, SQLiteBridge  # noqa: E402

LUA = r'''
local SQ3 = require("sq3_shim").SQ3
local DB = require("ch_db")
local Resolve = require("ch_resolve")
local Model = require("ch_popup_model")
local Text = require("ch_text")
local Components = require("ch_components")
local Settings = require("ch_settings")

local G = {}

-- main.lua's READING_SOURCES, read from the file so the gate cannot drift.
local function reading_sources()
    local f = assert(io.open(PLUGIN_DIR .. "/main.lua"))
    local src = f:read("*a")
    f:close()
    local body = assert(src:match("ChineseHelper%.READING_SOURCES = (%b{})"))
    local out = {}
    for name in body:gmatch("([%w_]+)%s*=%s*true") do out[name] = true end
    return out
end

function G.open(files)
    local main = assert(DB.open(DB_PATH, SQ3))
    local settings = Settings.new(nil)    -- the defaults: every source on
    local sources = {}
    for _, source in ipairs(settings:fallbackOrder()) do
        if settings:fallbackEnabled(source) then
            local db
            if source == "wikt" or source == "wp" then
                db = main
            elseif files[source] then
                db = assert(DB.open(files[source], SQ3))
            end
            if db then sources[#sources + 1] = { source = source, db = db } end
        end
    end
    local function lookup(words, only)
        local remaining, out, fetched = words, {}, {}
        for _, src in ipairs(sources) do
            if #remaining == 0 then break end
            if not only or only[src.source] then
                local rows = fetched[src.db]
                if not rows then
                    rows = src.db:fallback(words)
                    fetched[src.db] = rows
                end
                local got = {}
                for _, row in ipairs(rows) do
                    if (row.source or src.source) == src.source then
                        row.source = src.source
                        got[#got + 1] = row
                    end
                end
                local kept
                kept, remaining = Model.takeFallback(remaining, got)
                for _, row in ipairs(kept) do out[#out + 1] = row end
            end
        end
        return out
    end
    local only = reading_sources()
    local names = {}
    for _, src in ipairs(sources) do if only[src.source] then names[#names + 1] = src.source end end
    local data = main:readings()
    data:setFallback(function(list) return lookup(list, only) end, table.concat(names, ","))
    local idiom_sources = { idioms = true, xinhua = true }
    local function idioms(words)
        local rows = {}
        for _, src in ipairs(sources) do
            if idiom_sources[src.source] then
                for _, row in ipairs(src.db:idioms(words)) do
                    row.source = src.source
                    rows[#rows + 1] = row
                end
            end
        end
        return Model.pickIdioms(rows, settings:fallbackOrder())
    end
    local names_all = {}
    for _, src in ipairs(sources) do names_all[#names_all + 1] = src.source end
    return { main = main, data = data, special = main:special(), lookup = lookup, idioms = idioms,
             settings = settings, sources = table.concat(names_all, ",") }
end

-- Engine-like items: tests/sq3_shim.lua's H.items, with each item's
-- character position in the text.
local function items_of(text)
    local items, joined, on_page, pos = {}, false, true, 0
    if text:find("|", 1, true) then on_page = false end
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if ch == "|" then
            on_page = not on_page
        elseif Resolve.single_char(ch) and not ch:match("^\227\128") and not ch:match("^\239\188") then
            items[#items + 1] = { text = ch, joined = joined, on_page = on_page, pos = pos }
            joined = true
        else
            joined = false
        end
        pos = pos + 1
    end
    return items
end

function G.annotate(g, text, threshold, mode)
    local items = items_of(text)
    local out = {}
    for _, a in ipairs(Resolve.annotate(g.data, items, threshold, mode, g.special)) do
        out[#out + 1] = { index = a.index, char = items[a.index].text, reading = a.reading,
                          special = a.special and true or false }
    end
    return out, items
end

-- The popup as Tap:present builds it: { blocks = { {label, head, lines, note} }, buttons = {...} }.
local function present(g, char, cands, rows, matches, annotated)
    local bodies_ok, comp = pcall(function()
        local c, via, changes = Components.resolve(char,
            function(list) return g.main:components(list) end, cands, rows)
        return c and { c = c, via = via, changes = changes }
    end)
    assert(bodies_ok, comp)
    -- Tap:attachIdioms
    local words = {}
    for _, m in ipairs(matches) do if m.len and m.len > 1 then words[#words + 1] = m.word end end
    if #words > 0 then Model.attachIdioms(matches, g.idioms(words)) end
    local blocks = Model.blocks(matches, char, annotated, "**", "**")
    local buttons = {}
    for _, m in ipairs(matches) do buttons[#buttons + 1] = m.word end
    for _, c in ipairs(Model.chuchu(matches)) do buttons[#buttons + 1] = c.text .. "(" .. c.word .. ")" end
    local block = comp and Components.block(comp.c, "**", "**", comp.via, comp.changes)
    if block then
        local first = matches[1]
        table.insert(blocks, (first and first.len == 1) and 2 or 1, block)
    end
    local label_mode = g.settings:labelMode()
    local function label(source)
        if label_mode == "none" or (label_mode == "fallback" and source == "cedict") then return false end
        return Model.SOURCE_LABELS[source] or source
    end
    local out = {}
    for _, b in ipairs(blocks) do
        out[#out + 1] = { label = label(b.source), head = b.head or false, lines = b.lines,
                          note = b.note and { label = label(b.note.source), text = b.note.text } or false }
    end
    return { blocks = out, buttons = buttons, chuchu = Model.chuchu(matches) }
end

function G.popup(g, text, threshold, mode, char, nth)
    local items = items_of(text)
    local i, seen = nil, 0
    for k, item in ipairs(items) do
        if item.text == char and item.on_page ~= false then
            seen = seen + 1
            if seen == nth then i = k break end
        end
    end
    assert(i, char .. " #" .. nth .. " not on the page")
    local left, right = {}, {}
    local k = i
    while #left < 7 and items[k].joined and items[k - 1] do
        k = k - 1
        table.insert(left, 1, items[k].text)
    end
    k = i
    while #right < 7 and items[k + 1] and items[k + 1].joined do
        k = k + 1
        right[#right + 1] = items[k].text
    end
    local drawn
    for _, a in ipairs(Resolve.annotate(g.data, items, threshold, mode, g.special)) do
        if a.index == i then drawn = a.reading end
    end
    local chosen, decided, unsure = Resolve.forPopup(g.data, items, i, mode, g.special, drawn)
    local cands, texts = Text.candidates(left, char, right)
    local rows = g.main:lookup(texts)
    for _, r in ipairs(g.lookup(Model.uncovered(texts, rows))) do rows[#rows + 1] = r end
    g.data:prefetch(texts)
    local matches = Model.matches{
        cands = cands, rows = rows, chosen = chosen, annotated = drawn ~= nil, decided = decided,
        unsure = unsure, order = g.settings:fallbackOrder(),
        default = select(2, g.data:char(char)),
        wordReading = function(w) return Resolve.wordReading(g.data, w) end,
    }
    local p = present(g, char, cands, rows, matches, drawn ~= nil)
    p.header = table.concat(left) .. "**" .. char .. "**" .. table.concat(right)
    p.drawn = drawn or false
    p.chosen = chosen or false
    p.pos = items[i].pos
    return p
end

return G
'''

FILES_DIR = os.path.join(ROOT, "build")
LOCAL_SOURCES = ("cbdb", "moe", "idioms", "xinhua", "moegirl")


def to_py(v):
    """Lua tables -> lists/dicts."""
    if hasattr(v, "items") and not isinstance(v, (str, bytes, dict)):
        d = dict(v.items())
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [to_py(d[k]) for k in sorted(d)]
        return {k: to_py(x) for k, x in d.items()} if d else []
    return v


class Gate:
    def __init__(self, files_dir=FILES_DIR):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.PLUGIN_DIR = PLUGIN
        g.DB_PATH = DB_PATH
        g.PY_SQLITE = SQLiteBridge(self.lua)
        self.lua.execute(f'package.path = "{PLUGIN}/?.lua;{ROOT}/tests/?.lua;" .. package.path')
        self.G = self.lua.execute(LUA)
        files = {}
        for s in LOCAL_SOURCES:
            path = os.path.join(files_dir, f"chinesehelper-{s}.sqlite")
            if os.path.exists(path):
                files[s] = path
        missing = [s for s in LOCAL_SOURCES if s not in files]
        if missing:
            sys.exit(f"gate: missing optional dictionaries in {files_dir}: {', '.join(missing)}")
        self.g = self.G.open(self.lua.table_from(files))
        self.sources = self.g.sources

    def annotate(self, text, threshold, mode="both"):
        """[(char, reading, special)] in page order."""
        anns, _ = self.G.annotate(self.g, text, threshold, mode)
        rows = sorted((to_py(a) for a in anns.values()), key=lambda a: a["index"])
        return [(a["char"], a["reading"], a["special"]) for a in rows]

    def popup(self, text, threshold, char, nth=1, mode="both"):
        return to_py(self.G.popup(self.g, text, threshold, mode, char, nth))


def format_popup(p):
    out = []
    if p.get("header"):
        out.append(f"header: {p['header']}")
    for b in p["blocks"]:
        if b.get("label"):
            out.append(f"  [{b['label']}]")
        if b.get("head"):
            out.append("  " + b["head"])
        out.extend("  " + line for line in b["lines"])
        if b.get("note"):
            n = b["note"]
            out.append(f"  [{n['label']}] {n['text']}" if n.get("label") else "  " + n["text"])
        out.append("")
    out.append("buttons: " + " | ".join(p["buttons"]))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--threshold", type=int, default=3500)
    ap.add_argument("--mode", default="both")
    ap.add_argument("--text")
    ap.add_argument("--text-file")
    ap.add_argument("--tap", action="append", default=[])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    text = args.text if args.text is not None else (open(args.text_file, encoding="utf-8").read()
                                                     if args.text_file else "")
    gate = Gate()
    print(f"sources: {gate.sources}")
    if text:
        anns = gate.annotate(text, args.threshold, args.mode)
        print(f"drawn at {args.threshold}: " + (" ".join(f"{c}={r}{'*' if s else ''}" for c, r, s in anns) or "none"))
    for t in args.tap:
        char, _, nth = t.partition(":")
        p = gate.popup(text, args.threshold, char, int(nth or 1), args.mode)
        print(f"\n== tap {char} #{nth or 1}: drawn {p['drawn'] or '-'}, chosen {p['chosen'] or '-'}")
        print(json.dumps(p, ensure_ascii=False, indent=1) if args.json else format_popup(p))


if __name__ == "__main__":
    main()
