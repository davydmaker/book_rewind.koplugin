local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local I18n = require("book_rewind/i18n")
local Screen = require("book_rewind/ui/screen")

local BookRewind = WidgetContainer:extend{
    name = "book_rewind",
    is_doc_only = false,
}

function BookRewind:init()
    self.ui.menu:registerToMainMenu(self)
end

function BookRewind:addToMainMenu(menu_items)
    menu_items.book_rewind = {
        text = I18n[I18n.language_from(G_reader_settings:readSetting("language"))].menu,
        sorting_hint = "tools",
        callback = function()
            -- The statistics plugin keeps the open book's pages in memory until it writes them.
            local statistics = self.ui.statistics
            if statistics and statistics.isEnabled and statistics:isEnabled() then
                pcall(statistics.insertDB, statistics)
            end
            UIManager:show(Screen:new{})
        end,
    }
end

return BookRewind
