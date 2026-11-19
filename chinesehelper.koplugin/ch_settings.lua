-- Settings and their defaults (pure Lua: the settings store is passed in, so
-- it is tested offline). Everything is global (G_reader_settings); nothing is
-- stored per book.

local Settings = {}
Settings.__index = Settings

Settings.PREFIX = "chinesehelper_"

-- 0 is All (learner mode): every character, whatever its rank.
Settings.THRESHOLDS = { 0, 500, 1000, 1500, 2500, 3500, 5000, 7000 }
Settings.ALL = 0
Settings.SIZES = { 35, 40, 45, 50, 55 }            -- pinyin size, % of the book's text size
Settings.POPUP_SIZES = { 40, 60, 80, 100, 120 }     -- popup text size, % of the book's text size
Settings.CHINESE_SIZES = { 100, 115, 130, 150, 175 } -- Chinese text in the popup, % of the popup text size

Settings.UNCERTAIN_BOTH = "both"
Settings.UNCERTAIN_BEST = "best"
Settings.UNCERTAIN_SKIP = "skip"

Settings.DEFAULTS = {
    pinyin_enabled = false,   -- "Show pinyin"
    popup_enabled = true,     -- "Tap characters for popup"
    threshold = 3500,
    size_pct = 40,
    uncertain = "both",
    special = true,
    special_style = "bold",   -- not in the menu: "bold", "underline" or "none"
    fallback_wikt = true,     -- fallback dictionaries, for words CC-CEDICT lacks
    fallback_wp = true,
    fallback_cbdb = true,     -- (CBDB, MOE, Moegirlpedia: only when the user
    fallback_moe = true,      -- has installed their files)
    fallback_moegirl = true,
    fallback_idioms = true,   -- 成語典 and Xinhua idioms: also the short line
    fallback_xinhua = true,   -- and Origin & Usage view of idioms CC-CEDICT has
    -- The dictionaries' order after CC-CEDICT, comma-separated (the menu's
    -- Order item). Sources left out keep their default place after the ones named.
    fallback_order = "wikt,cbdb,moe,idioms,xinhua,wp,moegirl",
    -- MOE 重編國語辭典, for single characters and for words: "off", "fallback"
    -- (only what CC-CEDICT lacks) or "always" (also what it has, collapsed;
    -- needs a MOE file rebuilt with covered rows). fallback_moe off overrides both.
    -- Both default to Fallback (characters were Always in 2.5.0-2.5.2, #24); a
    -- mode chosen in the menu is stored and kept.
    moe_chars = "fallback",
    moe_words = "fallback",
    collapse_lines = 2,       -- "Collapse long entries": 1, 2 or 3 lines, 0 = never
    labels = "fallback",      -- source labels: "all", "fallback" (entries not from CC-CEDICT), "none"
    edge_mm = 5,              -- "Edge pass-through width": 0 (off), 2.5, 5, 7.5 or 10 mm
    popup_text_pct = 60,      -- 38 px on a Boox Go 7 with 64 px book text (the old popups used 43 px)
    chinese_text_pct = 130,   -- "Chinese text size": MOE, 成語典, Xinhua and Moegirlpedia text, and the Origin & Usage view
    components = true,        -- "Show character components" in single-character popups
    char_rank = true,         -- "Show character frequency rank": 字频 N on the tapped character's entry
    popup_context = true,     -- "Show the text around the character in the popup"
    page_underline = true,    -- "Underline the tapped character on the page"
    match_book_font = true,   -- "Try to match the book's font": Chinese text in the popup in the book's font
}

-- store: G_reader_settings (readSetting, saveSetting, flush), or nil.
function Settings.new(store)
    return setmetatable({ store = store }, Settings)
end

function Settings:get(key)
    local value = self.store and self.store:readSetting(Settings.PREFIX .. key)
    if value == nil then return Settings.DEFAULTS[key] end
    return value
end

-- Settings change only from the menu, so write them straight to disk
-- (KOReader otherwise flushes only on a clean exit).
function Settings:set(key, value)
    if not self.store then return end
    self.store:saveSetting(Settings.PREFIX .. key, value)
    if self.store.flush then pcall(function() self.store:flush() end) end
end

-- Typed getters, with out-of-range values brought back to something valid.
function Settings:pinyinEnabled() return self:get("pinyin_enabled") == true end
function Settings:popupEnabled() return self:get("popup_enabled") == true end
function Settings:specialEnabled() return self:get("special") == true end
function Settings:componentsEnabled() return self:get("components") == true end
function Settings:charRankEnabled() return self:get("char_rank") == true end
function Settings:contextEnabled() return self:get("popup_context") == true end
function Settings:underlineEnabled() return self:get("page_underline") == true end
function Settings:matchBookFont() return self:get("match_book_font") == true end

