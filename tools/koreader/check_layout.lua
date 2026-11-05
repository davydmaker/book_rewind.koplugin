local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("screenshot_dir", out_dir .. "/exported")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/tools/koreader/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local SampleDb = require("sample_db")
local RecapScreen = require("book_rewind/ui/screen")

local problems = 0
local function problem(text)
    problems = problems + 1
    print("PROBLEM: " .. text)
end
local function shot(widget, name)
    widget:paintTo(Screen.bb, 0, 0)
    Screen.bb:writePNG(out_dir .. "/" .. name .. ".png")
end
local function tap(screen, x, y)
    screen:onTap(nil, { pos = { x = x, y = y } })
end

local year = tonumber(os.date("%Y"))
-- A fixed day, so the checks do not depend on the time of year they run.
local REFERENCE = os.time{ year = year, month = 11, day = 15, hour = 12 }
local function open_screen(args)
    args.now = args.now or REFERENCE
    return RecapScreen:new(args)
end
local I18n = require("book_rewind/i18n")
local db = DataStorage:getDataDir() .. "/sample_statistics.sqlite3"

SampleDb.write(db, year, { previous = true })
local no_covers = DataStorage:getDataDir() .. "/no_covers.sqlite3"
local full = open_screen{ db_path = db, covers_db = no_covers }
if full.mode ~= "cards" then problem("a full year did not open the cards") end
print(string.format("full year: %d cards, %d years in the database", #full.cards, #full.years))
local seen = {}
for index, card in ipairs(full.cards) do
    full:show_card(index)
    shot(full, string.format("card_%02d_%s", index, card.id))
    seen[card.id] = true
    if full.overflow then problem("card overflows the screen: " .. card.id) end
end
for _, id in ipairs({ "cover", "time", "pages", "books", "author", "streak", "best_day", "session", "hours", "weekdays", "months", "speed", "previous", "archetype", "summary", "timeline", "devoured", "about" }) do
    if not seen[id] then problem("missing card: " .. id) end
end
print(string.format("time: %d s, pages: %d, books: %d, finished: %d, author: %s", full.metrics.total_seconds, full.metrics.total_pages, #full.metrics.books, #full.metrics.finished_books, full.metrics.authors[1].name))
for _, book in ipairs(full.metrics.books) do
    if book.title == "privesc_marker" then problem("a stray file entered the book list") end
end

full:show_card(1)
tap(full, Screen:getWidth() - 10, Screen:getHeight() / 2)
if full.index ~= 2 then problem("a tap on the right did not move forward") end
tap(full, 10, Screen:getHeight() / 2)
if full.index ~= 1 then problem("a tap on the left did not move back") end
tap(full, 10, Screen:getHeight() / 2)
if full.index ~= 1 then problem("moved back before the first card") end
full:onSwipe(nil, { direction = "west" })
if full.index ~= 2 then problem("a swipe did not move forward") end

local previous_year_buttons = 0
for _, button in ipairs(full.cards[1].buttons or {}) do
    if button.year == year - 1 then previous_year_buttons = previous_year_buttons + 1 end
end
if previous_year_buttons ~= 1 then problem("the cover does not offer the previous year") end

-- Year buttons: older on the left, newer on the right, and only the neighbours.
local function year_button(screen, wanted)
    for _, rect in ipairs(require("book_rewind/ui/card_view").layout_buttons(screen.cards[1], Screen:getWidth(), Screen:getHeight())) do
        if rect.year == wanted then return rect end
    end
end
local conn_years = require("lua-ljsqlite3/init").open(db)
conn_years:exec(string.format("INSERT INTO page_stat_data VALUES (1, 2, %d, 900, 320)", os.time{ year = year - 2, month = 3, day = 3, hour = 20 }))
conn_years:close()
local browsing = open_screen{ db_path = db, covers_db = no_covers, language = "pt" }
if #browsing.years ~= 3 then problem("there should be 3 years: " .. #browsing.years) end
if browsing.year ~= year then problem("should open on the most recent year") end
if year_button(browsing, year + 1) then problem("there is no next year") end
if year_button(browsing, year - 2) then problem("only the neighbouring year should appear") end
local older_button = year_button(browsing, year - 1)
if not older_button or older_button.x > Screen:getWidth() / 4 then problem("the previous year should be on the left") end
shot(browsing, "cover_latest_year")
tap(browsing, older_button.x + 4, older_button.y + 4)
if browsing.year ~= year - 1 then problem("tapping the previous year did not open " .. (year - 1)) end
local newer_button = year_button(browsing, year)
local oldest_button = year_button(browsing, year - 2)
if not newer_button or newer_button.x < Screen:getWidth() / 2 then problem("the next year should be on the right") end
if not oldest_button or oldest_button.x > Screen:getWidth() / 4 then problem("the previous year is missing in the middle") end
shot(browsing, "cover_middle_year")
tap(browsing, newer_button.x + newer_button.w - 4, newer_button.y + newer_button.h - 4)
if browsing.year ~= year then problem("tapping the next year did not go back") end
tap(browsing, Screen:getWidth() / 2, Screen:getHeight() / 2)
if browsing.index ~= 2 then problem("a tap outside the buttons should move forward") end
browsing:onCloseWidget()
local pending_export
full.schedule = function(callback) pending_export = callback end
local summary_index
for index, card in ipairs(full.cards) do
    if card.id == "summary" then summary_index = index end
end
full:show_card(summary_index)
local save_button
for _, rect in ipairs(require("book_rewind/ui/card_view").layout_buttons(full.cards[summary_index], Screen:getWidth(), Screen:getHeight())) do
    if rect.id == "export" then save_button = rect end
end
local last_card = full.index
tap(full, save_button.x + 5, save_button.y + 5)
if not pending_export then problem("saving did not start") end
if full.export_label ~= full.strings.saving then problem("the button does not show it is saving") end
shot(full, "summary_saving")
tap(full, Screen:getWidth() - 10, Screen:getHeight() / 2)
if full.index ~= last_card then problem("a tap while saving changed the card") end
pending_export()
local saved = 0
do
    local count = 0
    for name in require("libs/libkoreader-lfs").dir(out_dir .. "/exported") do
        if name:find("^book_rewind_") then count = count + 1 end
    end
    saved = count
end
if saved ~= #full.cards - 1 then problem("exported " .. saved .. " of " .. (#full.cards - 1)) end
if full.export_label ~= full.strings.saved_button(saved) then problem("the button does not confirm the save") end
if not (full.export_footer or ""):find("exported", 1, true) then problem("the footer does not show the folder") end
for _, entry in ipairs(UIManager._window_stack) do
    if entry.widget ~= full and entry.widget.name == "InfoMessage" then problem("still opens a popup") end
end
shot(full, "summary_saved")
if full.overflow then problem("the summary overflows after saving") end
tap(full, Screen:getWidth() - 10, Screen:getHeight() / 2)
if full.index ~= last_card then problem("a queued tap after saving changed the card") end
full.ignore_input_until = nil
local exported = io.open(string.format("%s/exported/book_rewind_%d_01.png", out_dir, year), "rb")
if not exported then problem("exported image not found") else exported:close() end
print("exported " .. saved .. " images")

-- A new save removes the images of an older one that had more cards, and nothing else.
do
    local files = require("libs/libkoreader-lfs")
    local folder = out_dir .. "/exported"
    local function touch(name)
        local file = io.open(folder .. "/" .. name, "wb")
        file:write("x")
        file:close()
    end
    local function exists(name)
        return files.attributes(folder .. "/" .. name, "mode") == "file"
    end
    local stale = string.format("book_rewind_%d_%02d.png", year, #full.cards + 5)
    local other_year = string.format("book_rewind_%d_01.png", year - 1)
    local unrelated = string.format("book_rewind_%d_notes.png", year)
    touch(stale); touch(other_year); touch(unrelated)
    if full:export_images() ~= saved then problem("the second save did not write every image") end
    if exists(stale) then problem("an image from an older save stayed") end
    if not exists(other_year) or not exists(unrelated) then problem("a save removed a file that is not its own") end
    if not exists(string.format("book_rewind_%d_01.png", year)) then problem("a save removed its own image") end
    os.remove(folder .. "/" .. other_year)
    os.remove(folder .. "/" .. unrelated)
end

for _, lang in ipairs({ "en", "es" }) do
    local translated = open_screen{ db_path = db, covers_db = no_covers, language = lang }
    for index, card in ipairs(translated.cards) do
        translated:show_card(index)
        shot(translated, string.format("%s_%02d_%s", lang, index, card.id))
        if translated.overflow then problem("card in " .. lang .. " overflows the screen: " .. card.id) end
    end
    print(lang .. ": " .. #translated.cards .. " cards")
end

SampleDb.write(db, year, { sparse = true })
local sparse = open_screen{ db_path = db }
print("database with little reading: mode " .. sparse.mode .. ", " .. sparse.metrics.total_seconds .. " s")
if sparse.mode ~= "empty" then problem("little reading should show the notice") end
shot(sparse, "empty")
for _, lang in ipairs({ "en", "es" }) do
    local empty = open_screen{ db_path = db, language = lang }
    if empty.mode ~= "empty" then problem("notice in " .. lang) end
    shot(empty, "empty_" .. lang)
    empty:onCloseWidget()
end
sparse:onCloseWidget()

SampleDb.write(db, year, { sparse = true })
local conn = require("lua-ljsqlite3/init").open(db)
conn:exec(string.format("UPDATE page_stat_data SET duration = 200 WHERE id_book = 1"))
conn:close()
local small = open_screen{ db_path = db }
if small.mode ~= "cards" then problem("a single reading session should open the cards") end
print("single session: " .. #small.cards .. " cards")
for index, card in ipairs(small.cards) do
    small:show_card(index)
    shot(small, "small_" .. card.id)
    if small.overflow then problem("small card overflows the screen: " .. card.id) end
end

local lfs = require("libs/libkoreader-lfs")
for _, set in ipairs({ "600", "1200" }) do
    for _, name in ipairs({ "cover", "time", "pages", "author", "best_day", "session", "hours", "speed", "summary", "profile_night_owl", "profile_early_bird", "profile_steady", "profile_marathoner", "profile_loyal", "profile_weekender", "profile_explorer", "profile_curious" }) do
        if lfs.attributes(string.format("%s/assets/cards/%s/%s.png", plugin_dir, set, name), "mode") ~= "file" then
            problem("missing art: " .. set .. "/" .. name)
        end
    end
end

local FakeHistory = require("fake_history")
local covers_path = DataStorage:getDataDir() .. "/fake_covers.sqlite3"
FakeHistory.write_real_covers(covers_path)
local fake_db = DataStorage:getDataDir() .. "/fake_stats.sqlite3"
FakeHistory.write(fake_db, REFERENCE)
for _, lang in ipairs({ "pt", "en", "es" }) do
    local with_covers = open_screen{ db_path = fake_db, covers_db = no_covers, language = lang }
    local ids = {}
    for index, card in ipairs(with_covers.cards) do
        ids[card.id] = true
        with_covers:show_card(index)
        shot(with_covers, string.format("covers_%s_%02d_%s", lang, index, card.id))
        if with_covers.overflow then problem("card with covers overflows in " .. lang .. ": " .. card.id) end
    end
    for _, id in ipairs({ "timeline", "devoured", "books" }) do
        if not ids[id] then problem("missing " .. id .. " with covers in " .. lang) end
    end
    local generated = with_covers:load_cover(with_covers.metrics.books[1].id, 150, 220)
    if not generated then problem("the generated cover did not appear") else generated:free() end
    local with_real = open_screen{ db_path = fake_db, covers_db = covers_path, language = lang }
    local real = with_real:load_cover(with_real.metrics.books[1].id, 100, 150)
    if not real or real:getPixel(50, 75):getColor8().a ~= 0 then problem("the real cover should take priority") end
    if real then real:free() end
    with_real:onCloseWidget()
    if lang == "pt" then print("with covers: " .. #with_covers.cards .. " cards") end
end

local missing = open_screen{ db_path = DataStorage:getDataDir() .. "/does_not_exist.sqlite3" }
if missing.mode ~= "empty" then problem("a missing database should show the notice") end

local blank_path = DataStorage:getDataDir() .. "/blank.sqlite3"
io.open(blank_path, "wb"):close()
local blank_ok, blank = pcall(function() return open_screen{ db_path = blank_path, covers_db = no_covers } end)
if not blank_ok or blank.mode ~= "empty" then problem("a database with no tables should show the notice: " .. tostring(blank)) end

-- A shelf with a book finished in another year explains it in the legend.
local shelf_path = DataStorage:getDataDir() .. "/shelf.sqlite3"
SampleDb.write(shelf_path, year, { sparse = true })
do
    local shelf_conn = require("lua-ljsqlite3/init").open(shelf_path)
    shelf_conn:exec("DELETE FROM page_stat_data")
    shelf_conn:exec("BEGIN")
    local start = os.time{ year = year - 1, month = 3, day = 1, hour = 15 }
    for page = 1, 320 do shelf_conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, %d, %d, 60, 320)", page, start + page * 61)) end
    start = os.time{ year = year, month = 2, day = 1, hour = 15 }
    for page = 1, 20 do shelf_conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, %d, %d, 60, 320)", page, start + page * 61)) end
    for page = 1, 190 do shelf_conn:exec(string.format("INSERT INTO page_stat_data VALUES (4, %d, %d, 60, 190)", page, start + 86400 + page * 61)) end
    for page = 1, 40 do shelf_conn:exec(string.format("INSERT INTO page_stat_data VALUES (2, %d, %d, 60, 280)", page, start + 172800 + page * 61)) end
    shelf_conn:exec("COMMIT")
    shelf_conn:close()
end
for _, lang in ipairs({ "pt", "en", "es" }) do
    local shelf = open_screen{ db_path = shelf_path, language = lang }
    for index, card in ipairs(shelf.cards) do
        if card.id == "books" then
            shelf:show_card(index)
            shot(shelf, "shelf_earlier_" .. lang)
        end
    end
    shelf:onCloseWidget()
end

local SQ3 = require("lua-ljsqlite3/init")
local function history(name, spans)
    local path = DataStorage:getDataDir() .. "/" .. name .. ".sqlite3"
    SampleDb.write(path, year, { sparse = true })
    local c = SQ3.open(path)
    c:exec("DELETE FROM page_stat_data")
    c:exec("BEGIN")
    for _, span in ipairs(spans) do
        for page = span.first, span.last do
            c:exec(string.format("INSERT INTO page_stat_data VALUES (%d, %d, %d, 60, %d)", span.book, page, span.start + (page - span.first) * 61, span.total))
        end
    end
    c:exec("COMMIT")
    c:close()
    return path
end
local function moment(wanted_year, month) return os.time{ year = wanted_year, month = month or 1, day = 1, hour = 2 } end

-- The newest year with little reading must not hide the others.
local early = open_screen{ db_path = history("early_year", {
    { book = 1, first = 1, last = 200, total = 320, start = moment(year - 1, 3) },
    { book = 2, first = 1, last = 3, total = 280, start = moment(year) },
}), covers_db = no_covers, language = "pt" }
if early.mode ~= "cards" or early.year ~= year - 1 then problem("a year with little reading hid the previous one") end
if #early.years ~= 1 then problem("a year with little reading should not be offered") end
local early_notice = early.cards[1].notice or ""
if not early_notice:find(tostring(year), 1, true) or not early_notice:find("minuto", 1, true) then problem("the cover does not say what the current year is missing: " .. early_notice) end
if early.cards[1].body then problem("the notice should not take the card text") end
shot(early, "cover_notice")
if early.overflow then problem("the notice overflows the cover") end
for _, lang in ipairs({ "en", "es" }) do
    local translated_notice = open_screen{ db_path = early.db_path, covers_db = no_covers, language = lang }
    shot(translated_notice, "cover_notice_" .. lang)
    if translated_notice.overflow then problem("the notice overflows the cover in " .. lang) end
    translated_notice:onCloseWidget()
end

-- The notice stays on the screen and out of the saved images.
local CardView = require("book_rewind/ui/card_view")
local Blitbuffer = require("ffi/blitbuffer")
local function differences(export)
    local w, h = Screen:getWidth(), Screen:getHeight()
    local a, b = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8), Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    local card = early.cards[1]
    local paint_options = { width = w, height = h, strings = early.strings, plugin_dir = plugin_dir, export = export }
    CardView.paint(a, card, paint_options)
    local notice = card.notice
    card.notice = nil
    CardView.paint(b, card, paint_options)
    card.notice = notice
    local count = 0
    for y = 0, h - 1, 2 do
        for x = 0, w - 1, 2 do
            if a:getPixel(x, y):getColor8().a ~= b:getPixel(x, y):getColor8().a then count = count + 1 end
        end
    end
    a:free(); b:free()
    return count
end
if differences(false) == 0 then problem("the notice did not appear on the cover") end
if differences(true) ~= 0 then problem("the notice entered the saved image") end
early:onCloseWidget()

-- The current year with enough reading has no notice, and a closed newest year never mentions a future one.
local no_notice = open_screen{ db_path = history("no_notice", { { book = 1, first = 1, last = 200, total = 320, start = moment(year, 2) } }), covers_db = no_covers, language = "pt" }
if no_notice.cards[1].notice then problem("a current year with reading should have no notice") end
no_notice:onCloseWidget()

-- In the first days of a year, the recap of the year that ended comes first.
local both_years = history("both_years", {
    { book = 1, first = 1, last = 200, total = 320, start = moment(year - 1, 3) },
    { book = 2, first = 1, last = 30, total = 280, start = moment(year, 1) },
})
local function opened_on(month, day, path)
    local screen = open_screen{ db_path = path or both_years, covers_db = no_covers, language = "pt", now = os.time{ year = year, month = month, day = day, hour = 12 } }
    local opened = screen.year
    local has_newer = screen.cards and year_button(screen, year) ~= nil
    screen:onCloseWidget()
    return opened, has_newer
end
local january_year, january_newer = opened_on(1, 10)
if january_year ~= year - 1 then problem("in January it should open the year that ended") end
if not january_newer then problem("in January it should offer the new year") end
if opened_on(1, 30) ~= year - 1 then problem("on day 30 it should still open the year that ended") end
if opened_on(1, 31) ~= year then problem("on day 31 it should open the current year") end
local only_current = history("only_current", { { book = 1, first = 1, last = 200, total = 320, start = moment(year, 1) } })
if opened_on(1, 10, only_current) ~= year then problem("without the previous year it should open the current year") end

-- A year with little reading in the middle is skipped by the buttons.
local gap = open_screen{ db_path = history("gap_year", {
    { book = 1, first = 1, last = 200, total = 320, start = moment(year - 2, 3) },
    { book = 2, first = 1, last = 3, total = 280, start = moment(year - 1) },
    { book = 1, first = 1, last = 100, total = 320, start = moment(year) },
}), covers_db = no_covers, language = "pt" }
if year_button(gap, year - 2) == nil then problem("the button should skip the year with little reading") end
if year_button(gap, year - 1) then problem("a year with little reading became a button") end
gap:onCloseWidget()

-- A book read across two years is finished only in the second one.
local across_path = history("across_years", {
    { book = 1, first = 1, last = 160, total = 320, start = moment(year - 2, 11) },
    { book = 1, first = 161, last = 320, total = 320, start = moment(year - 1, 2) },
})
local across = open_screen{ db_path = across_path, covers_db = no_covers, language = "pt" }
if #across.metrics.finished_books ~= 1 then problem("the book should finish in the second year") end
across:open_year(year - 2)
if #across.metrics.finished_books ~= 0 then problem("the book did not finish in the first year") end
across:onCloseWidget()

-- A year in progress compares with the same period of the previous year.
local Store = require("book_rewind/store")
local period_path = history("same_period", {
    { book = 1, first = 1, last = 60, total = 320, start = moment(year - 1, 1) },
    { book = 1, first = 61, last = 180, total = 320, start = moment(year - 1, 9) },
    { book = 2, first = 1, last = 60, total = 280, start = moment(year, 1) },
})
local march = os.time{ year = year, month = 3, day = 1, hour = 12 }
if Store.load_year(period_path, year, march).previous_seconds ~= 3600 then problem("a year in progress should compare the same period") end
if Store.load_year(period_path, year - 1, march).previous_seconds ~= 0 then problem("a closed year has no previous year here") end
local whole = Store.load_year(period_path, year, os.time{ year = year + 1, month = 3, day = 1, hour = 12 })
if whole.previous_seconds ~= 10800 then problem("a closed year should compare the whole year") end

-- Changing the year clears what the save button said.
local two_years = open_screen{ db_path = across_path, covers_db = no_covers, language = "pt", schedule = function(callback) callback() end }
two_years.export_label, two_years.export_footer = "17", "pasta"
two_years:open_year(year - 2)
if two_years.export_label or two_years.export_footer then problem("a save from another year stayed on the button") end

-- A failure while saving does not lock the screen.
local failing = open_screen{ db_path = across_path, covers_db = no_covers, language = "pt", schedule = function(callback) callback() end }
failing.export_images = function() error("disk full") end
if not pcall(failing.start_export, failing) then problem("a save error escaped") end
if failing.export_saving then problem("a save error locked the screen") end
if failing.export_label ~= failing.strings.save_failed then problem("a save error did not appear on the button") end
failing.ignore_input_until = nil
failing:onCloseWidget()

-- A corrupted cover falls back to a generated one and closes the connection.
local broken_covers = DataStorage:getDataDir() .. "/broken_covers.sqlite3"
os.remove(broken_covers)
local broken = SQ3.open(broken_covers)
broken:exec("CREATE TABLE bookinfo (title TEXT, authors TEXT, has_cover TEXT, cover_w INTEGER, cover_h INTEGER, cover_bb_type INTEGER, cover_bb_stride INTEGER, cover_bb_data BLOB)")
broken:exec("INSERT INTO bookinfo VALUES ('A Casa das Marés', 'Helena Vargas', 'Y', 10, 10, 1, 10, 'not a cover')")
broken:close()
local with_broken = open_screen{ db_path = across_path, covers_db = broken_covers, language = "pt" }
local fallback = with_broken:load_cover(1, 100, 150)
if not fallback then problem("a corrupted cover should become a generated cover") else fallback:free() end
with_broken:onCloseWidget()

-- A title shared by different books only brings a cover with the same author, and a cover whose
-- size does not match its pixels is refused before being read.
local shared_covers = DataStorage:getDataDir() .. "/shared_covers.sqlite3"
os.remove(shared_covers)
local shared = SQ3.open(shared_covers)
shared:exec("CREATE TABLE bookinfo (title TEXT, authors TEXT, has_cover TEXT, cover_w INTEGER, cover_h INTEGER, cover_bb_type INTEGER, cover_bb_stride INTEGER, cover_bb_data BLOB)")
shared:exec("INSERT INTO bookinfo VALUES ('Poemas', 'Ana Lima', 'Y', 10, 10, 1, 10, X'00')")
shared:exec("INSERT INTO bookinfo VALUES ('Poemas', 'Bruno Dias', 'Y', 10, 10, 1, 10, X'00')")
do
    -- Fifty bytes of pixels, which match a stride of 5 for 10 rows but not a width of 10.
    -- As in the Cover browser, SQLite takes over the compressed buffer.
    local zstd, ffi = require("ffi/zstd"), require("ffi")
    local pixels = ffi.new("uint8_t[50]")
    local packed, size = zstd.zstd_compress(pixels, 50)
    local insert = shared:prepare("INSERT INTO bookinfo VALUES ('Duna', 'Frank Herbert', 'Y', 10, 10, 1, 5, ?)")
    insert:bind(SQ3.blob(packed, size)):step()
    insert:close()
end
shared:close()
local reader = require("book_rewind/store").open_covers(shared_covers)
if not reader then
    problem("the cover cache did not open")
else
    if reader:find("Poemas", "Bruno Dias") ~= 2 then problem("the same title and author should find the cover") end
    if reader:find("Poemas", "Carla Souza") then problem("a shared title brought the cover of another book") end
    if reader:find("Duna", "") ~= 3 then problem("a title found only once should find its cover") end
    if reader:load("Duna", "Frank Herbert") then problem("a cover with rows shorter than its width was read") end
    reader:close()
end

-- Covers are built once and survive repainting, and are released with the year.
local cached = open_screen{ db_path = fake_db, covers_db = covers_path, language = "pt" }
local builds = 0
local build = cached.load_cover
cached.load_cover = function(...) builds = builds + 1; return build(...) end
local timeline_index
for index, card in ipairs(cached.cards) do
    if card.id == "timeline" then timeline_index = index end
end
cached:show_card(timeline_index)
cached:paintTo(Screen.bb, 0, 0)
local first_builds = builds
if first_builds == 0 then problem("the timeline should load covers") end
cached:paintTo(Screen.bb, 0, 0)
if builds ~= first_builds then problem("covers were reloaded on repaint") end
cached:open_year(cached.year)
if next(cached.covers) ~= nil then problem("covers should be released when changing the year") end
cached:onCloseWidget()

-- Hardware keys navigate and close.
local keys = open_screen{ db_path = fake_db, covers_db = no_covers, language = "pt" }
keys:onNextCard()
if keys.index ~= 2 then problem("the next key did not work") end
keys:onPreviousCard()
if keys.index ~= 1 then problem("the previous key did not work") end
if Device:hasKeys() and not (keys.key_events and keys.key_events.Close) then problem("the close key is missing") end
keys:onCloseWidget()

-- Real files carry very long titles and authors, and every card and cover has to hold them.
local LONG_TITLE = "Um Título Muito Longo: uma Ferramenta Comprovada que Gera Resultados Extraordinários em Muito Pouco Tempo [e-Livros]"
local LONG_NO_COLON = "Um Título Muito Longo e sem Dois Pontos que Segue Falando por Muito Tempo - Uma Coleção Comprida de Leitores - Vol 12"
local long_db = DataStorage:getDataDir() .. "/long_titles.sqlite3"
FakeHistory.write(long_db, REFERENCE)
do
    local long_conn = SQ3.open(long_db)
    long_conn:exec(string.format("UPDATE book SET title = CASE WHEN id %% 2 = 0 THEN '%s' ELSE '%s' END, authors = 'Maria Aparecida de Albuquerque Vasconcelos Figueiredo' WHERE title <> 'privesc_marker'", LONG_TITLE, LONG_NO_COLON))
    long_conn:close()
end
local long_screen = open_screen{ db_path = long_db, covers_db = no_covers, language = "pt" }
for _, long_year in ipairs(long_screen.years) do
    long_screen:open_year(long_year)
    for index, card in ipairs(long_screen.cards) do
        long_screen:show_card(index)
        long_screen:paintTo(Screen.bb, 0, 0)
        if long_screen.overflow then problem(string.format("card %s of %d overflows with a long title", card.id, long_year)) end
        if card.id == "juggler" or card.id == "pace_change" or card.id == "memorable_day" or card.id == "comeback" then
            shot(long_screen, "long_title_" .. card.id)
        end
    end
end
-- The rows of the juggler card sit on the left of a chart, with no room for a second line.
do
    local long_rows = {}
    for i = 1, 5 do
        long_rows[i] = { title = LONG_NO_COLON, from = 60 + i, to = 90 + i * 2 }
    end
    local long_bb = require("ffi/blitbuffer").new(Screen:getWidth(), Screen:getHeight(), require("ffi/blitbuffer").TYPE_BB8)
    local overflowed = require("book_rewind/ui/card_view").paint(long_bb, {
        id = "juggler", kicker = "Você é malabarista", big = "5 livros", label = "abertos ao mesmo tempo, em março",
        rows = long_rows, peak = 75, peak_label = "março", foot = "E você terminou 3 deles.",
    }, { width = long_bb:getWidth(), height = long_bb:getHeight(), strings = I18n.pt, plugin_dir = plugin_dir, export = true })
    if overflowed then problem("juggler overflows with long titles") end
    long_bb:writePNG(out_dir .. "/long_title_juggler.png")
    long_bb:free()
end
for book_id = 2, 3 do
    local long_cover = long_screen:load_cover(book_id, 204, 300)
    if not long_cover then
        problem("a long title should still get a generated cover")
    else
        long_cover:writePNG(string.format("%s/long_title_generated_cover_%d.png", out_dir, book_id))
        long_cover:free()
    end
end
long_screen:onCloseWidget()

-- Every year of the fake history shows a different profile, and none overflows.
local Stats = require("book_rewind/stats")
local fake_profiles = {}
local wildcard_ids, wildcards_seen = {}, {}
for _, wildcard in ipairs(require("book_rewind/wildcards").ORDER) do
    wildcard_ids[wildcard] = true
end
local all_years = open_screen{ db_path = fake_db, covers_db = no_covers, language = "pt" }
for _, fake_year in ipairs(all_years.years) do
    all_years:open_year(fake_year)
    local id = Stats.archetype(all_years.metrics).id
    if fake_profiles[id] then problem("repeated profile in the fake history: " .. id .. " in " .. fake_year) end
    fake_profiles[id] = fake_year
    for _, lang in ipairs({ "pt", "en", "es" }) do
        all_years.strings = I18n[lang]
        all_years:rebuild_cards()
        for index, card in ipairs(all_years.cards) do
            all_years:show_card(index)
            all_years:paintTo(Screen.bb, 0, 0)
            if all_years.overflow then problem(string.format("card %s of %d overflows in %s", card.id, fake_year, lang)) end
            if wildcard_ids[card.id] then
                wildcards_seen[card.id] = true
                shot(all_years, string.format("wildcard_%s_%s", lang, card.id))
            end
        end
    end
    all_years.strings = I18n.pt
end
for wildcard in pairs(wildcard_ids) do
    if not wildcards_seen[wildcard] then problem("fake history without the wildcard " .. wildcard) end
end
for _, id in ipairs({ "night_owl", "early_bird", "steady", "marathoner", "loyal", "weekender", "explorer", "curious" }) do
    if not fake_profiles[id] then problem("fake history without the profile " .. id) end
end
all_years:onCloseWidget()

local initial = Screen:getRotationMode()
Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE)
SampleDb.write(db, year, {})
local rotated = open_screen{ db_path = db }
if Screen:getWidth() > Screen:getHeight() then problem("did not return to portrait") end
rotated:onCloseWidget()
if Screen:getRotationMode() ~= Screen.DEVICE_ROTATED_CLOCKWISE then problem("rotation was not restored") end
Screen:setRotationMode(initial)

-- A screen that fails to open puts the rotation back.
Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE)
if pcall(open_screen, { db_path = db, language = "xx" }) then problem("a screen without texts should not open") end
if Screen:getRotationMode() ~= Screen.DEVICE_ROTATED_CLOCKWISE then problem("a failed opening did not restore the rotation") end
Screen:setRotationMode(initial)

-- A card that cannot be drawn shows a message, and the others are still reachable.
local drawing = open_screen{ db_path = fake_db, covers_db = no_covers, language = "pt" }
drawing:show_card(2)
local real_id = drawing.cards[2].id
drawing.cards[2].id = "no_such_card"
if not pcall(drawing.paintTo, drawing, Screen.bb, 0, 0) then problem("a card that fails to draw broke the screen") end
shot(drawing, "card_failed")
drawing.cards[2].id = real_id
tap(drawing, Screen:getWidth() - 10, Screen:getHeight() / 2)
if drawing.index ~= 3 then problem("the navigation stopped after a card failed") end
drawing:onCloseWidget()

print("problems: " .. problems)
os.exit(problems == 0 and 0 or 1)
