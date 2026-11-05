local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")

local Cards = require("book_rewind/cards")

local Screen = Device.screen

local SERIF = "noto/NotoSerif-Regular.ttf"
local BOLD = "noto/NotoSerif-Bold.ttf"
local ITALIC = "noto/NotoSerif-Italic.ttf"
local SANS = "noto/NotoSans-Bold.ttf"
local MONO = "droid/DroidSansMono.ttf"
local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local GRAY, LIGHT, DARK = Blitbuffer.COLOR_DARK_GRAY, Blitbuffer.COLOR_GRAY, Blitbuffer.gray(0.75)
local BASE_W, BASE_H = 600, 800

local UPPER = {
    ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í",
    ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ü"] = "Ü", ["ç"] = "Ç", ["ñ"] = "Ñ",
}

local function upper(text)
    return (text:upper():gsub("[\194-\244][\128-\191]*", function(char) return UPPER[char] or char end))
end

local clip = Cards.clip

local CardView = {}

-- All drawing uses the 600x800 design space, scaled and centered on the real screen.
local Canvas = {}
Canvas.__index = Canvas

local function new_canvas(bb, width, height)
    local scale = math.min(width / BASE_W, height / BASE_H)
    return setmetatable({
        bb = bb, width = width, height = height, scale = scale,
        ox = math.floor((width - BASE_W * scale) / 2),
        oy = math.floor((height - BASE_H * scale) / 2),
        overflow = false,
    }, Canvas)
end

function Canvas:x(v) return math.floor(self.ox + v * self.scale + 0.5) end
function Canvas:y(v) return math.floor(self.oy + v * self.scale + 0.5) end
function Canvas:len(v) return math.max(1, math.floor(v * self.scale + 0.5)) end

function Canvas:face(name, size)
    return Font:getFace(name, size * self.scale * 1000 / Screen:scaleBySize(1000))
end

function Canvas:rect(x0, y0, x1, y1, fill, outline, border)
    local x, y, w, h = self:x(x0), self:y(y0), self:x(x1) - self:x(x0), self:y(y1) - self:y(y0)
    if fill then
        self.bb:paintRect(x, y, w, h, fill)
    end
    if outline then
        self.bb:paintBorder(x, y, w, h, self:len(border or 2), outline)
    end
end

function Canvas:disc(cx, cy, r, color)
    self.bb:paintCircle(self:x(cx), self:y(cy), self:len(r), color)
end

function Canvas:ring(cx, cy, r, color, border)
    self.bb:paintCircle(self:x(cx), self:y(cy), self:len(r), color, self:len(border))
end

