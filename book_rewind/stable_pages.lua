-- Page totals in KOReader's stable page numbers (publisher pages or characters per page), for the books where
-- the reader turned them on. KOReader keeps them in each book's settings, not in the statistics, so they are
-- found through the reading history and matched to the statistics by the partial MD5 of the file.
local StablePages = {}

-- The stable total of a book, from its settings, only when the reader uses stable page numbers in it.
function StablePages.total(settings)
    if type(settings) ~= "table" or settings.pagemap_use_page_labels ~= true then
        return nil
    end
    local pages = settings.pagemap_doc_pages
    if type(pages) ~= "number" or pages < 1 or pages ~= math.floor(pages) then
        return nil
    end
    return pages
end

-- books: { [id] = { md5, pages, ... } }, as the store loads them. totals: { [md5] = stable total }.
-- The screen total stays in screen_pages. Returns how many books changed.
function StablePages.apply(books, totals)
    local changed = 0
    for _, book in pairs(books or {}) do
        local total = book.md5 and totals[book.md5]
        if total then
            book.screen_pages = book.pages
            book.pages = total
            book.stable_pages = true
            changed = changed + 1
        end
    end
    return changed
end

local function read_keys(doc_settings)
    return {
        md5 = doc_settings:readSetting("partial_md5_checksum"),
        pagemap_use_page_labels = doc_settings:readSetting("pagemap_use_page_labels"),
        pagemap_doc_pages = doc_settings:readSetting("pagemap_doc_pages"),
    }
end

-- md5s: { [md5] = true } for the books of the year. since: only history entries opened from then on can
-- hold a book read in the year. opts, for tests: history (a list of { file, time }), open (a function from a
-- file path to its settings) and current (the settings of the book open now, newer than the file on disk).
function StablePages.collect(md5s, since, opts)
    opts = opts or {}
    local totals = {}
    local wanted = 0
    for _ in pairs(md5s) do
        wanted = wanted + 1
    end
    local found = 0
    local function consider(keys)
        if keys.md5 and md5s[keys.md5] and totals[keys.md5] == nil then
            totals[keys.md5] = StablePages.total(keys) or false
            found = found + 1
        end
    end
    if opts.current then
        local ok, keys = pcall(read_keys, opts.current)
        if ok then
            consider(keys)
        end
    end
    local history = opts.history or require("readhistory").hist
    local open = opts.open or function(file) return require("docsettings"):open(file) end
    for _, item in ipairs(history or {}) do
        if found >= wanted then
            break
        end
        if type(item) == "table" and type(item.file) == "string" and (item.time or 0) >= since then
            local ok, keys = pcall(function() return read_keys(open(item.file)) end)
            if ok then
                consider(keys)
            end
        end
    end
    for md5, total in pairs(totals) do
        if not total then
            totals[md5] = nil
        end
    end
    return totals
end

return StablePages
