-- A character's components, as the popup shows them below its own entry
-- (pure Lua, tested offline). Rows never contain a character outside the
-- BMP (the build skips those: the device fonts would draw boxes). The rows are built by tools/components.py
-- (Builder, which documents the format) into the components table:
--
--   H  source  type  flags  via  changes  choices  origin
--   P  form  lookup  role  reading  gloss  match  flags
--
-- One line per part:
--
--   髟 biāo  hair; shaggy  → meaning
--   兀 wù  (literary) rising to a height  → sound (loose)
--
-- A simplified character whose simplification hid a part shows its
-- traditional form's analysis, then the parts replaced:
--
--   traditional 觀:
--   雚 guàn  (archaic) stork; heron  → sound (same sound)
--   見 jiàn  see  → meaning
--   simplified: 雚 → 又

local Text = require("ch_text")

local Components = {}

Components.SOURCE_LABELS = { wikt = "Wikt", mmah = "MMAH", ids = "IDS" }
Components.MATCH = { same = "same sound", ending = "same ending", loose = "loose" }
Components.TYPES = { pictogram = "pictogram (象形)", indicative = "indicative (指事)" }

local function split(line)
    local out = {}
    local start = 1
    while true do
        local i = line:find("\t", start, true)
        if not i then
            out[#out + 1] = line:sub(start)
            return out
        end
        out[#out + 1] = line:sub(start, i - 1)
        start = i + 1
    end
end

-- "雚>又,見>见" -> { {"雚", "又"}, {"見", "见"} }
local function pairs_of(s)
    local out = {}
    for item in (s or ""):gmatch("[^,]+") do
        local f, t = item:match("^(.-)>(.*)$")
        if f and f ~= "" then out[#out + 1] = { f, t } end
    end
    return out
end

--[[--
A components row's body as a table:
  { source=, type=, disputed=bool, via= (or nil), changes={ {from, to} }, origin= (or nil),
    choices={ [trad] = { {from, to} } } (or nil),
    parts={ {form=, lookup= (or nil), role=, reading=, gloss=, match=, abbr=bool} } }
nil for an empty or malformed body.
]]
function Components.parse(body)
    if not body or body == "" then return nil end
    local c
    for line in body:gmatch("[^\n]+") do
        local f = split(line)
        if f[1] == "H" then
            c = { source = f[2] or "", type = f[3] or "", disputed = (f[4] or ""):find("d", 1, true) ~= nil,
                  via = (f[5] or "") ~= "" and f[5] or nil, changes = pairs_of(f[6]), parts = {},
                  origin = (f[8] or "") ~= "" and f[8] or nil }
            if f[7] and f[7] ~= "" then
                c.choices = {}
                for item in f[7]:gmatch("[^;]+") do
                    local t, ch = item:match("^(.-)=(.*)$")
                    if t and t ~= "" then c.choices[t] = pairs_of(ch) end
                end
            end
        elseif f[1] == "P" and c then
            c.parts[#c.parts + 1] = {
                form = f[2] or "", lookup = (f[3] or "") ~= "" and f[3] or nil, role = f[4] or "",
                reading = f[5] or "", gloss = f[6] or "", match = f[7] or "",
                abbr = (f[8] or ""):find("a", 1, true) ~= nil,
            }
        end
    end
    return c
end

-- Does the row say anything of its own (parts or a type)? A row may hold
-- only `choices` (发: 發 or 髮, picked by the word).
function Components.hasContent(c)
    return c ~= nil and c.source ~= "" and (#c.parts > 0 or Components.TYPES[c.type] ~= nil)
end

--[[--
For a simplified character with several traditional forms (发: 發 and 髮),
the one the word it was tapped in uses: the longest candidate word (Text.candidates)
with a CC-CEDICT row whose simplified form is that word, the character's
position in the row's traditional form. nil when no word says.
  cands  Text.candidates' first result
  rows   the popup's rows ({simp, trad, source}); fallback rows are ignored
  choices  { [trad] = ... } from Components.parse
]]
function Components.pickTrad(cands, rows, choices)
    if not choices then return nil end
    local by_simp = {}
    for _, row in ipairs(rows or {}) do
        if (row.source == nil or row.source == "cedict") and row.simp and not by_simp[row.simp] then
            by_simp[row.simp] = row
        end
    end
    local best, best_len
    for _, c in ipairs(cands or {}) do
        local row = by_simp[c.text]
        if c.len > 1 and row and (not best_len or c.len > best_len) then
            local chars = Text.chars(row.trad or "")
            local t = chars[1 - c.start]
            if t and choices[t] then
                best, best_len = t, c.len
            end
        end
    end
    return best
end

-- "→ meaning", "→ sound (same sound)", "→ sound, abbreviated (loose)".
function Components.roleText(p)
    if p.role == "s" then return "→ meaning" end
    if p.role == "p" then
        local m = Components.MATCH[p.match]
        local abbr = p.abbr and ", abbreviated" or ""
        if m then return "→ sound" .. abbr .. " (" .. m .. ")" end
        return "→ sound" .. abbr
    end
    return ""
end

--[[--
The popup block for components `c` (Components.parse): { source=, lines={...},
components=true }, or nil when there is nothing to show. b0/b1: bold markers.
`via` and `changes` override the row's (a traditional form picked by the word).
]]
function Components.block(c, b0, b1, via, changes)
    if not Components.hasContent(c) then return nil end
    b0, b1 = b0 or "", b1 or ""
    via = via or c.via
    changes = changes or c.changes
    local lines = {}
    if via then lines[#lines + 1] = "traditional " .. via .. ":" end
    if #c.parts == 0 then
        lines[#lines + 1] = Components.TYPES[c.type]
    end
    for _, p in ipairs(c.parts) do
        local bits = { b0 .. p.form .. b1 }
        if p.reading ~= "" then bits[#bits + 1] = " " .. p.reading end
        if p.gloss ~= "" then bits[#bits + 1] = "  " .. p.gloss end
        local role = Components.roleText(p)
        if role ~= "" then bits[#bits + 1] = "  " .. role end
        lines[#lines + 1] = table.concat(bits)
    end
    if via and changes and #changes > 0 then
        local shown = {}
        for _, ch in ipairs(changes) do shown[#shown + 1] = ch[1] .. " → " .. ch[2] end
        lines[#lines + 1] = "simplified: " .. table.concat(shown, ", ")
    end
    return { source = c.source, lines = lines, components = true }
end

--[[--
What the popup shows for character `ch`: the components to display and the
characters whose origin notes apply.
  lookup(list) -> { [ch] = body }   (DB:components)
Returns c (parsed, or nil), via, changes, note_chars ({ch} or {ch, via}).
]]
function Components.resolve(ch, lookup, cands, rows)
    local bodies = lookup({ ch }) or {}
    local c = Components.parse(bodies[ch])
    if not c then return nil end
    local t = Components.pickTrad(cands, rows, c.choices)
    if t then
        local tb = lookup({ t }) or {}
        local tc = Components.parse(tb[t])
        if Components.hasContent(tc) then
            return tc, t, c.choices[t], { ch, t }
        end
    end
    if not Components.hasContent(c) then return nil end
    if c.via then return c, c.via, c.changes, { ch, c.via } end
    return c, nil, nil, { ch, c.origin }
end

return Components
