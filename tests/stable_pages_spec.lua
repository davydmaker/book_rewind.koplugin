package.path = "./?.lua;" .. package.path
local StablePages = require("book_rewind/stable_pages")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAILED: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected)
    if actual ~= expected then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

-- Settings as KOReader's DocSettings gives them: readSetting(key).
local function settings(values)
    return { readSetting = function(_, key) return values[key] end }
end
local function book_settings(md5, use, pages)
    return settings{ partial_md5_checksum = md5, pagemap_use_page_labels = use, pagemap_doc_pages = pages }
end

test("the stable total counts only when the reader uses stable page numbers", function()
    eq(StablePages.total{ pagemap_use_page_labels = true, pagemap_doc_pages = 402 }, 402)
    eq(StablePages.total{ pagemap_use_page_labels = false, pagemap_doc_pages = 402 }, nil)
    eq(StablePages.total{ pagemap_doc_pages = 402 }, nil)
    eq(StablePages.total{ pagemap_use_page_labels = true }, nil)
    eq(StablePages.total(nil), nil)
end)

test("a stable total that is not a whole positive number is ignored", function()
    for _, pages in ipairs({ 0, -3, 12.5, "402" }) do
        eq(StablePages.total{ pagemap_use_page_labels = true, pagemap_doc_pages = pages }, nil)
    end
end)

test("apply changes only the books with a stable total and keeps the screen total", function()
    local books = {
        [1] = { md5 = "a", pages = 663 },
        [2] = { md5 = "b", pages = 200 },
        [3] = { pages = 50 },
    }
    eq(StablePages.apply(books, { a = 402 }), 1)
    eq(books[1].pages, 402)
    eq(books[1].screen_pages, 663)
    eq(books[1].stable_pages, true)
    eq(books[2].pages, 200)
    eq(books[2].stable_pages, nil)
    eq(books[3].pages, 50)
end)

test("collect matches books by the MD5 kept in their settings", function()
    local files = {
        ["/books/a.epub"] = book_settings("a", true, 402),
        ["/books/b.epub"] = book_settings("b", false, 150),
        ["/books/other.epub"] = book_settings("z", true, 99),
    }
    local history = {
        { file = "/books/a.epub", time = 200 },
        { file = "/books/b.epub", time = 150 },
        { file = "/books/other.epub", time = 120 },
    }
    local totals = StablePages.collect({ a = true, b = true }, 100, { history = history, open = function(file) return files[file] end })
    eq(totals.a, 402)
    eq(totals.b, nil)
    eq(totals.z, nil)
end)

test("collect skips history entries opened before the year", function()
    local opened = {}
    local history = { { file = "/books/new.epub", time = 500 }, { file = "/books/old.epub", time = 50 } }
    local totals = StablePages.collect({ old = true }, 100, {
        history = history,
        open = function(file)
            opened[#opened + 1] = file
            return book_settings(file:match("/(%a+)%.epub$"), true, 300)
        end,
    })
    eq(totals.old, nil)
    eq(#opened, 1)
    eq(opened[1], "/books/new.epub")
end)

test("a book whose settings cannot be read is left out, and the others still count", function()
    local history = { { file = "/books/broken.epub", time = 200 }, { file = "/books/a.epub", time = 150 } }
    local totals = StablePages.collect({ a = true, broken = true }, 100, {
        history = history,
        open = function(file)
            if file == "/books/broken.epub" then error("bad settings file") end
            return book_settings("a", true, 402)
        end,
    })
    eq(totals.a, 402)
end)

test("the book open now wins over its settings file, which may be older", function()
    local history = { { file = "/books/a.epub", time = 200 } }
    local totals = StablePages.collect({ a = true }, 100, {
        history = history,
        open = function() return book_settings("a", false, 402) end,
        current = book_settings("a", true, 410),
    })
    eq(totals.a, 410)
end)

test("collect stops reading the history once every book is found", function()
    local opened = 0
    local history = {}
    for i = 1, 50 do
        history[i] = { file = "/books/" .. i .. ".epub", time = 1000 - i }
    end
    StablePages.collect({ ["1"] = true }, 0, {
        history = history,
        open = function(file)
            opened = opened + 1
            return book_settings(file:match("(%d+)%.epub"), true, 100)
        end,
    })
    eq(opened, 1)
end)

test("odd history entries do not break collect", function()
    local totals = StablePages.collect({ a = true }, 1, {
        history = { "text", { time = 5 }, { file = 3, time = 5 }, { file = "/books/a.epub" } },
        open = function() return book_settings("a", true, 7) end,
    })
    eq(totals.a, nil)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
