-- Serves the share page with the fake history, approving the first device, to test it in a browser.
-- Usage: RUN_SECONDS=600 READY_FILE=/tmp/url KOREADER_DIR=... tools/koreader/run_headless.sh tools/koreader/demo_share.lua
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/tools/koreader/?.lua;" .. package.path
os.execute('mkdir -p "' .. DataStorage:getDataDir() .. '/cache"')
local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
require("ui/uimanager"):init()
local FakeHistory = require("fake_history")
local RecapScreen = require("book_rewind/ui/screen")
local ShareScreen = require("book_rewind/ui/share_screen")

local year = tonumber(os.date("%Y"))
local db = DataStorage:getDataDir() .. "/stats.sqlite3"
FakeHistory.write(db, os.time{ year = year, month = 11, day = 15, hour = 12 })
local language = os.getenv("UI_LANGUAGE") or "pt"
local recap = RecapScreen:new{ db_path = db, covers_db = DataStorage:getDataDir() .. "/none.sqlite3", language = language,
    now = os.time{ year = year + 1, month = 2, day = 15, hour = 12 } }
local share = ShareScreen:new{
    cards = recap.cards,
    year = recap.year,
    language = language,
    card_strings = recap.strings,
    plugin_dir = plugin_dir,
    cover = recap.cover_provider,
    after_layer = function() recap:free_covers() end,
    local_ip = os.getenv("SHARE_IP"),
    port = tonumber(os.getenv("SHARE_PORT")),
    open_firewall = function() end,
    close_firewall = function() end,
}
assert(share.url, "no address")
local shot_dir = os.getenv("SHOT_DIR")
if shot_dir then
    share:paintTo(Screen.bb, 0, 0)
    Screen.bb:writePNG(shot_dir .. "/share_waiting.png")
end
local ready = io.open(assert(os.getenv("READY_FILE")), "w")
ready:write(share.url)
ready:close()
local started = os.time()
local run_seconds = tonumber(os.getenv("RUN_SECONDS")) or 0
local shot_connected = false
while os.time() - started < run_seconds do
    share.server:tick()
    if share.access.pending_ip then
        local ip = share.access.pending_ip
        share:close_confirm()
        share.access:approve(ip)
        share.state = "connected"
        share:show_sharing()
        if shot_dir and not shot_connected then
            shot_connected = true
            share:paintTo(Screen.bb, 0, 0)
            Screen.bb:writePNG(shot_dir .. "/share_connected.png")
        end
    end
    require("ffi/util").usleep(2000)
end
share:onCloseWidget()
os.exit(0)
