-- The popup's sentence button (ch_translate.lua): which mode, shown or not
-- with the network state mocked, and what each mode is handed.
local Translate = require("ch_translate")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function network(on, connected)
    local n = { ran = 0 }
    function n:isWifiOn() return on end
    function n:isConnected() return connected end
    function n:runWhenConnected(f) self.ran = self.ran + 1; f() end
    return n
end

-- A ReaderUI with a ReaderHighlight that records translations and clears.
local function fakeUI()
    local ui = { translated = {}, cleared = 0, doc_settings = {} }
    ui.document = { getScreenBoxesFromPositions = function(_, a, b) return { { x = 1, y = 2, w = 3, h = 4 } } end }
    ui.highlight = {
        onTranslateText = function(_, text) ui.translated[#ui.translated + 1] = text end,
        clear = function() ui.cleared = ui.cleared + 1 end,
        getSelectedWordContext = function(self) return "prev", "next" end,
    }
    return ui
end

-- KOAssistant as loaded in KOReader: the plugin instance on ui and its modules.
local function installKOAssistant(ui)
    local koa = { calls = {} }
    koa.settings = { readSetting = function(_, k) return k == "features" and { dictionary_context_mode = "paragraph" } end }
    function koa:updateConfigFromSettings() self.calls[#self.calls + 1] = "update" end
    function koa:executeQuickAction(action, text, context, selection_data, window)
        self.run = { action = action, text = text, context = context, selection_data = selection_data,
                     window = window, live_selection = ui.highlight.selected_text }
    end
    ui.koassistant = koa
    package.loaded["koassistant_dialogs"] = {
        extractSurroundingContext = function(u, text, mode)
            local st = u.highlight.selected_text
            return st and st.text == text and ("ctx:" .. mode .. ":" .. st.pos0 .. "-" .. st.pos1) or ""
        end,
        fetchSelectionContextWindow = function(u, text)
            local st = u.highlight.selected_text
            return st and { prev = "prev", next = "next", text = text } or nil
        end,
    }
    package.loaded["koassistant_book_settings"] = {
        resolveDictionaryContext = function(_, features) return features.dictionary_context_mode end,
    }
    return koa
end

local function uninstall()
    package.loaded["koassistant_dialogs"] = nil
    package.loaded["koassistant_book_settings"] = nil
end

local SENTENCE = { text = "他说：“今天下雨了。”", pos0 = "1/0", pos1 = "1/10" }
local function press(row)
    row[1].callback()
end

-- Show/hide: Wi-Fi off; on but not connected; connected.
local ui = fakeUI()
eq(Translate.row{ ui = ui, network = network(false, false), sentence = function() return SENTENCE end }, nil, "Wi-Fi off")
eq(Translate.row{ ui = ui, network = network(true, false), sentence = function() return SENTENCE end }, nil,
    "Wi-Fi on, not connected")
eq(Translate.row{ ui = ui, network = network(false, true), sentence = function() return SENTENCE end }, nil,
    "connected but Wi-Fi reported off")
eq(Translate.row{ ui = ui, network = nil, sentence = function() return SENTENCE end }, nil, "no network manager")
local broken = network(true, true)
function broken:isConnected() error("jni") end
eq(Translate.row{ ui = ui, network = broken, sentence = function() return SENTENCE end }, nil, "check throws: hidden")
local row, mode = Translate.row{ ui = ui, network = network(true, true), sentence = function() return SENTENCE end }
assert(row, "connected: shown")
eq(#row, 1, "one full-width button")

-- Mode: KOAssistant absent -> KOReader's translator.
eq(mode, "translator", "absent")
eq(row[1].text, "Translate", "absent: label")
local closed = 0
row = Translate.row{ ui = ui, network = network(true, true), sentence = function() return SENTENCE end,
                     close = function() closed = closed + 1 end }
press(row)
eq(closed, 1, "closes the popup")
eq(ui.translated[1], SENTENCE.text, "translator gets the sentence")
eq(ui.highlight.selected_text, nil, "no selection left")

-- Mode: KOAssistant present -> its action, with a real selection.
ui = fakeUI()
local koa = installKOAssistant(ui)
local net = network(true, true)
row, mode = Translate.row{ ui = ui, network = net, sentence = function() return SENTENCE end }
eq(mode, "koassistant", "present")
eq(row[1].text, "Translate & Analyze", "present: label")
press(row)
assert(koa.run, "executeQuickAction ran")
eq(net.ran, 1, "through runWhenConnected")
eq(koa.calls[1], "update", "config refreshed first")
eq(koa.run.text, SENTENCE.text, "the sentence")
eq(koa.run.context, "ctx:paragraph:1/0-1/10", "context read from the selection, in the user's mode")
eq(koa.run.window.text, SENTENCE.text, "context window")
eq(koa.run.selection_data.pos0, "1/0", "selection start")
eq(koa.run.selection_data.pos1, "1/10", "selection end")
eq(koa.run.selection_data.sboxes[1].w, 3, "screen boxes")
eq(koa.run.live_selection, nil, "selection cleared before the request")
eq(ui.cleared, 1, "highlight cleared")
eq(#ui.translated, 0, "not the translator")
local a = koa.run.action
eq(a.text, "Translate & Analyze"); eq(a.context, "highlight"); eq(a.include_book_context, true)
eq(a.api_params.temperature, 0.3); eq(a.api_params.max_tokens, 2000)
eq(a.id, Translate.ACTION_ID); eq(a.enabled, true); eq(a.source, "config"); eq(a.builtin, false)
eq(a.prompt, Translate.KOASSISTANT_ACTION.prompt)
assert(a.prompt:find("{highlighted_text}", 1, true) and a.prompt:find("{title}", 1, true), "placeholders")
assert(a ~= Translate.KOASSISTANT_ACTION and a.api_params ~= Translate.KOASSISTANT_ACTION.api_params, "a copy")

-- Present, but the sentence has no positions: text only, no selection.
koa.run = nil
row = Translate.row{ ui = ui, network = network(true, true), sentence = function() return { text = "雨" } end }
press(row)
eq(koa.run.text, "雨"); eq(koa.run.context, ""); eq(koa.run.selection_data, nil)

-- Present but KOAssistant fails at run time: the translator instead, no selection left.
ui = fakeUI()
koa = installKOAssistant(ui)
function koa:executeQuickAction() error("changed internals") end
row = Translate.row{ ui = ui, network = network(true, true), sentence = function() return SENTENCE end }
press(row)
eq(ui.translated[1], SENTENCE.text, "fell back to the translator")
eq(ui.highlight.selected_text, nil, "no selection left")
-- Context reading throws: translator, selection cleared.
ui = fakeUI()
koa = installKOAssistant(ui)
package.loaded["koassistant_dialogs"].fetchSelectionContextWindow = function() error("boom") end
row = Translate.row{ ui = ui, network = network(true, true), sentence = function() return SENTENCE end }
press(row)
eq(ui.translated[1], SENTENCE.text, "context failure: translator")
eq(ui.highlight.selected_text, nil, "context failure: no selection left")
eq(ui.cleared, 1, "context failure: cleared")

-- Mode: KOAssistant present but with unexpected internals -> translator.
local function expectTranslator(msg)
    local r, m = Translate.row{ ui = ui, network = network(true, true), sentence = function() return SENTENCE end }
    eq(m, "translator", msg)
    eq(r[1].text, "Translate", msg .. ": label")
end
ui = fakeUI(); koa = installKOAssistant(ui); koa.executeQuickAction = nil
expectTranslator("no executeQuickAction")
ui = fakeUI(); koa = installKOAssistant(ui); koa.updateConfigFromSettings = "x"
expectTranslator("no updateConfigFromSettings")
ui = fakeUI(); installKOAssistant(ui); package.loaded["koassistant_dialogs"].fetchSelectionContextWindow = nil
expectTranslator("dialogs changed")
ui = fakeUI(); installKOAssistant(ui); package.loaded["koassistant_book_settings"] = { }
expectTranslator("book settings changed")
ui = fakeUI(); installKOAssistant(ui); ui.koassistant = function() end
expectTranslator("plugin not a table")
ui = fakeUI(); installKOAssistant(ui); uninstall()
eq(Translate.koassistant(ui, false), nil, "modules not loaded")
uninstall()

-- The snapshot matches the custom action it was copied from, when the
-- device copy is around (build/koassistant_custom_actions.lua; not committed).
local f = io.open(PLUGIN_DIR .. "/../build/koassistant_custom_actions.lua")
if f then
    f:close()
    local actions = dofile(PLUGIN_DIR .. "/../build/koassistant_custom_actions.lua")
    local found
    for _, act in ipairs(actions) do if act.text == "Translate & Analyze" then found = act end end
    assert(found, "custom action not found")
    local n = 0
    for k, v in pairs(found) do
        n = n + 1
        if type(v) == "table" then
            for k2, v2 in pairs(v) do eq(Translate.KOASSISTANT_ACTION[k][k2], v2, k .. "." .. k2) end
        else
            eq(Translate.KOASSISTANT_ACTION[k], v, k)
        end
    end
    for _ in pairs(Translate.KOASSISTANT_ACTION) do n = n - 1 end
    eq(n, 0, "same fields")
end

-- Android: isWifiOn is isConnected (one JNI call); both false or both true.
local android = { calls = 0 }
function android:isConnected() self.calls = self.calls + 1; return self.up end
android.isWifiOn = android.isConnected
android.up = true
eq(Translate.wifiConnected(android), true, "android connected"); eq(android.calls, 1, "one call")
android.up = false
eq(Translate.wifiConnected(android), false, "android not connected")
