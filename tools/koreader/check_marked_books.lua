-- Checks books marked as finished in KOReader and missing from the statistics, with KOReader's own reading
-- history and book settings: a book whose statistics were reset, a book read in part before a reset, and the
-- books that must stay out. Saves the books card and the timeline to OUTPUT_DIR.
-- Usage: OUTPUT_DIR=<folder> KOREADER_DIR=... tools/koreader/run_headless.sh tools/koreader/check_marked_books.lua
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/tools/koreader/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
require("ui/uimanager"):init()
local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local SQ3 = require("lua-ljsqlite3/init")
local FakeHistory = require("fake_history")
local Stats = require("book_rewind/stats")
local Store = require("book_rewind/store")
local RecapScreen = require("book_rewind/ui/screen")

local problems = 0
local function problem(text)
    problems = problems + 1
    print("PROBLEM: " .. text)
end

local year = tonumber(os.date("%Y"))
local REFERENCE = os.time{ year = year, month = 11, day = 15, hour = 12 }
local data_dir = DataStorage:getDataDir()
local db = data_dir .. "/stats.sqlite3"
FakeHistory.write(db, REFERENCE)
local covers = data_dir .. "/covers.sqlite3"
FakeHistory.write_real_covers(covers)
local function open()
    local screen = RecapScreen:new{ db_path = db, covers_db = covers, now = REFERENCE, language = "en" }
    return screen
end
local function counts(screen)
    local card = screen.cards and (function()
        for _, c in ipairs(screen.cards) do
            if c.id == "books" then return c end
        end
    end)()
    local shelf, finished = require("book_rewind/cards").book_lists(screen.metrics)
    return #shelf, #finished, card
end
local function card_index(screen, id)
    for index, card in ipairs(screen.cards) do
        if card.id == id then return index end
    end
end

local base = open()
local base_opened, base_finished = counts(base)
print(string.format("statistics only: %d opened, %d finished", base_opened, base_finished))
base:free_covers()

os.execute(string.format('mkdir -p "%s/books"', data_dir))
local function book_file(name)
    local file = data_dir .. "/books/" .. name .. ".epub"
    local handle = assert(io.open(file, "wb"))
    handle:write(string.rep(name .. " ", 2048))
    handle:close()
    ReadHistory:addItem(file, REFERENCE)
    return file
end
local function write_settings(file, values)
    local settings = DocSettings:open(file)
    for key, value in pairs(values) do
        settings:saveSetting(key, value)
    end
    settings:flush()
end
local function marked(md5, modified, percent, title)
    return {
        partial_md5_checksum = md5, percent_finished = percent or 1,
        summary = { status = "complete", modified = modified }, doc_props = { title = title, authors = "Rui Paz" }, doc_pages = 240,
    }
end

-- A: a book read to the end before its statistics were reset.
write_settings(book_file("reset"), marked("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", string.format("%d-04-15", year), 1, "O Alienista"))
-- A, with the date as older KOReader versions wrote it.
write_settings(book_file("old_format"), marked("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", string.format("02.07.%d", year), 0.95, "Memórias Póstumas"))

-- B: a book of the year that the statistics do not show as finished.
local partial
for _, book in ipairs(base.metrics.books) do
    if not book.finished and not book.finished_earlier and not book.reread and base.book_data[book.id].md5 then
        partial = book
        break
    end
end
if not partial then
    problem("the fake history has no unfinished book to stand for a reset")
else
    write_settings(book_file("partial"), marked(base.book_data[partial.id].md5, string.format("%d-09-03", year), 0.97, partial.title))
end

-- Books that must stay out.
local finished_now = base.metrics.finished_books[1]
write_settings(book_file("finished_now"), marked(base.book_data[finished_now.id].md5, string.format("%d-10-01", year), 1, finished_now.title))
write_settings(book_file("marked_before"), marked("cccccccccccccccccccccccccccccccc", string.format("%d-12-20", year - 1), 1, "Ano Passado"))
write_settings(book_file("not_read"), marked("dddddddddddddddddddddddddddddddd", string.format("%d-05-05", year), 0.4, "Só Marcado"))
local reading = marked("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", string.format("%d-05-05", year), 1, "Lendo")
reading.summary.status = "reading"
write_settings(book_file("reading"), reading)