-- Scanline fill. Blitbuffer has no polygons, and these are small, so this stays cheap.
function Canvas:poly(points, color)
    local real = {}
    local top, bottom = math.huge, -math.huge
    for i, p in ipairs(points) do
        real[i] = { self.ox + p[1] * self.scale, self.oy + p[2] * self.scale }
        top, bottom = math.min(top, real[i][2]), math.max(bottom, real[i][2])
    end
    for y = math.floor(top), math.ceil(bottom) do
        local crossings = {}
        for i, a in ipairs(real) do
            local b = real[i % #real + 1]
            if (a[2] <= y and b[2] > y) or (b[2] <= y and a[2] > y) then
                crossings[#crossings + 1] = a[1] + (y - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
            end
        end
        table.sort(crossings)
        for i = 1, #crossings - 1, 2 do
            local x0 = math.floor(crossings[i] + 0.5)
            local width = math.floor(crossings[i + 1] + 0.5) - x0
            if width > 0 then
                self.bb:paintRect(x0, y, width, 1, color)
            end
        end
    end
end

function Canvas:line(points, color, width)
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            local nx, ny = -dy / length * width / 2, dx / length * width / 2
            self:poly({ { a[1] + nx, a[2] + ny }, { b[1] + nx, b[2] + ny }, { b[1] - nx, b[2] - ny }, { a[1] - nx, a[2] - ny } }, color)
        end
    end
end

function Canvas:hatch(x0, y0, x1, y1, spacing)
    local left, top, right, bottom = self:x(x0), self:y(y0), self:x(x1), self:y(y1)
    local step = math.max(3, self:len(spacing or 6))
    local thick = self:len(1.4)
    for y = top, bottom - 1 do
        local x = left + (bottom - y) % step
        while x < right do
            self.bb:paintRect(x, y, math.min(thick, right - x), 1, BLACK)
            x = x + step
        end
    end
end

function Canvas:dots(x0, y0, x1, y1, spacing, radius, inside)
    local row, y = 0, y0
    while y <= y1 do
        local x = x0 + (row % 2 == 1 and spacing / 2 or 0)
        while x <= x1 do
            if not inside or inside(x, y) then
                self.bb:paintCircle(self:x(x), self:y(y), math.max(1, self:len(radius)), BLACK)
            end
            x = x + spacing
        end
        y = y + spacing * 0.87
        row = row + 1
    end
end

function Canvas:measure(text, name, size)
    local widget = TextWidget:new{ text = text, face = self:face(name, size) }
    local width = widget:getSize().w
    widget:free()
    return width / self.scale
end

-- anchor: "c" centered, "l" from the left, "r" from the right. y is the vertical center.
function Canvas:text(x, y, text, name, size, color, anchor)
    local widget = TextWidget:new{ text = text, face = self:face(name, size), fgcolor = color or BLACK }
    local measured = widget:getSize()
    local px = self:x(x)
    if anchor == "r" then
        px = px - measured.w
    elseif anchor ~= "l" then
        px = px - math.floor(measured.w / 2)
    end
    widget:paintTo(self.bb, px, self:y(y) - math.floor(measured.h / 2))
    widget:free()
end

function Canvas:fit_size(text, name, sizes, width)
    for _, size in ipairs(sizes) do
        if self:measure(text, name, size) <= width then
            return size
        end
    end
end

-- The largest size that fits on one line, or two wrapped lines at the smallest size.
function Canvas:fit(x, y, text, name, sizes, width, color, anchor)
    local size = self:fit_size(text, name, sizes, width)
    if size then
        self:text(x, y, text, name, size, color, anchor)
    elseif anchor == "l" or anchor == "r" then
        -- Text anchored to a side has no room to wrap around its x, so it stays on one line.
        local smallest = sizes[#sizes]
        local length = 0
        for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            length = length + 1
        end
        -- The longest clip that fits, found in a few measures instead of one per character.
        local low, high, short = 1, length - 1, clip(text, 1)
        while low <= high do
            local middle = math.floor((low + high) / 2)
            local candidate = clip(text, middle)
            if self:measure(candidate, name, smallest) <= width then
                low, short = middle + 1, candidate
            else
                high = middle - 1
            end
        end
        self:text(x, y, short, name, smallest, color, anchor)
    else
        self:wrap(x, y - sizes[#sizes] * 0.7, text, name, sizes[#sizes], width, color, nil, sizes[#sizes] * 3)
    end
end

function Canvas:wrap(x, y, text, name, size, width, color, background, max_height)
    local widget = TextBoxWidget:new{
        text = text,
        face = self:face(name, size),
        width = self:len(width),
        alignment = "center",
        fgcolor = color or BLACK,
        bgcolor = background or WHITE,
    }
    local height = widget:getSize().h / self.scale
    if max_height and height > max_height then
        self.overflow = true
    end
    widget:paintTo(self.bb, self:x(x - width / 2), self:y(y))
    widget:free()
    return height
end

function Canvas:art(plugin_dir, name, dark)
    self.bb:paintRect(0, 0, self.width, self.height, dark and BLACK or WHITE)
    if not name then
        return
    end
    local set = self.width <= 760 and "600" or "1200"
    local image = ImageWidget:new{
        file = string.format("%s/assets/cards/%s/%s.png", plugin_dir, set, name),
        width = self:len(BASE_W),
        height = self:len(BASE_H),
    }
    image:paintTo(self.bb, self.ox, self.oy)
    image:free()
end

-- Draws a book cover fitted inside the box. Returns false when the book has no cover. The provider owns the cover.
function Canvas:cover(provider, book_id, x, y, w, h, frame, frame_color)
    if not provider then
        return false
    end
    local box_w, box_h = self:len(w), self:len(h)
    local cover, cover_w, cover_h = provider(book_id, box_w, box_h)
    if not cover then
        return false
    end
    local px = self:x(x) + math.floor((box_w - cover_w) / 2)
    local py = self:y(y) + math.floor((box_h - cover_h) / 2)
    self.bb:blitFrom(cover, px, py, 0, 0, cover_w, cover_h)
    if frame then
        self.bb:paintBorder(px, py, cover_w, cover_h, self:len(frame), frame_color or BLACK)
    end
    return true
end

local function spine(c, x, base, w, h, tone)
    c:rect(x, base - h, x + w, base, tone == "black" and BLACK or WHITE, BLACK, 2)
    if tone == "hatch" then
        c:hatch(x + 2, base - h + 2, x + w - 2, base - 2)
    elseif tone == "dots" then
        c:dots(x + 4, base - h + 4, x + w - 4, base - 4, 6, 1.7)
    end
    if w >= 16 then
        local ink = tone == "black" and WHITE or BLACK
        c:rect(x + 3, base - h + 12, x + w - 3, base - h + 15, ink)
        c:rect(x + 3, base - h + 20, x + w - 3, base - h + 22, ink)
    end
end

local Paint = {}

function Paint.cover(c, card)
    c:rect(40, 128, 180, 132, BLACK)
    c:fit(40, 110, upper(card.kicker), SANS, { 20, 17, 15 }, 200, BLACK, "l")
    local halo = 4
    for dx = -halo, halo, halo do
        for dy = -halo, halo, halo do
            c:text(300 + dx, 330 + dy, card.big, BOLD, 165, WHITE)
        end
    end
    c:text(300, 330, card.big, BOLD, 165, BLACK)
    c:text(300, 452, card.label, ITALIC, 32)
    if card.body then
        c:wrap(300, 490, card.body, SERIF, 18, 480, BLACK, WHITE, 60)
    end
end

function Paint.time(c, card)
    c:text(300, 430, card.kicker, ITALIC, 24, WHITE)
    c:fit(300, 505, card.big, BOLD, { 66, 56, 46 }, 540, WHITE)
    c:text(300, 575, card.label, SERIF, 24, WHITE)
    if card.body then
        c:wrap(300, 610, card.body, SERIF, 19, 500, WHITE, BLACK, 90)
    end
end

function Paint.pages(c, card)
    c:text(300, 165, card.kicker, ITALIC, 24)
    c:fit(300, 240, card.big, BOLD, { 94, 76, 60 }, 350, BLACK)
    c:text(300, 312, card.label, SERIF, 26)
    if card.body then
        c:wrap(300, 620, card.body, SERIF, 24, 400, BLACK, WHITE, 120)
    end
end

local function shelf_rows(books)
    local gap, row_width, limit = 5, 520, 12
    local total = 0
    local items = {}
    for i = 1, math.min(limit, #books) do
        local w = math.max(38, math.min(112, books[i].total_pages / 6))
        items[i] = { book = books[i], w = w }
        total = total + w + gap
    end
    local factor = math.min(1, (2 * row_width - 40) / math.max(total, 1))
    local rows, used = { {}, {} }, 0
    local row = 1
    for _, item in ipairs(items) do
        item.w = math.max(16, item.w * factor)
        if used + item.w > row_width and row == 1 then
            row, used = 2, 0
        end
        if used + item.w <= row_width then
            table.insert(rows[row], item)
            used = used + item.w + gap
        end
    end
    return rows, gap
end

function Paint.timeline(c, card, t, provider)
    c:text(300, 62, card.kicker, ITALIC, 24)
    c:fit(300, 105, card.label, BOLD, { 30, 25, 20 }, 480)
    local top, row_h = 145, 51
    local axis = 92
    c:rect(axis - 1, top + 6, axis + 1, top + 12 * row_h - 12, BLACK)
    for month = 1, 12 do
        local y = top + (month - 1) * row_h + row_h / 2
        local books = card.months_books[month]
        c:text(70, y, (clip(t.months[month], 3):gsub("…$", "")), #books > 0 and BOLD or SERIF, 15, BLACK, "r")
        if #books > 0 then
            c:disc(axis, y, 6, BLACK)
        else
            c:disc(axis, y, 3, BLACK)
        end
        local x = 112
        for index, book in ipairs(books) do
            if x > 530 then
                c:text(x, y, "+" .. (#books - index + 1), BOLD, 15, BLACK, "l")
                break
            end
            if not c:cover(provider, book.id, x, y - 22, 34, 44, 1) then
                c:rect(x + 6, y - 22, x + 28, y + 22, BLACK)
                c:rect(x + 9, y - 14, x + 25, y - 12, WHITE)
                c:rect(x + 9, y - 8, x + 25, y - 6, WHITE)
            end
            x = x + 40
            if #books == 1 and book.title then
                c:fit(x + 4, y, clip(book.title, 34), SERIF, { 16, 14, 12 }, 560 - x - 4, BLACK, "l")
            end
        end
    end
end

function Paint.devoured(c, card, _, provider)
    c:text(300, 62, card.kicker, ITALIC, 24)
    if not c:cover(provider, card.book_id, 180, 90, 240, 340, 2) then
        c:rect(202, 96, 398, 424, BLACK)
        c:rect(218, 96, 222, 424, WHITE)
        c:rect(240, 150, 380, 154, WHITE)
        c:rect(240, 166, 380, 168, WHITE)
        c:rect(240, 370, 380, 372, WHITE)
    end
    c:fit(300, 475, clip(card.title, 40), BOLD, { 26, 22, 18 }, 530)
    c:fit(300, 560, card.big, BOLD, { 70, 58, 46 }, 530)
    c:text(300, 640, card.body, SERIF, 24)
end

function Paint.books(c, card, t, provider)
    c:text(300, 90, card.kicker, ITALIC, 24)
    c:fit(300, 148, card.big .. " " .. card.label, BOLD, { 62, 52, 42 }, 540)
    if card.body then
        c:text(300, 208, card.body, SERIF, 22)
    end
    local rows, gap = shelf_rows(card.books)
    local shelf_has_earlier = false
    local base = #rows[2] > 0 and 400 or 480
    -- With covers to show, the first shelf stays and the covers take the place of the second one.
    local covers_drawn = 0
    if provider and card.books[1].title then
        covers_drawn = #card.ranks
        rows[2] = {}
        base = 400
    end
    for _, row in ipairs(rows) do
        if #row == 0 then
            break
        end
        local x = 46
        for _, item in ipairs(row) do
            local h = 110 + item.book.total_pages % 37
            local tone = item.book.finished and "black" or (item.book.finished_earlier and "dots" or "hatch")
            shelf_has_earlier = shelf_has_earlier or tone == "dots"
            spine(c, x, base, item.w, h, tone)
            x = x + item.w + gap
        end
        c:rect(30, base, 570, base + 6, BLACK)
        base = base + 190
    end
    if covers_drawn > 0 then
        local width = 130
        local x0 = 300 - (covers_drawn * width + (covers_drawn - 1) * 14) / 2
        for i, rank in ipairs(card.ranks) do
            c:cover(provider, rank.book_id, x0 + (i - 1) * (width + 14), 422, width, 185, 1)
        end
    end
    local top = card.ranks[1]
    c:fit(300, 628, clip(top.title or "", 40), BOLD, { 21, 18, 15 }, 530)
    c:text(300, 660, top.meta, ITALIC, 17)
    local first_x, second_x = 150, 330
    if shelf_has_earlier then
        first_x, second_x = 30, 210
        c:rect(390, 692, 424, 714, WHITE, BLACK, 1.5)
        c:dots(394, 696, 420, 710, 6, 1.7)
        c:text(434, 703, t.finished_earlier_legend, SERIF, 15, BLACK, "l")
    end
    c:rect(first_x, 692, first_x + 34, 714, BLACK)
    c:text(first_x + 44, 703, t.finished_legend, SERIF, 15, BLACK, "l")
    c:rect(second_x, 692, second_x + 34, 714, WHITE, BLACK, 1.5)
    c:hatch(second_x + 1, 693, second_x + 33, 713)
    c:text(second_x + 44, 703, t.abandoned_legend, SERIF, 15, BLACK, "l")
end

function Paint.author(c, card)
    c:text(320, 190, card.kicker, ITALIC, 24)
    c:fit(300, 300, clip(card.big_text, 40), BOLD, { 54, 44, 36, 28 }, 520)
    c:text(300, 362, card.label, SERIF, 22)
    for i, rank in ipairs(card.ranks or {}) do
        local y = 400 + i * 70
        c:ring(90, y, 22, BLACK, 2)
        c:text(90, y, tostring(i + 1), BOLD, 22)
            c:fit(130, y - 12, clip(rank.title, 40), BOLD, { 21, 18, 15 }, 430, BLACK, "l")
        c:text(130, y + 16, rank.meta, ITALIC, 16, BLACK, "l")
    end
end

local function heat_shade(ratio)
    if ratio < 0.15 then return LIGHT end
    if ratio < 0.3 then return GRAY end
    if ratio < 0.5 then return DARK end
    return BLACK
end

function Paint.streak(c, card, t)
    local metrics = card.metrics
    c:text(300, 100, card.kicker, ITALIC, 24)
    c:text(300, 190, card.big, BOLD, 130)
    c:text(300, 285, card.label, SERIF, 25)
    local cell_w, cell_h, gap = 9, 18, 1
    local x0, y0 = (BASE_W - 53 * (cell_w + gap)) / 2, 350
    local jan1 = os.date("*t", os.time{ year = card.year, month = 1, day = 1, hour = 12 })
    local offset = jan1.wday - 1
    local days_in_year = os.date("*t", os.time{ year = card.year, month = 12, day = 31, hour = 12 }).yday
    local maximum = 1
    for _, seconds in pairs(metrics.days) do
        maximum = math.max(maximum, seconds)
    end
    for yday = 1, days_in_year do
        local position = yday - 1 + offset
        local x = x0 + math.floor(position / 7) * (cell_w + gap)
        local y = y0 + position % 7 * (cell_h + gap)
        local seconds = metrics.days[yday]
        if seconds then
            c:rect(x, y, x + cell_w - 1, y + cell_h - 1, heat_shade(seconds / maximum))
        else
            c:rect(x, y, x + cell_w - 1, y + cell_h - 1, WHITE, LIGHT, 1)
        end
    end
    for month = 1, 12 do
        local yday = os.date("*t", os.time{ year = card.year, month = month, day = 1, hour = 12 }).yday
        local position = yday - 1 + offset
        c:text(x0 + math.floor(position / 7) * (cell_w + gap) + 5, y0 - 16, t.month_letters[month], SERIF, 13)
    end
    local last = metrics.longest_streak_end
    local first = last - metrics.longest_streak + 1
    local bracket_y = y0 + 7 * (cell_h + gap)
    local left = x0 + math.floor((first - 1 + offset) / 7) * (cell_w + gap) - 3
    local right = x0 + (math.floor((last - 1 + offset) / 7) + 1) * (cell_w + gap) + 2
    c:line({ { left, bracket_y + 4 }, { left, bracket_y + 12 }, { right, bracket_y + 12 }, { right, bracket_y + 4 } }, BLACK, 2.4)
    local label_x = math.max(60, math.min(540, (left + right) / 2))
    c:text(label_x, bracket_y + 32, string.format(t.heat_streak, metrics.longest_streak), ITALIC, 16)
    c:wrap(300, 572, t.heat_hint, SERIF, 19, 480, BLACK, WHITE, 70)
    c:text(300, 690, string.format(t.heat_total, metrics.days_read), BOLD, 26)
end

function Paint.best_day(c, card, t)
    c:fit(40, 62, card.kicker, ITALIC, { 30, 24 }, 430, BLACK, "l")
    c:text(295, 170, upper(t.months[card.date.month]), SANS, 40, WHITE)
    c:text(295, 365, tostring(card.date.day), BOLD, 165)
    c:text(295, 510, t.weekdays[card.date.wday], ITALIC, 26)
    c:fit(300, 695, card.label, BOLD, { 26, 22, 18 }, 440)
end

function Paint.session(c, card)
    local cx, cy = 300, 390
    c:text(cx, cy - 92, card.kicker, ITALIC, 22)
    c:fit(cx, cy - 18, card.big, BOLD, { 72, 60, 50, 42 }, 330)
    c:text(cx, cy + 50, card.label, SERIF, 18)
    if card.body then
        c:wrap(cx, cy + 74, clip(card.body, 44), BOLD, 16, 270, BLACK, WHITE, 50)
    end
end

function Paint.hours(c, card, t)
    c:text(60, 100, card.kicker, ITALIC, 25, WHITE, "l")
    c:fit(60, 158, card.big_text, BOLD, { 62, 50, 40, 32 }, 370, WHITE, "l")
    c:fit(60, 212, card.label, SERIF, { 18, 15 }, 370, WHITE, "l")
    local cx, cy, inner, outer = 300, 490, 92, 225
    c:ring(cx, cy, inner, WHITE, 2)
    local peak = 1
    for hour = 0, 23 do
        peak = math.max(peak, card.hour_values[hour])
    end
    local spread = math.rad(5.5)
    for hour = 0, 23 do
        local seconds = card.hour_values[hour]
        local angle = math.rad(hour * 15 - 90)
        local r0 = inner + 6
        local r1 = r0 + (seconds > 0 and (outer - inner - 6) * seconds / peak or 2)
        c:poly({
            { cx + r0 * math.cos(angle - spread), cy + r0 * math.sin(angle - spread) },
            { cx + r1 * math.cos(angle - spread), cy + r1 * math.sin(angle - spread) },
            { cx + r1 * math.cos(angle + spread), cy + r1 * math.sin(angle + spread) },
            { cx + r0 * math.cos(angle + spread), cy + r0 * math.sin(angle + spread) },
        }, hour == card.best_hour and WHITE or LIGHT)
    end
    for _, hour in ipairs({ 0, 6, 12, 18 }) do
        local angle = math.rad(hour * 15 - 90)
        c:text(cx + 238 * math.cos(angle), cy + 238 * math.sin(angle), tostring(hour), SERIF, 15, WHITE)
    end
    c:text(cx, cy - 14, t.hour(card.best_hour), BOLD, 40, WHITE)
    c:text(cx, cy + 26, t.hours_center, ITALIC, 15, WHITE)
end

function Paint.weekdays(c, card)
    c:text(300, 110, card.kicker, ITALIC, 24)
    c:fit(300, 180, card.big_text, BOLD, { 66, 54, 44 }, 520)
    local base, peak = 710, 400
    local gap, w = 8, 66
    local x0 = (BASE_W - (7 * w + 6 * gap)) / 2
    local largest = 1
    for _, bar in ipairs(card.bars) do
        largest = math.max(largest, bar.value)
    end
    for i, bar in ipairs(card.bars) do
        local h = math.max(36, peak * bar.value / largest)
        local x = x0 + (i - 1) * (w + gap)
        spine(c, x, base, w, h, bar.highlight and "black" or ((i == 1 or i == 7) and "dots" or "hatch"))
        c:text(x + w / 2, base + 26, bar.label, SERIF, 16)
    end
    c:rect(20, base, 580, base + 5, BLACK)
end

function Paint.months(c, card)
    c:text(300, 110, card.kicker, ITALIC, 24)
    c:fit(300, 180, card.big_text, BOLD, { 70, 56, 44 }, 520)
    c:text(300, 250, card.label, SERIF, 22)
    local base, peak = 700, 330
    local step = (BASE_W - 60) / 11
    local largest = 1
    for _, bar in ipairs(card.bars) do
        largest = math.max(largest, bar.value)
    end
    local points = {}
    for i, bar in ipairs(card.bars) do
        points[i] = { 30 + (i - 1) * step, base - 25 - peak * bar.value / largest }
    end
    local outline = { { 0, points[1][2] } }
    for _, point in ipairs(points) do
        outline[#outline + 1] = point
    end
    outline[#outline + 1] = { BASE_W, points[#points][2] }
    local function surface_y(x)
        for i = 1, #outline - 1 do
            local a, b = outline[i], outline[i + 1]
            if x >= a[1] and x <= b[1] then
                return a[2] + (x - a[1]) / (b[1] - a[1]) * (b[2] - a[2])
            end
        end
        return base
    end
    c:dots(0, 270, BASE_W, base - 3, 7, 2.1, function(x, y) return y > surface_y(x) + 3 end)
    c:line(outline, BLACK, 3.4)
    for i, bar in ipairs(card.bars) do
        if bar.highlight then
            local fx, fy = points[i][1], points[i][2]
            c:line({ { fx, fy }, { fx, fy - 70 } }, BLACK, 3.4)
            local flag_dir = fx > 500 and -1 or 1
            c:poly({ { fx, fy - 70 }, { fx + 48 * flag_dir, fy - 56 }, { fx, fy - 42 } }, BLACK)
            c:disc(fx, fy, 6, BLACK)
            c:disc(fx, fy, 3, WHITE)
        end
        c:text(30 + (i - 1) * step, base + 24, bar.label, bar.highlight and BOLD or SERIF, 15)
    end
    c:rect(0, base, BASE_W, base + 4, BLACK)
end

function Paint.speed(c, card)
    c:text(300, 110, card.kicker, ITALIC, 26)
    local cx, cy, r = 300, 480, 240
    for _, value in ipairs({ 0, 50, 100 }) do
        local angle = math.rad(180 + value * 1.8)
        c:text(cx + (r - 92) * math.cos(angle), cy + (r - 92) * math.sin(angle) + 4, tostring(value), SERIF, 17)
    end
    local angle = math.rad(180 + math.min(card.speed, 100) * 1.8)
    c:poly({
        { cx + 170 * math.cos(angle), cy + 170 * math.sin(angle) },
        { cx + 13 * math.cos(angle + 1.57), cy + 13 * math.sin(angle + 1.57) },
        { cx + 13 * math.cos(angle - 1.57), cy + 13 * math.sin(angle - 1.57) },
    }, BLACK)
    c:disc(cx, cy, 20, BLACK)
    c:disc(cx, cy, 7, WHITE)
    c:text(cx, cy + 90, card.big, BOLD, 96)
    c:text(cx, cy + 170, card.label, SERIF, 26)
    if card.body then
        c:text(cx, cy + 215, card.body, ITALIC, 18)
    end
end

-- A small fixed sequence, so the piles look the same every time the card opens.
local function pile(c, cx, count, base, palette)
    local tones = palette or { "black", "white", "dots", "black", "hatch", "white" }
    local seed = 12
    local function next_value(low, high)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return low + seed % (high - low + 1)
    end
    local y = base
    for i = 1, count do
        local w, h = next_value(120, 180), next_value(19, 28)
        local x = cx - w / 2 + next_value(0, 18) - 9
        local tone = tones[(i - 1) % #tones + 1]
        c:rect(x, y - h, x + w, y, tone == "black" and BLACK or WHITE, BLACK, 2)
        if tone == "hatch" then
            c:hatch(x + 2, y - h + 2, x + w - 2, y - 2)
        elseif tone == "dots" then
            c:dots(x + 5, y - h + 5, x + w - 5, y - 5, 6, 1.7)
        else
            c:rect(x + 8, y - h + 5, x + 11, y - 5, tone == "black" and WHITE or BLACK)
        end
        y = y - h
    end
end

function Paint.previous(c, card)
    c:fit(300, 90, card.kicker, ITALIC, { 24, 20, 17 }, 540)
    c:fit(300, 170, card.big, BOLD, { 100, 80, 60 }, 540)
    c:text(300, 245, card.label, SERIF, 23)
    local base = 720
    local largest = math.max(card.current_seconds, card.previous_seconds)
    local function count(seconds)
        return math.max(1, math.floor(15 * seconds / largest + 0.5))
    end
    pile(c, 160, count(card.previous_seconds), base)
    pile(c, 430, count(card.current_seconds), base)
    c:rect(20, base, 580, base + 4, BLACK)
    c:text(160, base + 22, tostring(card.year - 1), BOLD, 17)
    c:text(160, base + 44, Cards.duration(card.previous_seconds), ITALIC, 15)
    c:text(430, base + 22, tostring(card.year), BOLD, 17)
    c:text(430, base + 44, Cards.duration(card.current_seconds), ITALIC, 15)
end

function Paint.archetype(c, card)
    c:text(300, 60, card.kicker, ITALIC, 24)
    c:fit(300, 531, upper(card.big_text), BOLD, { 42, 34, 28, 22 }, 330)
    if card.secondary then
        c:fit(300, 603, card.secondary, ITALIC, { 16, 14, 12 }, 510)
    end
    c:wrap(300, 622, card.body, SERIF, 20, 510, BLACK, WHITE, 130)
end

function Paint.summary(c, card, t)
    c:fit(300, 136, string.format(t.summary_title, card.year), MONO, { 22, 18, 15 }, 460)
    local y = 194
    for _, rank in ipairs(card.ranks) do
        c:text(76, y, upper(rank.title), MONO, 15, BLACK, "l")
        local label_width = c:measure(upper(rank.title), MONO, 15)
        c:fit(524, y, clip(rank.meta, 34), BOLD, { 20, 17, 14, 12 }, 448 - label_width - 12, BLACK, "r")
        c:rect(76, y + 26, 524, y + 27, GRAY)
        y = y + 50
    end
    if y > 548 then
        c.overflow = true
    end
    c:fit(160, 581, t.stamp, SANS, { 18, 15, 13 }, 60)
    c:text(160, 602, tostring(card.year), SANS, 13)
end

function Paint.about(c, card, t)
    local meta = card.meta
    local function bare(url)
        return (url:gsub("^https?://", ""):gsub("/$", ""))
    end
    c:text(300, 100, t.about_kicker, ITALIC, 24)
    c:fit(300, 170, meta.fullname, BOLD, { 56, 46 }, 520)
    c:text(300, 228, string.format(t.about_version, meta.version), ITALIC, 18)
    c:rect(50, 258, 550, 260, BLACK)
    c:text(300, 296, string.format(t.about_by, meta.author), SERIF, 20)
    c:text(300, 326, bare(meta.website), SERIF, 17)
    c:text(300, 354, meta.copyright, SERIF, 16)
    c:text(300, 410, t.about_source, BOLD, 19)
    c:fit(300, 440, bare(meta.homepage), SERIF, { 17, 15, 13 }, 530)
    c:text(300, 496, t.about_license_title, BOLD, 19)
    c:wrap(300, 518, t.about_license, SERIF, 16, 500, BLACK, WHITE, 120)
    c:text(300, 680, t.about_warranty, ITALIC, 16)
end

require("book_rewind/ui/wildcard_paint")(Paint, {
    BLACK = BLACK, WHITE = WHITE, GRAY = GRAY, LIGHT = LIGHT,
    SERIF = SERIF, BOLD = BOLD, ITALIC = ITALIC, SANS = SANS,
    spine = spine, pile = pile, clip = clip, upper = upper,
})

local function button_box(c, rect, label)
    c:rect(rect.dx0, rect.dy0, rect.dx1, rect.dy1, WHITE, BLACK, 2)
    c:fit((rect.dx0 + rect.dx1) / 2, (rect.dy0 + rect.dy1) / 2, label, BOLD, { 18, 15, 13 }, rect.dx1 - rect.dx0 - 12)
end

function CardView.layout_buttons(card, width, height)
    local rects = {}
    if not card.buttons then
        return rects
    end
    local c = new_canvas(nil, width, height)
    for i, button in ipairs(card.buttons) do
        local dx0, dy0, dx1, dy1
        -- What can be tapped may be larger than what is drawn.
        local hit_x0, hit_y0, hit_x1, hit_y1
        if button.side then
            dy0, dy1 = 769, 797
            if button.side == "left" then
                dx0, dx1 = 8, 104
                hit_x0, hit_x1 = 0, 150
            else
                dx0, dx1 = 496, 592
                hit_x0, hit_x1 = 450, BASE_W
            end
            hit_y0, hit_y1 = 730, BASE_H
        else
            dx0, dy0 = 30, 668 + (i - 1) * 50
            dx1, dy1 = 570, dy0 + 42
            hit_x0, hit_y0, hit_x1, hit_y1 = dx0, dy0, dx1, dy1
        end
        rects[i] = {
            id = button.id, year = button.year, label = button.label,
            dx0 = dx0, dy0 = dy0, dx1 = dx1, dy1 = dy1,
            x = c:x(hit_x0), y = c:y(hit_y0), w = c:x(hit_x1) - c:x(hit_x0), h = c:y(hit_y1) - c:y(hit_y0),
        }
    end
    return rects
end

function CardView.close_rect(width, height)
    local c = new_canvas(nil, width, height)
    return { x = c:x(504), y = c:y(8), w = c:x(592) - c:x(504), h = c:y(56) - c:y(8) }
end

-- What stays on the screen when a card cannot be drawn: a short message, the way out and the position.
function CardView.paint_error(bb, opts)
    local c = new_canvas(bb, opts.width, opts.height)
    bb:paintRect(0, 0, opts.width, opts.height, WHITE)
    c:wrap(300, 360, opts.strings.card_failed, SERIF, 22, 480, BLACK, WHITE)
    c:rect(504, 12, 590, 52, WHITE, BLACK, 2)
    c:fit(547, 32, opts.strings.close, BOLD, { 15, 13, 11 }, 78, BLACK)
    if opts.footer then
        c:fit(300, 780, opts.footer, ITALIC, { 14, 12, 10 }, 560, BLACK)
    end
end

function CardView.paint(bb, card, opts)
    local c = new_canvas(bb, opts.width, opts.height)
    c:art(opts.plugin_dir, card.art, card.dark)
    Paint[card.id](c, card, opts.strings, opts.cover)
    if not opts.export then
        if card.notice then
            c:wrap(300, 490, card.notice, SERIF, 18, 480, BLACK, WHITE, 60)
        end
        for _, rect in ipairs(CardView.layout_buttons(card, opts.width, opts.height)) do
            button_box(c, rect, opts.button_labels and opts.button_labels[rect.id] or rect.label)
        end
        local ink, background = card.dark and WHITE or BLACK, card.dark and BLACK or WHITE
        c:rect(504, 12, 590, 52, background, ink, 2)
        c:fit(547, 32, opts.strings.close, BOLD, { 15, 13, 11 }, 78, ink)
        if opts.footer then
            local width = math.min(c:measure(opts.footer, ITALIC, 14), 560) + 16
            c:rect(300 - width / 2, 768, 300 + width / 2, 792, background)
            c:fit(300, 780, opts.footer, ITALIC, { 14, 12, 10 }, 560, ink)
        end
    end
    return c.overflow
end

return CardView
