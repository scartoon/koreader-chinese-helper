-- The reader's own character frequency ranks (#42), counted from their books
-- by tools/build_user_ranks.py (pure Lua, testable offline).
--
-- The file (main.lua: settings/chinesehelper_ranks.tsv, next to the marks
-- file, so plugin updates and reinstalls keep it):
--
--   # chinesehelper user ranks (tools/build_user_ranks.py)
--   # date <TAB> 2026-11-19
--   # works <TAB> 42
--   # han <TAB> 41325818
--   # ranked <TAB> 7215
--   # exact <TAB> 5700
--   char <TAB> rank <TAB> works <TAB> occurrences
--
-- Only characters seen in the books are listed; every other character keeps
-- its bundled (wordfreq) rank (Readings:char). Ranks past `exact` are too
-- thin to tell apart: the popup shows them as "N+".

local Ranks = {}

-- Parse the file's text. Returns { ranks = { [char] = rank }, info = {
-- date=, works=, files=, han=, ranked=, exact= } }, or nil and a message
-- when no character row was found.
function Ranks.parse(text)
    local ranks, info, rows = {}, {}, 0
    for raw in (text or ""):gmatch("[^\n]+") do
        local line = raw:gsub("\r$", "")
        if line:sub(1, 1) == "#" then
            local key, value = line:match("^#%s*(%a+)\t([^\t]+)$")
            if key then info[key] = tonumber(value) or value end
        else
            local ch, rank = line:match("^([^\t]+)\t(%d+)")
            rank = tonumber(rank)
            if ch and rank and rank > 0 then
                ranks[ch] = rank
                rows = rows + 1
            end
        end
    end
    if rows == 0 then return nil, "no ranks in the file" end
    if type(info.exact) ~= "number" or info.exact <= 0 then info.exact = nil end
    info.rows = rows
    return { ranks = ranks, info = info }
end

-- Read and parse `path`. nil (and a message) when it is missing or empty.
function Ranks.load(path)
    local f = path and io.open(path, "r")
    if not f then return nil, "missing" end
    local text = f:read("*a")
    f:close()
    return Ranks.parse(text)
end

return Ranks