-- KOReader's quick start guide, in its help folder, is no book even when marked as finished.
os.execute(string.format('mkdir -p "%s/help"', data_dir))
local guide = data_dir .. "/help/quickstart-en.html"
local handle = assert(io.open(guide, "wb"))
handle:write("<html><body>quick start</body></html>")
handle:close()
ReadHistory:addItem(guide, REFERENCE)
write_settings(guide, marked("ffffffffffffffffffffffffffffffff", string.format("%d-11-01", year), 1, "Guia de Início Rápido"))

-- A book read to the end in an earlier year, not read this year, and marked this year.
local conn = SQ3.open(db, "ro")
local result = conn:exec("SELECT id, md5 FROM book WHERE md5 IS NOT NULL")
conn:close()
local earlier
for i = 1, #result[1] do
    local id = tonumber(result[1][i])
    if not base.book_data[id] then
        local history = Store.book_history(db, id, year)
        if history and Stats.count_passes(history) > 0 then
            earlier = result[2][i]
            break
        end
    end
end
if not earlier then
    problem("the fake history has no book finished in an earlier year")
else
    write_settings(book_file("finished_earlier"), marked(earlier, string.format("%d-03-03", year), 1, "Lido Antes"))
end

local screen = open()
local opened, finished, books_card = counts(screen)
print(string.format("with marked books: %d opened, %d finished", opened, finished))
if opened ~= base_opened + 2 then
    problem(string.format("expected %d opened books, got %d", base_opened + 2, opened))
end
if finished ~= base_finished + 3 then
    problem(string.format("expected %d finished books, got %d", base_finished + 3, finished))
end
local titles = {}
for _, book in ipairs(screen.metrics.marked_books or {}) do
    titles[#titles + 1] = string.format("%s (%s, month %d)", book.title, book.in_books and "already read this year" or "new", book.finish_month)
end
print("marked: " .. table.concat(titles, "; "))
if partial and not partial.title then
    problem("the partly read book has no title")
end
for _, book in ipairs(screen.metrics.books) do
    if partial and book.id == partial.id and not book.marked_finished then
        problem("the partly read book was not marked as finished")
    end
end
if books_card and books_card.big ~= tostring(opened) then
    problem("the books card does not show the marked books")
end

local timeline = card_index(screen, "timeline")
if not timeline then
    problem("no timeline")
else
    local april = screen.cards[timeline].months_books[4]
    local found = false
    for _, book in ipairs(april) do
        if book.id < 0 then found = true end
    end
    if not found then problem("the book marked in April is not on the timeline") end
    screen:show_card(timeline)
    screen:paintTo(Screen.bb, 0, 0)
    Screen.bb:writePNG(out_dir .. "/marked_timeline.png")
end
local books_index = card_index(screen, "books")
screen:show_card(books_index)
screen:paintTo(Screen.bb, 0, 0)
Screen.bb:writePNG(out_dir .. "/marked_books.png")
if screen.metrics.total_seconds ~= base.metrics.total_seconds or screen.metrics.total_pages ~= base.metrics.total_pages then
    problem("marked books changed the time or the pages")
end
-- The share page draws the same cards, as layers, with the same covers.
local Blitbuffer = require("ffi/blitbuffer")
local CardView = require("book_rewind/ui/card_view")
for _, id in ipairs({ "books", "timeline" }) do
    local index = card_index(screen, id)
    if index then
        local layer = Blitbuffer.new(1080, 1440, Blitbuffer.TYPE_BBRGB32)
        local ok, err = pcall(CardView.paint_layer, layer, screen.cards[index], {
            width = 1080, height = 1440, strings = screen.strings, plugin_dir = plugin_dir, cover = screen.cover_provider, theme = "vibrant",
        })
        if not ok then
            problem("the share layer of " .. id .. " failed: " .. tostring(err))
        else
            layer:writePNG(out_dir .. "/marked_share_" .. id .. ".png")
        end
        layer:free()
    end
end
screen:free_covers()

print(problems == 0 and "marked books: ok" or ("marked books: " .. problems .. " problem(s)"))
os.exit(problems == 0 and 0 or 1)
