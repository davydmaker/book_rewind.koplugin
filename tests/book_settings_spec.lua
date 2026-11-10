package.path = "./?.lua;" .. package.path
local BookSettings = require("book_rewind/book_settings")

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
local function by_md5(entries)
    local map = {}
    for _, entry in ipairs(entries) do
        map[entry.md5] = entry
    end
    return map
end

test("collect reads stable page numbers, status, progress and book info", function()
    local files = {
        ["/books/a.epub"] = settings{
            partial_md5_checksum = "a", pagemap_use_page_labels = true, pagemap_doc_pages = 402,
            summary = { status = "complete", modified = "2026-05-10" }, percent_finished = 0.98,
            doc_props = { title = "Livro A", authors = "Ana Lima" }, doc_pages = 663,
        },
    }
    local entries = BookSettings.collect(100, {
        history = { { file = "/books/a.epub", time = 200 } },
        open = function(file) return files[file] end,
    })
    eq(#entries, 1)
    local a = entries[1]
    eq(a.md5, "a"); eq(a.file, "/books/a.epub")
    eq(a.pagemap_use_page_labels, true); eq(a.pagemap_doc_pages, 402)
    eq(a.status, "complete"); eq(a.modified, "2026-05-10"); eq(a.percent, 0.98)
    eq(a.title, "Livro A"); eq(a.authors, "Ana Lima"); eq(a.doc_pages, 663)
end)

test("collect reads every book opened since the start of the year, and none before", function()
    local opened = {}
    local history = {}
    for i = 1, 30 do
        history[i] = { file = "/books/" .. i .. ".epub", time = 1000 - i }
    end
    history[#history + 1] = { file = "/books/old.epub", time = 10 }
    local entries = BookSettings.collect(100, {
        history = history,
        open = function(file)
            opened[#opened + 1] = file
            return settings{ partial_md5_checksum = file:match("/([%w]+)%.epub$") }
        end,
    })
    eq(#entries, 30)
    eq(#opened, 30)
    eq(by_md5(entries).old, nil)
end)

test("a book whose settings cannot be read is left out, and the others still count", function()
    local entries = BookSettings.collect(0, {
        history = { { file = "/books/broken.epub", time = 5 }, { file = "/books/a.epub", time = 5 } },
        open = function(file)
            if file == "/books/broken.epub" then error("bad settings file") end
            return settings{ partial_md5_checksum = "a" }
        end,
    })
    eq(#entries, 1); eq(entries[1].md5, "a")
end)

test("the book open now wins over its settings file, which may be older", function()
    local entries = BookSettings.collect(0, {
        history = { { file = "/books/a.epub", time = 5 } },
        open = function() return settings{ partial_md5_checksum = "a", summary = { status = "reading" } } end,
        current = settings{ partial_md5_checksum = "a", summary = { status = "complete", modified = "2026-06-01" } },
        current_file = "/books/a.epub",
    })
    eq(#entries, 1); eq(entries[1].status, "complete"); eq(entries[1].file, "/books/a.epub")
end)

test("settings without an MD5, odd values and odd history entries do not break collect", function()
    local entries = BookSettings.collect(1, {
        history = {
            "text", { time = 5 }, { file = 3, time = 5 }, { file = "/books/no_time.epub" },
            { file = "/books/no_md5.epub", time = 5 }, { file = "/books/odd.epub", time = 5 },
        },
        open = function(file)
            if file == "/books/no_md5.epub" then return settings{} end
            return settings{ partial_md5_checksum = "odd", summary = "complete", doc_props = 7, percent_finished = "x" }
        end,
    })
    eq(#entries, 1)
    local odd = entries[1]
    eq(odd.md5, "odd"); eq(odd.status, nil); eq(odd.title, nil); eq(odd.percent, nil)
end)

test("KOReader's quick start guide, in its help folder, is no book", function()
    local guide = "/mnt/us/koreader/help/quickstart-en-v2026.07.1.html"
    local done = settings{ partial_md5_checksum = "guide", summary = { status = "complete", modified = "2026-11-01" }, percent_finished = 1 }
    local entries = BookSettings.collect(0, {
        history = { { file = guide, time = 5 }, { file = "/mnt/us/documents/a.epub", time = 5 } },
        open = function(file) return file == guide and done or settings{ partial_md5_checksum = "a" } end,
        current = done, current_file = guide, help_dir = "/mnt/us/koreader/help/",
    })
    eq(#entries, 1); eq(entries[1].md5, "a")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
