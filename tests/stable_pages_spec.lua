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

test("totals keeps only the entries with a stable total", function()
    local totals = StablePages.totals({
        { md5 = "a", pagemap_use_page_labels = true, pagemap_doc_pages = 402 },
        { md5 = "b", pagemap_use_page_labels = false, pagemap_doc_pages = 150 },
        { pagemap_use_page_labels = true, pagemap_doc_pages = 99 },
    })
    eq(totals.a, 402)
    eq(totals.b, nil)
    local count = 0
    for _ in pairs(totals) do count = count + 1 end
    eq(count, 1)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
