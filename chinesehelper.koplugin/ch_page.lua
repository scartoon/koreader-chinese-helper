-- Walk the current page through the rendering engine and turn the
-- annotations into screen positions. The same page items feed the tap popup's
-- reading (Page.find), so the popup resolves a character exactly as the
-- annotation layer does.
--
-- From pinyin_page.lua in koreader-interlinear-pinyin, itself based on
-- wordgloss_page.lua from WordGloss (GPL-3.0, GangYe293), changed to:
--   * read a few characters of context before and after the page, so a word
--     split across a page turn still resolves (and the first character of the
--     page is not skipped: the engine's next-word-start never returns the
--     position it starts from);
--   * decide what to annotate first and only then ask for screen boxes, since a
--     Chinese page has hundreds of one-character "words" and box lookups are the
--     expensive part.

local Resolve = require("ch_resolve")

local Page = {}

Page.MAX_ITEMS = 3000
Page.CONTEXT = 3     -- characters of context kept on each side of the page

local function call(object, method, ...)
    if not object or not object[method] then return nil end
    local ok, value = pcall(object[method], object, ...)
    if not ok then return nil end
    return value
end

local function visible_pages(document)
    local count = call(document, "getVisiblePageCount")
    if type(count) ~= "number" or count < 1 then return 1 end
    return count
end

-- Items for the page plus context, each { text=, ws=, we=, joined=, on_page= }.
-- scroll: continuous view, where the screen starts anywhere in a page and
-- ends in the next one: "the page" is then what is on screen, from the top of
-- the screen (document:getXPointer()) to the start of the page after next
-- (a page is a screen high); Page.build leaves out what falls below it.
function Page.collect(document, page, scroll)
    if not document then return {} end
    page = page or call(document, "getCurrentPage") or 1
    local start_xp = scroll and call(document, "getXPointer") or call(document, "getPageXPointer", page)
    if not start_xp then return {} end
    local end_xp = call(document, "getPageXPointer", page + (scroll and 2 or visible_pages(document)))
    -- Past the last page the engine returns "" rather than nil.
    if end_xp == "" then end_xp = nil end

    -- Step back a few words so the first on-page character is not skipped and
    -- has its left-hand context.
    local xp = start_xp
    for _ = 1, Page.CONTEXT + 1 do
        local prev = call(document, "getPrevVisibleWordStart", xp)
        if not prev then break end
        xp = prev
    end
    -- getNextVisibleWordStart skips a word starting exactly at xp, so begin one
    -- step earlier still when possible.
    local before = call(document, "getPrevVisibleChar", xp)
    if before then xp = before end

    local items, seen_page, past_end = {}, false, 0
    for _ = 1, Page.MAX_ITEMS do
        local ws = call(document, "getNextVisibleWordStart", xp)
        if not ws then break end
        local we = call(document, "getNextVisibleWordEnd", ws)
        if not we then break end
        local text = call(document, "getTextFromXPointers", ws, we)
        -- compareXPointers(a, b) is 1 when b is after a, 0 when equal, -1 otherwise.
        local on_page = call(document, "compareXPointers", start_xp, ws) ~= -1
        if on_page and end_xp and call(document, "compareXPointers", ws, end_xp) ~= 1 then
            on_page = false
        end
        if text and text ~= "" then
            local prev = items[#items]
            items[#items + 1] = {
                text = text, ws = ws, we = we, on_page = on_page,
                joined = prev ~= nil and prev.we == ws,
            }
            if on_page then
                seen_page = true
            elseif seen_page then
                past_end = past_end + 1
                if past_end >= Page.CONTEXT then break end
            end
        end
        -- Continue from this word's start, not its end: for CJK the end of one
        -- character is exactly the start of the next, and next-word-start never
        -- returns its own starting position, so stepping from `we` would skip
        -- every other character. Stepping from `ws` works for spaced text too.
        xp = ws
    end
    return items
end

-- Screen box for one item; nil when it is not on screen (screen_h: the
-- screen's height, to leave out boxes below or above it in continuous view).
-- get_segments must be true: in word mode crengine returns the box of every
-- word the range touches, and the range end (`we`) is the start of the next
-- CJK character, so each box would also cover the following character.
local function boxes_for(document, item, screen_h)
    local boxes = call(document, "getScreenBoxesFromPositions", item.ws, item.we, true)
    for _, box in ipairs(boxes or {}) do
        if box and box.w and box.w > 0 and box.h and box.h > 0
                and not (screen_h and (box.y >= screen_h or box.y + box.h <= 0)) then
            return box
        end
    end
    return nil
end

--[[--
Annotations for the current page, ready for the overlay:
  { {text="tāo", box={x,y,w,h}, rank=4396, char="饕", ws=, we=, index=,
     special=true or nil}, ... }
(ws/we: the character's xpointers; index: its position in items), plus stats
{ items=, annotated=, special= } and the items themselves (for Page.find).
special: loaded special words, or nil when that setting is off.
scroll: continuous view (see Page.collect), with screen_h the screen height.
]]
function Page.build(document, page, data, threshold, uncertain, special, scroll, screen_h)
    local items = Page.collect(document, page, scroll)
    local stats = { items = #items, annotated = 0, special = 0 }
    local glosses = {}
    for _, a in ipairs(Resolve.annotate(data, items, threshold, uncertain, special)) do
        local item = items[a.index]
        local box = boxes_for(document, item, scroll and screen_h or nil)
        if box then
            glosses[#glosses + 1] = {
                text = a.reading, box = box, rank = a.rank, char = item.text,
                ws = item.ws, we = item.we, index = a.index, special = a.special,
            }
            if a.special then stats.special = stats.special + 1 end
        end
    end
    stats.annotated = #glosses
    return glosses, stats, items
end

-- Index of the item starting at xpointer xp (a tapped character's pos0), or
-- nil. Items hold the engine's word starts; a tap gives the character's
-- start, which is the same xpointer (compared through the engine when the
-- strings differ).
function Page.find(document, items, xp)
    if not items or not xp then return nil end
    for i, item in ipairs(items) do
        if item.ws == xp then return i end
    end
    for i, item in ipairs(items) do
        if call(document, "compareXPointers", item.ws, xp) == 0 then return i end
    end
    return nil
end

return Page
