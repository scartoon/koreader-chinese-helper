-- Chinese text in the popup in the book's font (the "Try to match the book's
-- font" setting).
--
-- KOReader's UI font (Noto Sans) has no CJK glyphs: every Chinese character
-- in a popup comes from a fallback font. xtext asks a face for its fallbacks
-- through the face's own getFallbackFont(num) callback (ui/font.lua). So a
-- popup face here is a copy of the UI face whose first fallback is the book
-- font: Latin text, pinyin and tone marks stay in Noto Sans, every CJK glyph
-- comes from the book font, and glyphs it lacks fall through to KOReader's
-- usual list. KOReader's global Font.fallbacks and its own faces are left
-- alone.
--
-- The book font is the one chosen in KOReader's font menu
-- (CreDocument:getFontFace), not fonts the book embeds or sets in its CSS.
-- Anything that fails (not a crengine document, a name with no file, a file
-- FreeType will not load) leaves the UI face as it is.
--
-- No KOReader requires at load: Font and cre are passed in (tested offline,
-- tests/test_bookfont.lua).

local BookFont = {}

-- Copies, by UI face and book font: { [key] = face, or false (failed) }.
BookFont.faces = {}

--[[--
The font chosen for the book in `ui` ({ name=, path=, index= }), or nil.
get_cre: returns the crengine module (CreDocument:engineInit()); called
only for a crengine document.
]]
function BookFont.resolve(ui, get_cre)
    local ok, font = pcall(function()
        local doc = ui and ui.document
        if not doc or doc.provider ~= "crengine" or type(doc.getFontFace) ~= "function" then return nil end
        local name = doc:getFontFace()
        if type(name) ~= "string" or name == "" then return nil end
        local cre = get_cre()
        if not cre or type(cre.getFontFaceFilenameAndFaceIndex) ~= "function" then return nil end
        local path, index = cre.getFontFaceFilenameAndFaceIndex(name)
        if not path then
            -- A font only available in italic (as ReaderFont's menu does).
            path, index = cre.getFontFaceFilenameAndFaceIndex(name, nil, true)
        end
        if type(path) ~= "string" or path == "" then return nil end
        return { name = name, path = path, index = tonumber(index) or 0 }
    end)
    return ok and font or nil
end

-- The cache key of `base` with `book`.
local function key(base, book)
    return tostring(base.hash) .. "|chbook:" .. book.path .. "/" .. tostring(book.index)
end

--[[--
`base` (a face from Font:getFace) with `book` ({path=, index=}, or nil) as its
first fallback, or `base` itself when there is no book font or it cannot be
loaded. Cached per (base face, book font): a new book font or popup text size
is a new key, so it applies to the next popup.
]]
function BookFont.wrap(Font, base, book)
    if not base or not book or not book.path then return base end
    local k = key(base, book)
    local cached = BookFont.faces[k]
    if cached == false then return base end
    if cached then return cached end
    local ok, face = pcall(function()
        local bf = Font:getFace(book.path, base.orig_size, book.index ~= 0 and book.index or nil)
        if not bf or not bf.getFallbackFont then return nil end
        -- (num 0 completes each face's properties, as xtext's first call would.)
        bf = bf.getFallbackFont(0) or bf
        base.getFallbackFont(0)
        local face = {}
        for name, value in pairs(base) do face[name] = value end
        face.fallbacks = nil
        -- Its own name in KOReader's caches: RenderText's glyph cache (the
        -- same glyphs as base, cached twice) and Font:getAdjustedFace's
        -- bold copies, which must not be base's.
        face.hash = k
        face.book_font = bf
        face.getFallbackFont = function(num)
            if not num or num == 0 then return face end
            if num == 1 then return bf end
            return base.getFallbackFont(num - 1)
        end
        return face
    end)
    if not ok or not face then
        BookFont.faces[k] = false
        return base
    end
    BookFont.faces[k] = face
    return face
end

--[[--
The bold face for `base` with `book` (for a TextWidget with bold = true): the
face KOReader would use for bold text (Font:getAdjustedFace: Noto Sans Bold,
or Noto Sans with synthesized bold), with the book font first. A synthesized
bold copy is entered in Font's own cache under the names getAdjustedFace looks
for, so a TextWidget given it with bold = true keeps it.
]]
function BookFont.bold(Font, base, book)
    if not base or not book then return base end
    local ok, face = pcall(function()
        local adjusted = Font:getAdjustedFace(base, true)
        local face = BookFont.wrap(Font, adjusted, book)
        if face ~= adjusted and not face.is_real_bold and Font.faces then
            Font.faces[face.hash .. "synthbold"] = face
            Font.faces[face.hash .. "realbold"] = face
        end
        return face
    end)
    return ok and face or base
end

return BookFont
