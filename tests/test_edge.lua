-- The edge band (ch_edge.lua): millimetres to pixels, and which taps fall in
-- the band, on all four edges, in portrait and landscape, for every setting.
local Edge = require("ch_edge")
local eq = require("sq3_shim").eq

-- The menu's choices.
eq(table.concat(Edge.CHOICES, ","), "0,2.5,5,10")

-- At 300 dpi (Boox Go 7): 2.5 / 5 / 10 mm = 30 / 59 / 118 px.
eq(Edge.px(0, 300), 0, "0 mm is off")
eq(Edge.px(2.5, 300), 30)
eq(Edge.px(5, 300), 59)
eq(Edge.px(10, 300), 118)
-- Another DPI scales with it; no usable DPI falls back to 300.
eq(Edge.px(5, 150), 30)
eq(Edge.px(5, nil), 59); eq(Edge.px(5, 0), 59)

-- Every width, both orientations of a 1264 x 1680 screen, all four edges:
-- one pixel inside the band passes through, the first pixel outside does not.
local screens = { { name = "portrait", w = 1264, h = 1680 }, { name = "landscape", w = 1680, h = 1264 } }
for _, mm in ipairs({ 2.5, 5, 10 }) do
    local band = Edge.px(mm, 300)
    for _, s in ipairs(screens) do
        local cx, cy = s.w / 2, s.h / 2
        local cases = {
            { "left", band - 1, cy, band, cy },
            { "right", s.w - band, cy, s.w - band - 1, cy },
            { "top", cx, band - 1, cx, band },
            { "bottom", cx, s.h - band, cx, s.h - band - 1 },
        }
        for _, c in ipairs(cases) do
            local label = string.format("%s mm, %s, %s edge", mm, s.name, c[1])
            assert(Edge.inBand(c[2], c[3], s.w, s.h, band), label .. ": just inside should pass through")
            assert(not Edge.inBand(c[4], c[5], s.w, s.h, band), label .. ": just outside should not")
        end
        -- The very edge and the corners are inside; the middle is not.
        assert(Edge.inBand(0, cy, s.w, s.h, band) and Edge.inBand(s.w - 1, s.h - 1, s.w, s.h, band))
        assert(Edge.inBand(0, 0, s.w, s.h, band), "corner")
        assert(not Edge.inBand(cx, cy, s.w, s.h, band), "middle")
    end
end
-- Edges follow the orientation: x = 1200 is 64 px from the right edge of a
-- portrait screen (1264 wide), inside a 10 mm band, but 480 px from it in
-- landscape (1680 wide).
assert(Edge.inBand(1200, 600, 1264, 1680, 118), "portrait: near the right edge")
assert(not Edge.inBand(1200, 600, 1680, 1264, 118), "landscape: far from it")

-- 0 mm never passes a tap through, not even at the very edge.
for _, s in ipairs(screens) do
    for _, p in ipairs({ { 0, 0 }, { 0, s.h / 2 }, { s.w - 1, s.h / 2 }, { s.w / 2, 0 }, { s.w / 2, s.h - 1 } }) do
        assert(not Edge.inBand(p[1], p[2], s.w, s.h, Edge.px(0, 300)), "0 mm at the edge")
    end
end
assert(not Edge.inBand(nil, 5, 100, 100, 10), "no position")
