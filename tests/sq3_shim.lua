-- Test helpers: a stand-in for KOReader's SQLite binding (lua-ljsqlite3),
-- backed by Python's sqlite3 through tests/run.py (PY_SQLITE), with the same
-- calls ch_db.lua makes: open, prepare, reset, bind, step, clearbind, close.
-- Plus the plugin's real data, loaded the way the plugin loads it.

local H = {}

local SQ3 = {}
function SQ3.open(path)
    local py = PY_SQLITE
    local cid = py.open(path)
    local conn = {}
    function conn.close() py.close(cid) end
    function conn.prepare(_, sql)
        local sid = py.prepare(cid, sql)
        return {
            reset = function() py.reset(sid) end,
            bind = function(_, ...) py.bind(sid, { ... }) end,
            step = function() return py.step(sid) end,
            clearbind = function() py.clearbind(sid) end,
            close = function() end,
        }
    end
    return conn
end
H.SQ3 = SQ3

local cache = {}

-- The database, as the plugin opens it (ch_db.lua over the stand-in).
function H.db()
    if not cache.db then
        local DB = require("ch_db")
        cache.db = assert(DB.open(DB_PATH, SQ3))
    end
    return cache.db
end

-- The resolver's tables, as the plugin loads them.
function H.readings()
    if not cache.readings then cache.readings = H.db():readings() end
    return cache.readings
end

function H.special()
    if not cache.special then cache.special = H.db():special() end
    return cache.special
end

-- Engine-like items for a string: one item per Han character; punctuation,
-- spaces, digits and Latin are not items but break the "joined" chain, as in
-- the rendering engine. "|" toggles on_page (a page boundary does not break
-- a word).
function H.items(text)
    local Resolve = require("ch_resolve")
    local items, joined, on_page = {}, false, true
    if text:find("|", 1, true) then on_page = false end
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if ch == "|" then
            on_page = not on_page
        elseif Resolve.single_char(ch) and not ch:match("^\227\128") and not ch:match("^\239\188") then
            items[#items + 1] = { text = ch, joined = joined, on_page = on_page }
            joined = true
        else
            joined = false
        end
    end
    return items
end

function H.eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

return H
