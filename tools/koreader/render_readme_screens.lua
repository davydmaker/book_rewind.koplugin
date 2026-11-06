-- Renders the README images from the fake history: clean cards, without buttons, in English and Portuguese.
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))
require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/tools/koreader/?.lua;" .. package.path
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/uimanager"):init()
local Blitbuffer = require("ffi/blitbuffer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local CardView = require("book_rewind/ui/card_view")
local FakeHistory = require("fake_history")
local Screen = require("book_rewind/ui/screen")
local Stats = require("book_rewind/stats")

local year = tonumber(os.date("%Y"))
local db = DataStorage:getDataDir() .. "/readme_stats.sqlite3"
FakeHistory.write(db, os.time{ year = year, month = 11, day = 15, hour = 12 })

local WANTED = { "cover", "books", "timeline", "streak", "hours", "months", "previous", "summary" }
local WILDCARDS = { comeback = true, series_run = true, past_midnight = true, slow_burn = true }
local bb = Blitbuffer.new(Device.screen:getWidth(), Device.screen:getHeight(), Blitbuffer.TYPE_BB8)
local color_bb = Blitbuffer.new(Device.screen:getWidth(), Device.screen:getHeight(), Blitbuffer.TYPE_BBRGB32)

local function save(screen, card, path, theme)
    local target = theme and color_bb or bb
    CardView.paint(target, card, {
        width = target:getWidth(), height = target:getHeight(), strings = screen.strings,
        plugin_dir = plugin_dir, export = true, cover = screen.cover_provider, theme = theme or "gray",
    })
    target:writePNG(path)
end

-- A closed year, so the cards read as a finished recap.
local after_the_year = os.time{ year = year + 1, month = 2, day = 15, hour = 12 }
for _, language in ipairs({ "en", "pt" }) do
    local folder = language == "en" and out_dir or (out_dir .. "/" .. language)
    util.makePath(folder .. "/profiles")
    util.makePath(folder .. "/wildcards")
    local screen = Screen:new{ db_path = db, covers_db = DataStorage:getDataDir() .. "/none.sqlite3", language = language, now = after_the_year, theme = "gray" }
    util.makePath(folder .. "/themes")
    for _, name in ipairs({ "eink", "vibrant" }) do
        save(screen, screen.cards[1], folder .. "/themes/" .. name .. ".png", name)
    end
    save(screen, screen.cards[1], folder .. "/themes/gray.png")
    for _, id in ipairs(WANTED) do
        for _, card in ipairs(screen.cards) do
            if card.id == id then
                save(screen, card, folder .. "/" .. id .. ".png")
            end
        end
    end
    for _, fake_year in ipairs(screen.years) do
        screen:open_year(fake_year)
        for _, card in ipairs(screen.cards) do
            if card.id == "archetype" then
                save(screen, card, folder .. "/profiles/" .. Stats.archetype(screen.metrics).id .. ".png")
            elseif WILDCARDS[card.id] then
                save(screen, card, folder .. "/wildcards/" .. card.id .. ".png")
            end
        end
    end
    screen:onCloseWidget()
end
bb:free()
color_bb:free()
assert(lfs.attributes(out_dir .. "/pt/profiles/curious.png", "mode") == "file", "the Curious Reader image is missing")
os.exit(0)
