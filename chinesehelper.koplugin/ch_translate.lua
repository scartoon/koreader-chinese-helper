-- The popup's sentence button: sends the sentence around the tapped character
-- (ch_sentence.lua) to KOAssistant, or to KOReader's translator.
--
--   KOAssistant installed and loaded, and its internals as expected:
--     "Translate & Analyze", run through KOAssistant with the action below,
--     the way its highlight-menu action buttons run an action;
--   otherwise: "Translate", KOReader's built-in translator (the highlight
--     menu's Translate: ReaderHighlight:onTranslateText).
-- Decided when the popup opens, so the label always says what the button
-- does. Shown only while Wi-Fi is on and connected (NetworkMgr's cheap state
-- checks, no lookup or request); a connection lost after that is KOReader's
-- or KOAssistant's to handle.

local Translate = {}

--[[--
SNAPSHOT of the "Translate & Analyze" custom action from the author's
KOAssistant custom_actions.lua (copied 2026-11-11, KOAssistant 0.23.0):
prompt, system prompt (behavior_override), book context and API parameters,
verbatim. Later edits to that custom action do NOT change this button; the
button never looks the custom action up, so it works for anyone with
KOAssistant installed.
]]
Translate.KOASSISTANT_ACTION = {
    text = "Translate & Analyze",
    context = "highlight",
    include_book_context = true,
    behavior_override = "You are a precise philologist. Translate faithfully and explain only what a strong reader needs. No preamble, no summary, no padding.",
    prompt = [[Text from '{title}':

"{highlighted_text}"

**Translation:** one natural English translation of the whole selection. Do not give pinyin or romanization for the full text.

**Analysis:** go through the text in order, chunk by chunk (a word or tight phrase). For each chunk worth explaining, one line in exactly this shape:
- **汉字** (pīnyīn): literal gloss; grammatical role or pattern

Write each chunk in its original characters, bolded, then pinyin with tone marks in parentheses. Never replace the characters with pinyin. Example of the shape (not of content): **看得懂** (kàn de dǒng): "can read and understand"; potential complement V得C

Skip chunks an advanced reader would know on sight. Flag particles, complements, word order, ellipsis, classical or literary usages, set phrases and idioms where they occur, and only then. If a chunk's role is genuinely ambiguous, say so and give the readings; do not force one.

**Patterns:** if a grammatical construction recurs or governs the whole sentence, name it once with a one-line explanation. Omit this section if there is nothing to say.

Bold labels, no headers, no closing remarks.]],
    api_params = {
        temperature = 0.3,
        max_tokens = 2000,
    },
}

-- Fields KOAssistant's ActionService adds to an action it loads from
-- custom_actions.lua (addCustomAction); the id is our own.
Translate.ACTION_ID = "chinesehelper_translate_analyze"

Translate.LABELS = { koassistant = "Translate & Analyze", translator = "Translate" }

-- A fresh copy for each run (KOAssistant may annotate the table it is given).
function Translate.action()
    local a = {}
    for k, v in pairs(Translate.KOASSISTANT_ACTION) do
        if type(v) == "table" then
            local t = {}
            for k2, v2 in pairs(v) do t[k2] = v2 end
            a[k] = t
        else
            a[k] = v
        end
    end
    a.id = Translate.ACTION_ID
    a.enabled = true
    a.source = "config"
    a.builtin = false
    a.original_context = a.context
    return a
end

-- Wi-Fi on and connected, from NetworkMgr's state checks only (on Android
-- both are android.getNetworkInfo(): no DNS lookup, no request).
function Translate.wifiConnected(network)
    if not network then return false end
    local ok, on = pcall(network.isWifiOn, network)
    if not ok or not on then return false end
    -- On Android isWifiOn is isConnected: one call is enough.
    if network.isConnected == network.isWifiOn then return true end
    local ok2, connected = pcall(network.isConnected, network)
    return ok2 and connected and true or false
end

local function loaded(name, load)
    local m = package.loaded[name]
    if m == nil and load then
        local ok, r = pcall(require, name)
        m = ok and r or nil
    end
    return type(m) == "table" and m or nil
end