-- "wikt", "wp", "cbdb", "moe", "idioms", "xinhua" or "moegirl": is that
-- fallback dictionary switched on?
function Settings:fallbackEnabled(source)
    return self:get("fallback_" .. source) == true
end

Settings.FALLBACK_SOURCES = { "wikt", "cbdb", "moe", "idioms", "xinhua", "wp", "moegirl" }   -- the default order

-- The fallback dictionaries in priority order: those fallback_order names
-- (unknown names and repeats ignored), then the rest in the default order.
function Settings:fallbackOrder()
    local known, out, seen = {}, {}, {}
    for _, s in ipairs(Settings.FALLBACK_SOURCES) do known[s] = true end
    local value = self:get("fallback_order")
    for name in (type(value) == "string" and value or ""):gmatch("[^,%s]+") do
        if known[name] and not seen[name] then
            out[#out + 1], seen[name] = name, true
        end
    end
    for _, s in ipairs(Settings.FALLBACK_SOURCES) do
        if not seen[s] then out[#out + 1] = s end
    end
    return out
end

Settings.MOE_MODES = { "off", "fallback", "always" }
Settings.COLLAPSE_LINES = { 1, 2, 3, 0 }   -- 0: never collapse

-- MOE's mode for single characters (`kind` "chars") or words ("words"):
-- "off", "fallback" or "always"; "off" whenever MOE itself is switched off.
function Settings:moeMode(kind)
    if not self:fallbackEnabled("moe") then return "off" end
    local key = kind == "words" and "moe_words" or "moe_chars"
    local mode = self:get(key)
    for _, m in ipairs(Settings.MOE_MODES) do
        if mode == m then return mode end
    end
    return Settings.DEFAULTS[key]
end

-- How many lines an Always entry is collapsed to (0: never collapsed).
function Settings:collapseLines()
    local n = tonumber(self:get("collapse_lines"))
    for _, choice in ipairs(Settings.COLLAPSE_LINES) do
        if n == choice then return n end
    end
    return Settings.DEFAULTS.collapse_lines
end

-- Save an order (a list of source names) as fallback_order.
function Settings:setFallbackOrder(list)
    self:set("fallback_order", table.concat(list, ","))
end

Settings.LABEL_MODES = { "all", "fallback", "none" }

function Settings:labelMode()
    local mode = self:get("labels")
    for _, m in ipairs(Settings.LABEL_MODES) do
        if mode == m then return mode end
    end
    return Settings.DEFAULTS.labels
end

-- One of THRESHOLDS; anything else (a hand-edited or old value) is the default.
function Settings:threshold()
    local threshold = tonumber(self:get("threshold"))
    for _, choice in ipairs(Settings.THRESHOLDS) do
        if threshold == choice then return threshold end
    end
    return Settings.DEFAULTS.threshold
end

function Settings:sizePercent()
    local pct = tonumber(self:get("size_pct")) or Settings.DEFAULTS.size_pct
    return math.max(20, math.min(80, pct))
end

-- One of POPUP_SIZES; anything else (e.g. 70 saved by an earlier version) is
-- the default.
function Settings:popupTextPercent()
    local pct = tonumber(self:get("popup_text_pct"))
    for _, size in ipairs(Settings.POPUP_SIZES) do
        if pct == size then return pct end
    end
    return Settings.DEFAULTS.popup_text_pct
end

-- MOE's, the 成語典's and Xinhua's text in the popup, % of the popup text size.
function Settings:chineseTextPercent()
    local pct = tonumber(self:get("chinese_text_pct"))
    for _, size in ipairs(Settings.CHINESE_SIZES) do
        if pct == size then return pct end
    end
    return Settings.DEFAULTS.chinese_text_pct
end

-- Edge pass-through width in millimetres: one of Edge.CHOICES (0 = off).
function Settings:edgeMm()
    local mm = tonumber(self:get("edge_mm"))
    for _, choice in ipairs(require("ch_edge").CHOICES) do
        if mm == choice then return mm end
    end
    return Settings.DEFAULTS.edge_mm
end

function Settings:uncertainMode()
    local mode = self:get("uncertain")
    if mode ~= Settings.UNCERTAIN_BEST and mode ~= Settings.UNCERTAIN_SKIP then
        mode = Settings.UNCERTAIN_BOTH
    end
    return mode
end

function Settings:specialStyle()
    local style = self:get("special_style")
    if style ~= "underline" and style ~= "none" then style = "bold" end
    return style
end

return Settings
