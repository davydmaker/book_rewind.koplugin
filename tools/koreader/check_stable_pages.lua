-- Checks that a book where the reader uses stable page numbers counts pages in them, with KOReader's own
-- reading history and book settings, in the sidecar next to the book and in the hash folder.
-- Usage: KOREADER_DIR=... tools/koreader/run_headless.sh tools/koreader/check_stable_pages.lua
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/tools/koreader/?.lua;" .. package.path

local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/uimanager"):init()
local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local FakeHistory = require("fake_history")
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
local covers = data_dir .. "/none.sqlite3"
local function open(args)
    args = args or {}
    args.db_path, args.covers_db, args.now, args.language = db, covers, REFERENCE, "en"
    local screen = RecapScreen:new(args)
    screen:free_covers()
    return screen
end
local function find(screen, id)
    for _, book in ipairs(screen.metrics.books) do
        if book.id == id then
            return book
        end
    end
end

-- The book with the most reading time stands for a book whose stable page numbers are turned on.
local base = open()
local target = base.metrics.books[1]
local md5 = base.book_data[target.id].md5
if not md5 then
    problem("the books of the fake history have no MD5")
end
local stable_total = math.floor(target.total_pages / 2)
print(string.format("book %q: %d screen pages, %d read; year total %d", target.title, target.total_pages, target.pages, base.metrics.total_pages))

os.execute(string.format('mkdir -p "%s/books"', data_dir))
local file = data_dir .. "/books/stable.epub"
local handle = assert(io.open(file, "wb"))
handle:write(string.rep("stable page numbers ", 4096))
handle:close()
ReadHistory:addItem(file, REFERENCE)

local function write_settings(use)
    local settings = DocSettings:open(file)
    settings:saveSetting("partial_md5_checksum", md5)
    settings:saveSetting("pagemap_use_page_labels", use)
    settings:saveSetting("pagemap_doc_pages", stable_total)
    settings:flush()
    return settings
end

local function expect_stable(screen, where)
    local book = find(screen, target.id)
    if screen.book_data[target.id].pages ~= stable_total or not screen.book_data[target.id].stable_pages then
        problem(where .. ": the stable total was not used")
        return
    end
    if book.total_pages ~= stable_total then
        problem(string.format("%s: the book shows %d pages, expected %d", where, book.total_pages, stable_total))
    end
    local expected_read = math.floor(target.pages * stable_total / target.total_pages + 0.5)
    if math.abs(book.pages - expected_read) > 1 then
        problem(string.format("%s: %d pages read, expected about %d", where, book.pages, expected_read))
    end
    if screen.metrics.total_pages ~= base.metrics.total_pages - target.pages + book.pages then
        problem(where .. ": the year total does not follow the book")
    end
    print(string.format("%s: %d stable pages, %d read; year total %d", where, book.total_pages, book.pages, screen.metrics.total_pages))
end

local function expect_screen(screen, where)
    if screen.book_data[target.id].stable_pages or find(screen, target.id).total_pages ~= target.total_pages then
        problem(where .. ": the screen total should stay")
    end
end

-- Next to the book, KOReader's default.
write_settings(true)
expect_stable(open(), "sidecar next to the book")

write_settings(false)
expect_screen(open(), "stable page numbers turned off")

-- The book open in KOReader can have the option turned on before its file is written.
local current = DocSettings:open(file)
current:saveSetting("pagemap_use_page_labels", true)
expect_stable(open{ doc_settings = current }, "book open now")

-- In the hash folder, found from the file itself.
os.execute(string.format('rm -rf "%s/books/stable.sdr"', data_dir))
G_reader_settings:saveSetting("document_metadata_folder", "hash")
write_settings(true)
if not DocSettings:hasSidecarFile(file) then
    problem("the hash sidecar was not written")
end
expect_stable(open(), "hash folder")

-- A history entry opened before the year cannot hold a book read in it.
ReadHistory.hist = { { file = file, time = os.time{ year = year - 1, month = 6, day = 1 } } }
expect_screen(open(), "opened before the year")

print(problems == 0 and "stable pages: ok" or ("stable pages: " .. problems .. " problem(s)"))
os.exit(problems == 0 and 0 or 1)