--[[--
KOAssistant, when it is loaded and has everything mode 1 calls (the same
calls as its highlight-menu action buttons, KOAssistant 0.23.0):
plugin:executeQuickAction/updateConfigFromSettings, koassistant_dialogs'
extractSurroundingContext/fetchSelectionContextWindow and
koassistant_book_settings.resolveDictionaryContext. nil otherwise.
]]
function Translate.koassistant(ui, load)
    if load == nil then load = true end
    local koa = ui and ui.koassistant
    if type(koa) ~= "table" then return nil end
    if type(koa.executeQuickAction) ~= "function" or type(koa.updateConfigFromSettings) ~= "function" then
        return nil
    end
    if type(ui.highlight) ~= "table" then return nil end
    local dialogs = loaded("koassistant_dialogs", load)
    if not dialogs or type(dialogs.extractSurroundingContext) ~= "function"
            or type(dialogs.fetchSelectionContextWindow) ~= "function" then
        return nil
    end
    local book_settings = loaded("koassistant_book_settings", load)
    if not book_settings or type(book_settings.resolveDictionaryContext) ~= "function" then return nil end
    return { plugin = koa, dialogs = dialogs, book_settings = book_settings }
end

-- "koassistant" or "translator".
function Translate.mode(ui)
    return Translate.koassistant(ui) and "koassistant" or "translator"
end

-- KOReader's translator, through the highlight menu's Translate path.
function Translate.runTranslator(ui, text, translator)
    local highlight = ui and ui.highlight
    if highlight and highlight.onTranslateText then
        highlight:onTranslateText(text)
    else
        (translator or require("ui/translator")):showTranslation(text, true, nil, nil, true)
    end
end

--[[--
Run the action through KOAssistant as its highlight-menu buttons do
(registerHighlightMenuActions' runSlot): the sentence stands in as
ReaderHighlight's selection (text, positions, screen boxes) while the
surrounding context is read from it, then the selection is cleared and
executeQuickAction runs once connected. The selection is never drawn and no
highlight is saved. Returns false when it failed before reaching KOAssistant.
]]
function Translate.runKOAssistant(ui, koa, sentence, network, logger)
    local highlight, document = ui.highlight, ui.document
    local selection
    if sentence.pos0 and sentence.pos1 then
        local ok, boxes = pcall(document.getScreenBoxesFromPositions, document, sentence.pos0, sentence.pos1, true)
        selection = { text = sentence.text, pos0 = sentence.pos0, pos1 = sentence.pos1,
                      sboxes = ok and boxes or nil }
    end
    local context, window, selection_data = "", nil, nil
    local ok, err = pcall(function()
        if not selection then return end
        highlight.selected_text = selection
        local features = koa.plugin.settings and koa.plugin.settings:readSetting("features") or {}
        if highlight.getSelectedWordContext then
            local mode = koa.book_settings.resolveDictionaryContext(ui.doc_settings, features)
            if mode ~= "none" then
                context = koa.dialogs.extractSurroundingContext(ui, sentence.text, mode,
                    features.dictionary_context_chars or 100) or ""
            end
        end
        window = koa.dialogs.fetchSelectionContextWindow(ui, sentence.text)
        selection_data = { text = selection.text, pos0 = selection.pos0, pos1 = selection.pos1,
                           sboxes = selection.sboxes }
    end)
    -- Clear the stand-in selection, as closing the highlight menu does.
    if selection then
        pcall(highlight.clear, highlight)
        highlight.selected_text = nil
    end
    if not ok then
        if logger then logger.warn("chinesehelper: KOAssistant context failed:", tostring(err)) end
        return false
    end
    local run = function()
        local ok2, err2 = pcall(function()
            koa.plugin:updateConfigFromSettings()
            koa.plugin:executeQuickAction(Translate.action(), sentence.text, context, selection_data, window)
        end)
        if not ok2 then
            if logger then logger.warn("chinesehelper: KOAssistant failed:", tostring(err2)) end
            Translate.runTranslator(ui, sentence.text)
        end
    end
    if network and network.runWhenConnected then
        network:runWhenConnected(run)
    else
        run()
    end
    return true
end

--[[--
The button row for the popup, or nil when Wi-Fi is not connected.
opts: ui, network (NetworkMgr), sentence (function returning the sentence
table from ch_sentence.lua, called on press), close (closes the popup),
logger. The mode is decided now; the row is one full-width button.
]]
function Translate.row(opts)
    if not Translate.wifiConnected(opts.network) then return nil end
    local ui = opts.ui
    local koa = Translate.koassistant(ui)
    local mode = koa and "koassistant" or "translator"
    return {
        {
            text = Translate.LABELS[mode],
            callback = function()
                if opts.close then opts.close() end
                local sentence = opts.sentence()
                if not sentence or not sentence.text or sentence.text == "" then return end
                if mode == "koassistant" and Translate.runKOAssistant(ui, koa, sentence, opts.network, opts.logger) then
                    return
                end
                Translate.runTranslator(ui, sentence.text)
            end,
        },
    }, mode
end

return Translate
