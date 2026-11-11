-- Settings, defaults and the one-time migration from the two plugins this one
-- replaces (pure Lua: the settings store is passed in, so it is tested
-- offline). Everything is global (G_reader_settings), as in both old
-- plugins; neither stored anything per book.

local Settings = {}
Settings.__index = Settings

Settings.PREFIX = "chinesehelper_"

Settings.THRESHOLDS = { 1500, 2500, 3500, 5000, 7000 }
Settings.SIZES = { 35, 40, 45, 50, 55 }            -- pinyin size, % of the book's text size
Settings.POPUP_SIZES = { 70, 80, 90, 100, 110, 120 } -- popup text size, % of the book's text size

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
    popup_text_pct = 70,      -- 45 px on a Boox Go 7 with 64 px book text: the old popups used 43 px
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

function Settings:threshold()
    return tonumber(self:get("threshold")) or Settings.DEFAULTS.threshold
end

function Settings:sizePercent()
    local pct = tonumber(self:get("size_pct")) or Settings.DEFAULTS.size_pct
    return math.max(20, math.min(80, pct))
end

function Settings:popupTextPercent()
    local pct = tonumber(self:get("popup_text_pct")) or Settings.DEFAULTS.popup_text_pct
    return math.max(50, math.min(200, pct))
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
