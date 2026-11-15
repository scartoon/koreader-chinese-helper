-- The popup's faces with the book font first (ch_bookfont.lua), against a
-- fake Font module shaped like KOReader's ui/font.lua: faces with a hash, an
-- orig_size and a getFallbackFont(num) callback.
local BookFont = require("ch_bookfont")
local eq = require("sq3_shim").eq

local function fakeFont(fail)
    local Font = { faces = {}, calls = 0, use_bold_font_for_bold = true }
    function Font:getFace(name, size, index)
        self.calls = self.calls + 1
        if fail and name:find(fail, 1, true) then return nil end
        local hash = name .. size .. (index and ("/" .. index) or "")
        if self.faces[hash] then return self.faces[hash] end
        local face = { realname = name, orig_size = size, size = size, hash = hash, ftsize = {},
                       is_real_bold = name:find("Bold", 1, true) ~= nil }
        face.getFallbackFont = function(num)
            if not num or num == 0 then face.completed = true; return face end
            if num == 1 then return self:getFace("NotoSansCJKsc-Regular.otf", size) end
            return false
        end
        self.faces[hash] = face
        return face
    end
    function Font:getAdjustedFace(face, bold)
        if face.is_real_bold or not bold then return face, face.is_real_bold or false end
        if self.use_bold_font_for_bold then return self:getFace("NotoSans-Bold.ttf", face.orig_size), true end
        local hash = face.hash .. "synthbold"
        if self.faces[hash] then return self.faces[hash], "force" end
        local copy = setmetatable({ wants_bold = "force" }, { __index = face })
        copy.getFallbackFont = function(num) return num == 0 and copy or face.getFallbackFont(num) end
        self.faces[hash] = copy
        return copy, "force"
    end
    return Font
end

local KAI = { name = "LXGW WenKai", path = "/system/fonts/LXGWWenKai.ttf", index = 0 }
local SONG = { name = "Noto Serif SC", path = "/sdcard/fonts/NotoSerifCJK.ttc", index = 2 }

-- The book font comes first; the UI font's own fallbacks after it.
local Font = fakeFont()
BookFont.faces = {}
local base = Font:getFace("NotoSans-Regular.ttf", 20)
local face = BookFont.wrap(Font, base, KAI)
assert(face ~= base, "a copy")
eq(face.getFallbackFont(0), face, "num 0: the face itself")
eq(face.getFallbackFont(1).realname, KAI.path, "first fallback: the book font")
eq(face.getFallbackFont(1).orig_size, 20, "at the popup's size")
eq(face.getFallbackFont(2).realname, "NotoSansCJKsc-Regular.otf", "then KOReader's list")
eq(face.getFallbackFont(3), false)
eq(face.ftsize, base.ftsize, "the UI font's glyphs for Latin text")
assert(face.hash ~= base.hash, "its own cache name")
assert(base.completed and face.getFallbackFont(1).completed, "properties completed")
-- KOReader's own face is untouched.
eq(base.getFallbackFont(1).realname, "NotoSansCJKsc-Regular.otf", "the UI face keeps its fallbacks")
-- The face index is passed for a collection (.ttc).
eq(BookFont.wrap(Font, base, SONG).getFallbackFont(1).hash, SONG.path .. "20/2")

-- The cache: one copy per (UI face, book font); a new font or size is a new copy.
local calls = Font.calls
eq(BookFont.wrap(Font, base, KAI), face, "cached")
eq(Font.calls, calls, "no new lookup")
assert(BookFont.wrap(Font, base, SONG) ~= face, "another book font: another copy")
local bigger = BookFont.wrap(Font, Font:getFace("NotoSans-Regular.ttf", 26), KAI)
assert(bigger ~= face and bigger.getFallbackFont(1).orig_size == 26, "another size: another copy")

-- No book font, or one that will not load: the UI face as it is (and the
-- failure is remembered).
eq(BookFont.wrap(Font, base, nil), base)
Font = fakeFont("Broken")
BookFont.faces = {}
base = Font:getFace("NotoSans-Regular.ttf", 20)
local broken = { name = "Broken", path = "/x/Broken.ttf", index = 0 }
eq(BookFont.wrap(Font, base, broken), base, "unloadable: the UI face")
calls = Font.calls
eq(BookFont.wrap(Font, base, broken), base)
eq(Font.calls, calls, "not retried for each popup")
-- A Font that throws: still the UI face.
local throwing = setmetatable({ getFace = function() error("boom") end }, { __index = Font })
BookFont.faces = {}
eq(BookFont.wrap(throwing, base, KAI), base, "an error: the UI face")

-- Bold (the context line's marked character): KOReader's bold face, with the
-- book font first; getAdjustedFace gives it back as it is.
Font = fakeFont()
BookFont.faces = {}
base = Font:getFace("NotoSans-Regular.ttf", 20)
local bold = BookFont.bold(Font, base, KAI)
eq(bold.is_real_bold, true); eq(bold.getFallbackFont(1).realname, KAI.path)
eq((Font:getAdjustedFace(bold, true)), bold, "kept by getAdjustedFace")
-- Synthesized bold (bold fonts off in KOReader): the copy is registered
-- under the name getAdjustedFace looks up.
Font.use_bold_font_for_bold = false
BookFont.faces = {}
bold = BookFont.bold(Font, base, KAI)
eq(bold.wants_bold, "force"); eq(bold.getFallbackFont(1).realname, KAI.path)
eq((Font:getAdjustedFace(bold, true)), bold, "the synthesized copy is kept too")

-- Which font: the one chosen in the font menu, for crengine documents only.
local function ui(provider, name)
    return { document = { provider = provider, getFontFace = function() return name end } }
end
local cre = {
    getFontFaceFilenameAndFaceIndex = function(name, _, italic)
        if name == "LXGW WenKai" then return KAI.path, 0 end
        if name == "Italic Only" and italic then return "/f/ItalicOnly.ttf", 1 end
        return nil
    end,
}
local get_cre = function() return cre end
local got = BookFont.resolve(ui("crengine", "LXGW WenKai"), get_cre)
eq(got.name, "LXGW WenKai"); eq(got.path, KAI.path); eq(got.index, 0)
eq(BookFont.resolve(ui("crengine", "Italic Only"), get_cre).path, "/f/ItalicOnly.ttf", "italic-only font")
eq(BookFont.resolve(ui("crengine", "Not Installed"), get_cre), nil, "no file: nil")
eq(BookFont.resolve(ui("mupdf", "LXGW WenKai"), get_cre), nil, "a PDF: nil")
eq(BookFont.resolve(ui("crengine", ""), get_cre), nil)
eq(BookFont.resolve(nil, get_cre), nil)
eq(BookFont.resolve(ui("crengine", "LXGW WenKai"), function() error("no cre") end), nil, "an error: nil")

-- Buttons: a font name whose every size, down to BUTTON_MIN, is the bold UI
-- face with the book font first, found in Font's cache (no file lookup).
Font = fakeFont()
Font.use_bold_font_for_bold = true
BookFont.faces = {}
local scale = function(s) return s * 2 end
local name = BookFont.buttonFont(Font, scale, KAI, "cfont", 20)
assert(name ~= "cfont", name)
for size = BookFont.BUTTON_MIN, 20 do
    local f = Font.faces[name .. scale(size)]
    assert(f, "size " .. size)
    eq(f.is_real_bold, true); eq(f.getFallbackFont(1).realname, KAI.path)
end
eq(BookFont.buttonFont(Font, scale, KAI, "cfont", 20), name, "the same name next time")
eq(BookFont.buttonFont(Font, scale, nil, "cfont", 20), "cfont", "no book font: Button's own")
