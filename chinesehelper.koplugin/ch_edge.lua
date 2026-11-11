-- The edge band (pure Lua, no KOReader dependencies, tested offline): a tap
-- within a set distance of any screen edge is always KOReader's (page turn,
-- menus, corner actions), even on a Chinese character or its pinyin.
--
-- Widths are set in millimetres and converted with the screen's DPI, so the
-- band is the same physical size on any screen. Edges are those of the
-- screen in its current orientation: the caller passes the current width and
-- height (KOReader's Screen:getWidth()/getHeight(), which follow rotation),
-- and tap positions are in the same coordinates.

local Edge = {}

Edge.CHOICES = { 0, 2.5, 5, 7.5, 10 }   -- millimetres; 0 = off
Edge.FALLBACK_DPI = 300                 -- when the screen reports no usable DPI

-- Band width in pixels for `mm` millimetres at `dpi` (0 when off).
function Edge.px(mm, dpi)
    mm = tonumber(mm) or 0
    if mm <= 0 then return 0 end
    dpi = tonumber(dpi)
    if not dpi or dpi <= 0 then dpi = Edge.FALLBACK_DPI end
    return math.floor(mm * dpi / 25.4 + 0.5)
end

-- Is (x, y) within `band` pixels of an edge of a w x h screen? Never when
-- the band is 0.
function Edge.inBand(x, y, w, h, band)
    if not band or band <= 0 or not x or not y then return false end
    return x < band or y < band or x >= w - band or y >= h - band
end

return Edge
