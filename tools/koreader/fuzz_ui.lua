-- Random touches through the cards in each language, an empty year and the share screen, with the fake
-- history. Usage: KOREADER_DIR=... tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua
-- Environment: ACTIONS, SEED, ONLY and MAX_ERRORS (see tools/koreader/fuzz.lua).
local Fuzz = dofile(os.getenv("PLUGIN_DIR") .. "/tools/koreader/fuzz.lua")
package.path = Fuzz.plugin_dir .. "/tools/koreader/?.lua;" .. package.path

local DataStorage = require("datastorage")
local FakeHistory = require("fake_history")
local SampleDb = require("sample_db")
local RecapScreen = require("book_rewind/ui/screen")
local ShareScreen = require("book_rewind/ui/share_screen")

-- Touches must never serve a page on the network of the computer: the share screen gets an address that is
-- not on a private network, which it refuses, and shows its message instead.
ShareScreen.local_ip = "127.0.0.1"

local year = tonumber(os.date("%Y"))
local REFERENCE = os.time{ year = year, month = 11, day = 15, hour = 12 }
local data_dir = DataStorage:getDataDir()
local db = data_dir .. "/fuzz_stats.sqlite3"
FakeHistory.write(db, REFERENCE)
local covers = data_dir .. "/fuzz_covers.sqlite3"
FakeHistory.write_real_covers(covers)
local little = data_dir .. "/fuzz_little.sqlite3"
SampleDb.write(little, year, { sparse = true })

local function open(args)
    args.now = REFERENCE
    args.covers_db = args.covers_db or covers
    return RecapScreen:new(args)
end

local fuzz = Fuzz.new{ screen = open{ db_path = db, language = "en" } }
for _, language in ipairs({ "en", "pt", "es" }) do
    fuzz:run{
        label = "cards " .. language,
        setup = function()
            G_reader_settings:delSetting("book_rewind_double_flash")
            return open{ db_path = db, language = language }
        end,
    }
end
fuzz:run{
    label = "empty year",
    setup = function()
        local screen = open{ db_path = little, language = "pt" }
        assert(screen.mode == "empty", "the little history should open the empty year notice")
        return screen
    end,
}
fuzz:run{
    label = "share",
    setup = function()
        local screen = open{ db_path = db, language = "en" }
        screen:open_share()
        return screen
    end,
}
fuzz:finish()
