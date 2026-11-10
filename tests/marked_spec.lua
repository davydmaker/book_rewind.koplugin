package.path = "./?.lua;" .. package.path
local Marked = require("book_rewind/marked")

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

local function entry(values)
    local base = { md5 = "m", status = "complete", modified = "2026-05-10", percent = 0.97, title = "Livro", authors = "Ana Lima" }
    for k, v in pairs(values or {}) do base[k] = v end
    return base
end

test("the day is read in the current and the older KOReader formats, at noon", function()
    local t = os.date("*t", Marked.date("2026-05-10"))
    eq(t.year, 2026); eq(t.month, 5); eq(t.day, 10); eq(t.hour, 12)
    t = os.date("*t", Marked.date("24.01.2016"))
    eq(t.year, 2016); eq(t.month, 1); eq(t.day, 24)
end)

test("a day that does not exist or is written another way is ignored", function()
    for _, text in ipairs({ "2026-02-30", "2026-13-01", "2026-5-10", "10/05/2026", "", 20260510 }) do
        eq(Marked.date(text), nil)
    end
    eq(Marked.date(nil), nil)
end)

test("a book counts when finished, marked in the year and read to at least 90%", function()
    eq(Marked.finish_time(entry(), 2026) ~= nil, true)
    eq(Marked.finish_time(entry{ percent = 0.9 }, 2026) ~= nil, true)
end)

test("a book being read, marked in another year or not read far enough does not count", function()
    eq(Marked.finish_time(entry{ status = "reading" }, 2026), nil)
    eq(Marked.finish_time(entry{ status = "abandoned" }, 2026), nil)
    eq(Marked.finish_time(entry{ modified = "2025-12-31" }, 2026), nil)
    eq(Marked.finish_time(entry{ percent = 0.89 }, 2026), nil)
    eq(Marked.finish_time(entry{ percent = false }, 2026), nil)
    eq(Marked.finish_time(entry{ modified = "soon" }, 2026), nil)
end)

test("a marked book missing from the statistics becomes a finished book with its own id", function()
    local metrics = { books = {} }
    local list = Marked.add(metrics, {
        entry{ md5 = "a", modified = "2026-03-02", pagemap_use_page_labels = true, pagemap_doc_pages = 402, doc_pages = 663 },
    }, {}, 2026)
    eq(#list, 1); eq(metrics.marked_books, list)
    local book = list[1]
    eq(book.id < 0, true); eq(book.title, "Livro"); eq(book.authors, "Ana Lima")
    eq(book.total_pages, 402); eq(book.finish_month, 3); eq(book.finished, true); eq(book.marked, true)
    eq(book.seconds, 0); eq(book.pages, 0); eq(book.in_books, nil)
end)

test("without a title in the settings, the file name is used, and the screen total without stable pages", function()
    local list = Marked.add({ books = {} }, { entry{ title = false, file = "/books/Dom Casmurro.epub", doc_pages = 250 } }, {}, 2026)
    eq(list[1].title, "Dom Casmurro"); eq(list[1].total_pages, 250)
end)

test("a book read in part before a reset keeps its place and counts as finished", function()
    local info = { id = 7, title = "Livro", authors = "Ana Lima", total_pages = 300, finished = false }
    local metrics = { books = { info } }
    local list = Marked.add(metrics, { entry{ md5 = "b", modified = "2026-08-20" } }, { [7] = { md5 = "b" } }, 2026)
    eq(#list, 1); eq(list[1].id, 7); eq(list[1].in_books, true); eq(list[1].finish_month, 8)
    eq(info.marked_finished, true)
end)

test("a book the statistics already show as finished, now or before, is not counted again", function()
    for _, flags in ipairs({ { finished = true }, { finished_earlier = true }, { reread = true } }) do
        local info = { id = 7, title = "Livro" }
        for k, v in pairs(flags) do info[k] = v end
        local list = Marked.add({ books = { info } }, { entry{ md5 = "b" } }, { [7] = { md5 = "b" } }, 2026)
        eq(#list, 0); eq(info.marked_finished, nil)
    end
end)

test("a book read to the end in an earlier year and marked later stays out", function()
    local metrics = { books = {} }
    eq(#Marked.to_check(metrics, { entry{ md5 = "c" } }, {}, 2026), 1)
    eq(#Marked.add(metrics, { entry{ md5 = "c" } }, {}, 2026, { c = true }), 0)
end)

test("only marked books outside the year's lists need their earlier sessions checked", function()
    local metrics = { books = { { id = 7 } } }
    local md5s = Marked.to_check(metrics, {
        entry{ md5 = "in_year" }, entry{ md5 = "missing" }, entry{ md5 = "reading", status = "reading" },
    }, { [7] = { md5 = "in_year" } }, 2026)
    eq(#md5s, 1); eq(md5s[1], "missing")
end)

test("marked books get distinct ids and come in the order they were marked", function()
    local list = Marked.add({ books = {} }, {
        entry{ md5 = "x", modified = "2026-09-01", title = "Depois" },
        entry{ md5 = "y", modified = "2026-02-01", title = "Antes" },
    }, {}, 2026)
    eq(list[1].title, "Antes"); eq(list[2].title, "Depois")
    eq(list[1].id ~= list[2].id, true)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
