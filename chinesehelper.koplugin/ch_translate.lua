-- The popup's sentence button: sends the sentence around the tapped character
-- (ch_sentence.lua) to KOAssistant, or to KOReader's translator.
--
--   KOAssistant installed and loaded, and its internals as expected:
--     "Translate & analyze the surrounding sentence [AI]", run through KOAssistant with the action below,
--     the way its highlight-menu action buttons run an action;
--   otherwise: "Translate", KOReader's built-in translator (the highlight
--     menu's Translate: ReaderHighlight:onTranslateText).
-- Decided when the popup opens, so the label always says what the button
-- does. Shown only while Wi-Fi is on and connected (NetworkMgr's cheap state
-- checks, no lookup or request); a connection lost after that is KOReader's
-- or KOAssistant's to handle.

local Translate = {}

--[[--
The Translate & Analyze action: prompt, system prompt (behavior_override),
book context and API parameters. It started as a snapshot of the author's
KOAssistant "Translate & Analyze" custom action (2026-11-11, KOAssistant
0.23.0) and was rewritten for learners on 2026-11-18 (#30): every word, in
plain English. The button never looks up custom actions, so your own custom
actions don't change it and it works for anyone with KOAssistant installed.
]]
Translate.KOASSISTANT_ACTION = {
    text = "Translate & Analyze",
    context = "highlight",
    include_book_context = true,
    behavior_override = "You are a patient Chinese teacher. Translate naturally and explain every word in plain English, never punctuation. No preamble, no summary, no padding.",
    prompt = [[Text from '{title}':

"{highlighted_text}"

Explain this text for someone learning Chinese. Use plain, everyday English. Avoid grammar jargon: instead of naming a construction, say what it does (write "得 between a verb and a result means 'able to'", not "potential complement").

**Translation:** one natural English translation of the whole selection, the way a good translator would write it. No pinyin for the full text.

**Word by word:** go through the text in order and cover every word, including small ones like 的, 了, 吧, 把 and measure words. Punctuation marks (，。、：；！？“”《》…… and the like) are not words: never give one a line, not even an empty one. Group characters into words the way a reader would (电脑 is one entry, not two). One line per word, in exactly this shape:
- **汉字** (pīnyīn): meaning in this sentence — what it's doing, if that isn't obvious

Rules:
- Always write the original characters in bold, then pinyin with tone marks in parentheses. Never replace the characters with pinyin.
- Give the meaning that fits this sentence, not a list of dictionary senses.
- For words with no English equivalent (了, 的, 着, 吧, measure words), say in a few words what job they do here.
- Keep a set phrase or idiom (成语) together as one entry: give its literal meaning and what it actually means.
- If a word is literary, old-fashioned, or used in an unusual way here, say so in plain words.
- If the parts of a multi-character word make its meaning easier to remember, you may add them in brackets, e.g. 电脑 (electric + brain).
- If a word comes up again with the same meaning, give it a short line ("as above") rather than skipping it.
- If something can be read two ways, say so briefly and give both.

Example of the shape (not of content), for 我看得懂这本书了！ (the ！ gets no line):
- **我** (wǒ): I
- **看得懂** (kàn de dǒng): can read and understand — 得 between a verb and a result means "able to"
- **这** (zhè): this
- **本** (běn): measure word for books
- **书** (shū): book
- **了** (le): no English word; shows a change: now I can

**How it fits together:** one to three plain sentences on how the sentence is built, but only if the word order or structure would surprise an English speaker (for example, a long description placed before the noun, or the object moved to the front with 把). Leave this out if there's nothing to say.

Bold labels, no headers, no closing remarks.]],
    api_params = {
        temperature = 0.3,
        max_tokens = 2000,
    },
}

-- Fields KOAssistant's ActionService adds to an action it loads from
-- custom_actions.lua (addCustomAction); the id is our own.
Translate.ACTION_ID = "chinesehelper_translate_analyze"

-- The button's label; [AI]: the answer comes from a language model.
Translate.LABELS = { koassistant = "Translate & analyze the surrounding sentence [AI]", translator = "Translate" }

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
