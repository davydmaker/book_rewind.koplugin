local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")

local Cards = require("book_rewind/cards")
local CardView = require("book_rewind/ui/card_view")
local GeneratedCover = require("book_rewind/ui/generated_cover")
local I18n = require("book_rewind/i18n")
local Stats = require("book_rewind/stats")
local Store = require("book_rewind/store")

local Device_screen = Device.screen
local FULL_REFRESH_EVERY = 5
local NEW_YEAR_DAYS = 30
local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/book_rewind/ui/screen%.lua$", "")

local Screen = InputContainer:extend{
    name = "book_rewind_screen",
    covers_fullscreen = true,
    stop_events_propagation = true,
    db_path = nil,
    covers_db = nil,
    language = nil,
    schedule = nil,
    now = nil,
}

function Screen:init()
    -- The layout only fits portrait; odd rotation modes are landscape.
    local rotation = Device_screen:getRotationMode()
    if bit.band(rotation, 1) == 1 then
        self.restore_rotation = rotation
        Device_screen:setRotationMode(Device_screen.DEVICE_ROTATED_UPRIGHT)
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = Device_screen:getWidth(), h = Device_screen:getHeight() }
    self.width, self.height = self.dimen.w, self.dimen.h
    self.language = self.language or I18n.language_from(G_reader_settings and G_reader_settings:readSetting("language"))
    self.strings = I18n[self.language]
    self.db_path = self.db_path or (DataStorage:getSettingsDir() .. "/statistics.sqlite3")
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextCard = { { Device.input.group.PgFwd } },
            PreviousCard = { { Device.input.group.PgBack } },
        }
    end
    self.close_rect = CardView.close_rect(self.width, self.height)
    local meta_chunk = loadfile(PLUGIN_DIR .. "/_meta.lua")
    if meta_chunk then
        setfenv(meta_chunk, {})
        self.meta = meta_chunk()
    end
    self.covers_db = self.covers_db or (DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
    self.covers = {}
    self.cover_provider = function(book_id, max_w, max_h) return self:cached_cover(book_id, max_w, max_h) end
    self.years = Store.years(self.db_path, Cards.MIN_SECONDS)
    self.today = os.date("*t", self.now or os.time())
    self.current_year = self.today.year
    self.current_seconds = Store.year_seconds(self.db_path, self.current_year)
    self:open_year(self:first_year())
end

-- Early in a year, the one that just ended is the recap worth seeing.
function Screen:first_year()
    if self.years[1] == self.current_year and self.today.yday <= NEW_YEAR_DAYS then
        for _, year in ipairs(self.years) do
            if year == self.current_year - 1 then
                return year
            end
        end
    end
    return self.years[1] or self.current_year
end

function Screen:open_year(year)
    self.year = year
    self.export_label, self.export_footer = nil, nil
    self:free_covers()
    local data = Store.load_year(self.db_path, year, self.now)
    self.metrics = data and Stats.compute{
        year = year,
        rows = data.rows,
        books = data.books,
        earlier_pages = data.earlier_pages,
        earlier_reads = data.earlier_reads,
        read_later = data.read_later,
        last_read_before = data.last_read_before,
        last_year_seconds = data.last_year_seconds,
        previous_seconds = data.previous_seconds,
        now = self.now,
    }
    if not self.metrics or self.metrics.total_seconds < Cards.MIN_SECONDS then
        self:show_empty(year, self.metrics and self.metrics.total_seconds or 0)
        return
    end
    self.book_data = data.books
    self:rebuild_cards()
    self.mode = "cards"
    self.shown = 0
    self:show_card(1, "full")
end

function Screen:rebuild_cards()
    -- Only the neighbouring years: older on the left, newer on the right, like turning pages.
    local older, newer
    for _, other in ipairs(self.years) do
        if other < self.year and (not older or other > older) then
            older = other
        elseif other > self.year and (not newer or other < newer) then
            newer = other
        end
    end
    local other_years = {}
    if older then
        other_years[#other_years + 1] = { id = "year", year = older, label = "‹ " .. older, side = "left" }
    end
    if newer then
        other_years[#other_years + 1] = { id = "year", year = newer, label = newer .. " ›", side = "right" }
    end
    -- The newest cover says how close the current year is when it has too little reading to be listed.
    local notice
    if self.year == self.years[1] and self.year < self.current_year then
        notice = self.strings.cover_notice(Cards.minutes_missing(self.current_seconds), self.current_year)
    end
    self.cards = Cards.build(self.metrics, {
        notice = notice,
        strings = self.strings,
        meta = self.meta,
        in_progress = self.year == self.current_year,
        books = self.book_data,
        other_years = #other_years > 0 and other_years or nil,
    })
end

-- Returns a cover scaled to fit the box, with its size, or nil. A broken cover never stops the card.
function Screen:load_cover(book_id, max_w, max_h)
    local book = self.book_data and self.book_data[book_id]
    -- The cache is searched with the title as stored, and the generated cover shows the clean one.
    local display_title = book and Stats.clean_title(book.title, book.authors)
    if not display_title then
        return nil
    end
    local ok, cover = pcall(Store.load_cover, self.covers_db, book.title, book.authors)
    if not ok or not cover then
        return GeneratedCover.draw(display_title, book.authors, max_w, max_h)
    end
    local scale = math.min(max_w / cover:getWidth(), max_h / cover:getHeight())
    local w, h = math.max(1, math.floor(cover:getWidth() * scale)), math.max(1, math.floor(cover:getHeight() * scale))
    local scaled_ok, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, cover, w, h)
    if not scaled_ok or not scaled then
        cover:free()
        return GeneratedCover.draw(display_title, book.authors, max_w, max_h)
    end
    return scaled, w, h
end

-- Cards are repainted whenever they come back to the screen, so each cover is built only once per year.
function Screen:cached_cover(book_id, max_w, max_h)
    local key = string.format("%s:%dx%d", tostring(book_id), max_w, max_h)
    local entry = self.covers[key]
    if entry == nil then
        local cover, w, h = self:load_cover(book_id, max_w, max_h)
        entry = cover and { cover = cover, w = w, h = h } or false
        self.covers[key] = entry
    end
    if entry then
        return entry.cover, entry.w, entry.h
    end
end

function Screen:free_covers()
    for _, entry in pairs(self.covers) do
        if entry then
            entry.cover:free()
        end
    end
    self.covers = {}
end

function Screen:show_empty(year, seconds)
    self.mode = "empty"
    self.cards = nil
    local width = self.width - 2 * Device_screen:scaleBySize(30)
    local group = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{ text = self.strings.empty_title, face = Font:getFace("noto/NotoSerif-Bold.ttf", 30), width = width, alignment = "center" },
        VerticalSpan:new{ width = Device_screen:scaleBySize(16) },
        TextBoxWidget:new{
            text = self.strings.empty_body(Cards.minutes_missing(seconds), year),
            face = Font:getFace("noto/NotoSerif-Regular.ttf", 19),
            width = width,
            alignment = "center",
        },
        VerticalSpan:new{ width = Device_screen:scaleBySize(24) },
        Button:new{
            text = self.strings.close,
            width = width,
            padding_v = Device_screen:scaleBySize(10),
            radius = Device_screen:scaleBySize(8),
            bordersize = Device_screen:scaleBySize(2),
            callback = function() UIManager:close(self) end,
        },
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.width,
        height = self.height,
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, group },
    }
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
end

