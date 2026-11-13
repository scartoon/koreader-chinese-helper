-- Settings, defaults and the one-time migration from the two plugins this one
-- replaces (pure Lua: the settings store is passed in, so it is tested
-- offline). Everything is global (G_reader_settings), as in both old
-- plugins; neither stored anything per book.

local Settings = {}
Settings.__index = Settings

Settings.PREFIX = "chinesehelper_"

Settings.THRESHOLDS = { 1500, 2500, 3500, 5000, 7000 }
Settings.SIZES = { 35, 40, 45, 50, 55 }            -- pinyin size, % of the book's text size
Settings.POPUP_SIZES = { 40, 60, 80, 100, 120 }     -- popup text size, % of the book's text size

Settings.UNCERTAIN_BOTH = "both"
Settings.UNCERTAIN_BEST = "best"
Settings.UNCERTAIN_SKIP = "skip"

Settings.DEFAULTS = {
    pinyin_enabled = false,   -- "Show pinyin above rare characters"
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
    fallback_xinhua = true,   -- and 出处 view of idioms CC-CEDICT has
    -- Not in the menu: the fallback dictionaries' priority, comma-separated.
    -- Sources left out keep their default place after the ones named.
    fallback_order = "wikt,cbdb,moe,idioms,xinhua,wp,moegirl",
    labels = "fallback",      -- source labels: "all", "fallback" (entries not from CC-CEDICT), "none"
    edge_mm = 5,              -- "Edge pass-through width": 0 (off), 2.5, 5, 7.5 or 10 mm
    popup_text_pct = 60,      -- 38 px on a Boox Go 7 with 64 px book text (the old popups used 43 px)
    components = true,        -- "Show character components" in single-character popups
    popup_context = true,     -- "Show the text around the character in the popup"
    page_underline = true,    -- "Underline the tapped character on the page"
}

-- Old key -> new key. interlinearpinyin_tap_definitions has no successor:
-- "Tap characters for popup" governs every popup now.
Settings.MIGRATIONS = {
    { "interlinearpinyin_enabled", "pinyin_enabled" },
    { "interlinearpinyin_threshold", "threshold" },
    { "interlinearpinyin_size_pct", "size_pct" },
    { "interlinearpinyin_uncertain", "uncertain" },
    { "interlinearpinyin_special", "special" },
    { "interlinearpinyin_special_style", "special_style" },
    { "chinesepopup_enabled", "popup_enabled" },
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

--[[--
Copy the old plugins' settings to this plugin's keys, once. A key already
set here is never overwritten, and the old keys are left as they are (so
reinstalling an old plugin still finds its settings). Returns the list of
"old -> new" keys copied (empty when there was nothing to do).
]]
function Settings:migrate()
    local store = self.store
    if not store then return {} end
    if store:readSetting(Settings.PREFIX .. "migrated") then return {} end
    local copied = {}
    for _, m in ipairs(Settings.MIGRATIONS) do
        local old, new = m[1], m[2]
        local value = store:readSetting(old)
        if value ~= nil and store:readSetting(Settings.PREFIX .. new) == nil then
            store:saveSetting(Settings.PREFIX .. new, value)
            copied[#copied + 1] = old .. " -> " .. Settings.PREFIX .. new
        end
    end
    store:saveSetting(Settings.PREFIX .. "migrated", 1)
    if store.flush then pcall(function() store:flush() end) end
    return copied
end

-- Typed getters, with out-of-range values brought back to something valid.
function Settings:pinyinEnabled() return self:get("pinyin_enabled") == true end
function Settings:popupEnabled() return self:get("popup_enabled") == true end
function Settings:specialEnabled() return self:get("special") == true end
function Settings:componentsEnabled() return self:get("components") == true end
function Settings:contextEnabled() return self:get("popup_context") == true end
function Settings:underlineEnabled() return self:get("page_underline") == true end

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
