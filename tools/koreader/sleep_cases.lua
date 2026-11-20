-- Windows in a state with a timer, for tools/koreader/check_sleep.lua. The share screen gets a private address
-- that no interface of the computer has, so its server never listens; a stand-in server then runs the session
-- as a real one would, with its tick timer, so sleep stops it as it does on the device.
local function share_screen(plugin_dir)
    local Sleep = require("book_rewind/sleep")
    local ShareScreen = require("book_rewind/ui/share_screen")
    local screen = ShareScreen:new{
        plugin_dir = plugin_dir,
        cards = {},
        year = 2026,
        language = "en",
        card_strings = require("book_rewind/i18n").en,
        local_ip = "192.168.255.254",
        open_firewall = function() return true end,
        close_firewall = function() return true end,
    }
    screen.server = { last_activity = os.time(), tick = function() return false end, stop = function() end }
    screen.close_firewall_now = function() end
    screen.state = "waiting"
    Sleep.schedule(screen, 0.25, screen.tick_callback)
    return screen
end

return {
    ["book_rewind/ui/share_screen"] = share_screen,
}
