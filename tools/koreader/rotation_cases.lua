-- Fields for the windows that need more than plugin_dir in tools/koreader/check_rotation.lua.
-- The share screen gets a private address that no interface of the computer has: the session goes as far as
-- starting the server, which cannot listen there, so nothing is ever served on the network.
return {
    ["book_rewind/ui/share_screen"] = function(plugin_dir)
        return {
            plugin_dir = plugin_dir,
            cards = {},
            year = 2026,
            language = "en",
            card_strings = require("book_rewind/i18n").en,
            local_ip = "192.168.255.254",
            open_firewall = function() end,
            close_firewall = function() end,
        }
    end,
}