function Screen:footer(index)
    return string.format(self.strings.position, index, #self.cards)
end

function Screen:show_card(index, refresh)
    -- Black cards leave ghosts on e-ink, so going to or from one always redraws the whole panel.
    local crossing_dark = self.cards[index].dark or (self.index and self.cards[self.index] and self.cards[self.index].dark)
    self.index = index
    self.shown = self.shown + 1
    local mode = refresh or ((crossing_dark or self.shown % FULL_REFRESH_EVERY == 0) and "full" or "partial")
    UIManager:setDirty(self, function()
        return mode, self.dimen
    end)
end

function Screen:paintTo(bb, x, y)
    if self.mode ~= "cards" then
        InputContainer.paintTo(self, bb, x, y)
        return
    end
    self.dimen.x, self.dimen.y = x, y
    self.overflow = CardView.paint(bb, self.cards[self.index], {
        width = self.width,
        height = self.height,
        strings = self.strings,
        footer = self.cards[self.index].id == "summary" and self.export_footer or self:footer(self.index),
        button_labels = { export = self.export_label },
        cover = self.cover_provider,
        plugin_dir = PLUGIN_DIR,
    })
end

function Screen:go(delta)
    local target = self.index + delta
    if target >= 1 and target <= #self.cards then
        self:show_card(target)
    end
end

-- Saving blocks the screen for a moment. The result stays on the button, because taps made
-- during that time would dismiss a popup as soon as it appeared.
function Screen:start_export()
    if self.export_saving then
        return
    end
    self.export_saving = true
    self.export_label = self.strings.saving
    self:refresh_card()
    local schedule = self.schedule or function(callback)
        UIManager:scheduleIn(0.2, callback)
    end
    schedule(function()
        local ok, saved = pcall(self.export_images, self)
        self.export_saving = false
        if ok and saved > 0 then
            self.export_label = self.strings.saved_button(saved)
            -- The last two folders are enough to find it, and fit on the line.
            local short_path = self.export_dir:match("([^/]+/[^/]+)/?$") or self.export_dir
            self.export_footer = string.format(self.strings.saved_footer, short_path)
        else
            self.export_label = self.strings.save_failed
            self.export_footer = nil
        end
        self.ignore_input_until = os.time() + 1
        self:refresh_card()
    end)
end

function Screen:refresh_card()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function Screen:input_ignored()
    return self.export_saving or (self.ignore_input_until and os.time() <= self.ignore_input_until)
end

function Screen:export_images()
    local dir = require("ui/widget/screenshoter"):getScreenshotDir()
    util.makePath(dir)
    self.export_dir = dir
    local bb = Blitbuffer.new(self.width, self.height, Blitbuffer.TYPE_BB8)
    local saved = 0
    for index, card in ipairs(self.cards) do
        if not card.not_exported then
            local path = string.format("%s/book_rewind_%d_%02d.png", dir, self.year, index)
            local ok = pcall(function()
                CardView.paint(bb, card, { width = self.width, height = self.height, strings = self.strings, plugin_dir = PLUGIN_DIR, export = true, cover = self.cover_provider })
                bb:writePNG(path)
            end)
            if ok then
                saved = saved + 1
            end
        end
    end
    bb:free()
    return saved
end

local function inside(rect, pos)
    return pos.x >= rect.x and pos.x < rect.x + rect.w and pos.y >= rect.y and pos.y < rect.y + rect.h
end

function Screen:onTap(_, ges)
    if self.mode ~= "cards" then
        return false
    end
    if self:input_ignored() then
        return true
    end
    if inside(self.close_rect, ges.pos) then
        UIManager:close(self)
        return true
    end
    for _, rect in ipairs(CardView.layout_buttons(self.cards[self.index], self.width, self.height)) do
        if inside(rect, ges.pos) then
            if rect.id == "export" then
                self:start_export()
            elseif rect.id == "restart" then
                self.export_label, self.export_footer = nil, nil
                self:show_card(1, "full")
            elseif rect.id == "year" then
                self:open_year(rect.year)
            end
            return true
        end
    end
    self:go(ges.pos.x < self.width / 3 and -1 or 1)
    return true
end

function Screen:onSwipe(_, ges)
    if self.mode ~= "cards" then
        return false
    end
    if self:input_ignored() then
        return true
    end
    if ges.direction == "west" then
        self:go(1)
        return true
    elseif ges.direction == "east" then
        self:go(-1)
        return true
    end
    return false
end

function Screen:onNextCard()
    if self.mode ~= "cards" then
        return false
    end
    if not self:input_ignored() then
        self:go(1)
    end
    return true
end

function Screen:onPreviousCard()
    if self.mode ~= "cards" then
        return false
    end
    if not self:input_ignored() then
        self:go(-1)
    end
    return true
end

function Screen:onClose()
    if not self:input_ignored() then
        UIManager:close(self)
    end
    return true
end

function Screen:onSetRotationMode()
    return true
end

function Screen:onCloseWidget()
    self:free_covers()
    if self.restore_rotation then
        Device_screen:setRotationMode(self.restore_rotation)
    end
    UIManager:setDirty(nil, "full")
end

return Screen
