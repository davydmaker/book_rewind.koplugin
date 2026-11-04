local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")

local GeneratedCover = {}

local BASE_W, BASE_H = 300, 440
local MIN_WIDTH_FOR_TEXT = 60

local function style_for(title)
    local sum = 0
    for i = 1, #title do
        sum = (sum * 31 + title:byte(i)) % 1000003
    end
    return sum
end

-- An old book look: title at the top and author at the bottom, for books with no cover in the cache.
function GeneratedCover.draw(title, authors, max_w, max_h)
    local scale = math.min(max_w / BASE_W, max_h / BASE_H)
    local w, h = math.max(1, math.floor(BASE_W * scale)), math.max(1, math.floor(BASE_H * scale))
    local seed = style_for(title)
    local style = seed % 4
    local dark = style == 0 or style == 2
    local paper
    if dark then
        paper = Blitbuffer.Color8(seed % 8 < 4 and 34 or 68)
    else
        paper = Blitbuffer.Color8(seed % 8 < 4 and 238 or 204)
    end
    local ink = dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local cover = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    cover:fill(paper)
    local function px(value)
        return math.max(1, math.floor(value * scale + 0.5))
    end
    if style == 0 then
        cover:paintRect(0, px(300), w, px(8), ink)
        cover:paintRect(0, px(316), w, px(2), ink)
    elseif style == 1 then
        cover:paintBorder(px(14), px(14), w - 2 * px(14), h - 2 * px(14), px(4), ink)
    elseif style == 2 then
        cover:paintCircle(math.floor(w / 2), px(310), px(64), ink)
        cover:paintCircle(math.floor(w / 2), px(310), px(48), paper)
    else
        cover:paintRect(0, 0, px(26), h, ink)
    end
    if w < MIN_WIDTH_FOR_TEXT then
        cover:paintRect(px(50), px(70), w - 2 * px(50), px(16), ink)
        cover:paintRect(px(80), px(100), w - 2 * px(80), px(10), ink)
        return cover, w, h
    end
    local unscale = 1000 / Device.screen:scaleBySize(1000)
    local function text(content, face, size, y)
        local box = TextBoxWidget:new{
            text = content,
            face = Font:getFace(face, size * scale * unscale),
            width = w - 2 * px(32),
            alignment = "center",
            fgcolor = ink,
            bgcolor = paper,
        }
        box:paintTo(cover, px(32), y)
        box:free()
    end
    local short_title = title:gsub(":.*$", "")
    text(short_title, "noto/NotoSerif-Bold.ttf", 24, px(56))
    local author = type(authors) == "string" and authors:match("^[^\n]+")
    if author and author ~= "N/A" then
        text(author, "noto/NotoSerif-Italic.ttf", 15, px(385))
    end
    return cover, w, h
end

return GeneratedCover
