package.path = "./?.lua;" .. package.path
local Stats = require("book_rewind/stats")

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
local function at(month, day, hour, minute)
    return os.time{ year = 2026, month = month, day = day, hour = hour, min = minute or 0 }
end
local BOOKS = {
    [1] = { title = "Livro A", authors = "Ana Lima", pages = 100 },
    [2] = { title = "Livro B", authors = "Ana Lima\nBruno Dias", pages = 200 },
    [3] = { title = "Sem Autor", authors = "N/A", pages = 50 },
    [4] = { title = "privesc_marker", authors = "N/A", pages = 1 },
}
local function compute(rows, extra)
    local opts = { year = 2026, books = BOOKS, rows = rows, now = at(12, 31, 12) }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return Stats.compute(opts)
end
-- Rows for a run of pages of one book, one page per minute.
local function pages_read(book, first, last, total, start)
    local rows = {}
    for page = first, last do
        rows[#rows + 1] = { book, start + (page - first) * 60, 50, page, total }
    end
    return rows
end
local function earlier(book, first, last, total)
    local list = {}
    for page = first, last do
        list[#list + 1] = { book, page, total }
    end
    return list
end

test("adds up the time of the requested year only", function()
    local m = compute({
        { 1, os.time{ year = 2025, month = 12, day = 31, hour = 20 }, 600, 1, 100 },
        { 1, at(1, 1, 10), 120, 1, 100 },
        { 1, at(1, 1, 11), 60, 2, 100 },
    })
    eq(m.total_seconds, 180)
    eq(m.days_read, 1)
end)
test("no reading does not break", function()
    local m = compute({})
    eq(m.total_seconds, 0); eq(m.days_read, 0); eq(m.longest_streak, 0)
    eq(m.best_month, nil); eq(m.pages_per_hour, 0); eq(#m.books, 0)
    eq(Stats.archetype(m).id, "curious")
end)
test("streak counts days in a row across months", function()
    local m = compute({
        { 1, at(1, 30, 10), 60, 1, 100 },
        { 1, at(1, 31, 10), 60, 2, 100 },
        { 1, at(2, 1, 10), 60, 3, 100 },
        { 1, at(2, 5, 10), 60, 4, 100 },
    })
    eq(m.longest_streak, 3); eq(m.days_read, 4)
end)
test("keeps where the longest streak ends", function()
    local m = compute({
        { 1, at(1, 5, 10), 60, 1, 100 },
        { 1, at(2, 10, 10), 60, 2, 100 },
        { 1, at(2, 11, 10), 60, 3, 100 },
        { 1, at(2, 12, 10), 60, 4, 100 },
    })
    eq(m.longest_streak, 3)
    eq(m.longest_streak_end, os.date("*t", at(2, 12, 10)).yday)
    eq(m.days[os.date("*t", at(1, 5, 10)).yday], 60)
end)
test("a session ends after 5 idle minutes", function()
    local m = compute({
        { 1, at(3, 1, 10, 0), 120, 1, 100 },
        { 1, at(3, 1, 10, 4), 120, 2, 100 },
        { 1, at(3, 1, 10, 30), 60, 3, 100 },
    })
    eq(m.longest_session.seconds, 240)
    eq(m.longest_session.book, 1)
    eq(m.longest_session.start, at(3, 1, 10, 0))
end)
test("rereading a page does not count again", function()
    local m = compute({
        { 1, at(1, 1, 10), 60, 1, 100 },
        { 1, at(1, 2, 10), 60, 1, 100 },
        { 1, at(1, 3, 10), 60, 2, 100 },
    })
    eq(m.total_pages, 2)
end)
test("pages respect a change of font size", function()
    local m = compute({
        { 1, at(1, 1, 10), 60, 1, 50 },
        { 1, at(1, 1, 11), 60, 2, 50 },
    })
    eq(m.total_pages, 4)
end)
test("finished needs 90% of the book", function()
    local rows = pages_read(1, 1, 95, 100, at(1, 1, 10))
    for _, row in ipairs(pages_read(2, 1, 100, 200, at(1, 2, 10))) do rows[#rows + 1] = row end
    local m = compute(rows)
    eq(#m.books, 2); eq(#m.finished_books, 1); eq(m.finished_books[1].title, "Livro A")
end)
test("a book read across two years finishes only in the year it reached the end", function()
    local first_half = compute(pages_read(1, 1, 50, 100, at(11, 1, 10)))
    eq(#first_half.finished_books, 0)
    local second_half = compute(pages_read(1, 51, 100, 100, at(1, 3, 10)), { earlier_pages = earlier(1, 1, 50, 100) })
    eq(#second_half.finished_books, 1); eq(second_half.books[1].started_before_year, true)
    eq(second_half.total_pages, 50)
end)
test("reopening a finished book does not finish it again", function()
    local m = compute(pages_read(1, 90, 95, 100, at(2, 1, 10)), { earlier_pages = earlier(1, 1, 100, 100) })
    eq(#m.books, 1); eq(#m.finished_books, 0)
end)
test("a finished book that is reopened is marked as finished before", function()
    local m = compute(pages_read(1, 90, 95, 100, at(2, 1, 10)), { earlier_pages = earlier(1, 1, 100, 100) })
    eq(m.books[1].finished, false); eq(m.books[1].finished_earlier, true)
    local unfinished = compute(pages_read(1, 1, 50, 100, at(2, 1, 10)))
    eq(unfinished.books[1].finished_earlier, false)
end)
test("last pages read in under a minute still finish the book", function()
    local quick = { { 1, at(2, 1, 10), 40, 90, 100 } }
    local m = compute(quick, { earlier_pages = earlier(1, 1, 89, 100) })
    eq(#m.books, 1); eq(#m.finished_books, 1); eq(m.books[1].finished, true)
end)
test("a file opened by mistake stays out of the lists", function()
    eq(#compute({ { 4, at(1, 1, 10), 34, 1, 1 } }).books, 0)
    eq(#compute({ { 1, at(2, 1, 10), 40, 50, 100 } }, { earlier_pages = earlier(1, 1, 10, 100) }).books, 0)
end)
test("rereading the whole book in another year counts as finished", function()
    local m = compute(pages_read(1, 1, 100, 100, at(2, 1, 10)), { earlier_pages = earlier(1, 1, 100, 100) })
    eq(#m.finished_books, 1)
end)
test("rereading a passage at another font size does not inflate progress", function()
    local rows = pages_read(1, 1, 100, 200, at(5, 1, 10))
    for _, row in ipairs(pages_read(1, 1, 90, 180, at(5, 10, 10))) do rows[#rows + 1] = row end
    local m = compute(rows)
    eq(#m.finished_books, 0); eq(m.total_pages, 50)
end)
test("a whole book read at two font sizes finishes", function()
    local rows = pages_read(1, 1, 50, 100, at(5, 1, 10))
    for _, row in ipairs(pages_read(1, 61, 120, 120, at(5, 10, 10))) do rows[#rows + 1] = row end
    eq(#compute(rows).finished_books, 1)
end)
test("a half-hour time zone separates days near midnight", function()
    local ffi = require("ffi")
    ffi.cdef("int setenv(const char *, const char *, int); int unsetenv(const char *); void tzset(void);")
    local original = os.getenv("TZ")
    ffi.C.setenv("TZ", "IST-5:30", 1); ffi.C.tzset()
    local ok, err = pcall(function()
        local before = os.time{ year = 2026, month = 6, day = 10, hour = 23, min = 40 }
        local m = compute({ { 1, before, 300, 1, 100 }, { 1, before + 2400, 300, 2, 100 } })
        eq(m.days_read, 2); eq(m.hours[23], 300); eq(m.hours[0], 300)
    end)
    if original then ffi.C.setenv("TZ", original, 1) else ffi.C.unsetenv("TZ") end
    ffi.C.tzset()
    if not ok then error(err, 0) end
end)
test("lists ignore books opened for under a minute", function()
    local m = compute({ { 4, at(1, 1, 10), 34, 1, 1 }, { 1, at(1, 1, 11), 120, 1, 100 } })
    eq(#m.books, 1); eq(m.books[1].title, "Livro A")
    eq(m.total_seconds, 154)
end)
test("authors: splits co-authors and ignores N/A", function()
    local m = compute({
        { 1, at(1, 1, 10), 100, 1, 100 },
        { 2, at(1, 2, 10), 200, 1, 200 },
        { 3, at(1, 3, 10), 300, 1, 50 },
    })
    eq(#m.authors, 2)
    eq(m.authors[1].name, "Ana Lima"); eq(m.authors[1].seconds, 300); eq(m.authors[1].books, 2)
    eq(m.authors[2].name, "Bruno Dias"); eq(m.authors[2].seconds, 200)
end)
test("different spellings of an author count as one person", function()
    eq(Stats.author_key("J.R.R. Tolkien"), Stats.author_key("Tolkien, J. R. R."))
    eq(Stats.author_key("José Saramago"), Stats.author_key("SARAMAGO, Jose"))
    eq(Stats.author_key("Machado de Assis") == Stats.author_key("Eça de Queirós"), false)
    local books = {
        { title = "H", authors = "J.R.R. Tolkien", pages = 300 },
        { title = "S", authors = "Tolkien, J. R. R.", pages = 400 },
    }
    local m = compute({ { 2, at(1, 3, 15), 7000, 1, 400 }, { 1, at(2, 3, 15), 3000, 1, 300 } }, { books = books })
    eq(#m.authors, 1); eq(m.authors[1].name, "Tolkien, J. R. R."); eq(m.authors[1].books, 2); eq(m.authors[1].long_books, 2)
    eq(Stats.archetype(m).id, "loyal")
end)
test("best hour, weekday and month", function()
    local m = compute({
        { 1, at(3, 2, 21), 300, 1, 100 },
        { 1, at(3, 3, 8), 100, 2, 100 },
        { 1, at(5, 4, 21), 50, 3, 100 },
    })
    eq(m.best_hour, 21); eq(m.best_month, 3)
    eq(m.best_weekday, os.date("*t", at(3, 2, 21)).wday)
    eq(m.active_months, 2)
end)
test("time shares add up", function()
    local m = compute({ { 1, at(1, 1, 23), 300, 1, 100 }, { 1, at(1, 2, 6), 100, 2, 100 } })
    eq(m.night_share, 0.75); eq(m.morning_share, 0.25)
end)

local Cards = require("book_rewind/cards")
local I18n = require("book_rewind/i18n")
test("numbers and durations", function()
    eq(Cards.number(1298, "."), "1.298"); eq(Cards.number(100, "."), "100"); eq(Cards.number(1234567, "."), "1.234.567")
    eq(Cards.number(1298, ","), "1,298"); eq(Cards.number(123456, "."), "123.456")
    eq(Cards.duration(45 * 60), "45 min"); eq(Cards.duration(3600), "1 h"); eq(Cards.duration(5400), "1 h 30 min")
end)
local function card_ids(metrics)
    local ids = {}
    for _, card in ipairs(Cards.build(metrics, { books = BOOKS, strings = I18n.pt })) do ids[card.id] = card end
    return ids
end
test("cards without enough data disappear", function()
    local ids = card_ids(compute({ { 1, at(1, 1, 10), 700, 1, 100 } }))
    eq(ids.cover ~= nil, true); eq(ids.time ~= nil, true); eq(ids.archetype ~= nil, true); eq(ids.summary ~= nil, true)
    eq(ids.streak, nil); eq(ids.best_day, nil); eq(ids.months, nil); eq(ids.weekdays, nil); eq(ids.previous, nil); eq(ids.speed, nil)
end)
test("a book without an author creates no author card", function()
    local ids = card_ids(compute({ { 3, at(1, 1, 10), 700, 1, 50 } }))
    eq(ids.author, nil); eq(ids.books ~= nil, true)
end)
test("comparison with the previous year accepts a drop", function()
    local ids = card_ids(compute({ { 1, at(1, 1, 10), 700, 1, 100 } }, { previous_seconds = 1400 }))
    eq(ids.previous.big, "-50%")
end)
test("notices say how much is missing, with the right plural", function()
    eq(Cards.minutes_missing(0), 10); eq(Cards.minutes_missing(360), 4); eq(Cards.minutes_missing(599), 1); eq(Cards.minutes_missing(9000), 1)
    eq(I18n.pt.empty_body(1, 2026):find("Falta 1 minuto de leitura", 1, true) ~= nil, true)
    eq(I18n.pt.cover_notice(4, 2026), "Faltam 4 minutos de leitura para a retrospectiva de 2026 aparecer.")
    eq(I18n.en.cover_notice(1, 2026), "Just 1 more minute of reading until your 2026 review appears.")
    eq(I18n.es.empty_body(4, 2026):find("Faltan 4 minutos", 1, true) ~= nil, true)
end)
test("the cover carries the current year notice, apart from the card text", function()
    local metrics = compute({ { 1, at(1, 1, 10), 700, 1, 100 } })
    local cover = Cards.build(metrics, { books = BOOKS, strings = I18n.pt, notice = "aviso" })[1]
    eq(cover.notice, "aviso"); eq(cover.body, nil)
end)
test("a year in progress says it compares the same period", function()
    local metrics = compute({ { 1, at(1, 1, 10), 700, 1, 100 } }, { previous_seconds = 1400 })
    local function kicker(lang, in_progress)
        for _, card in ipairs(Cards.build(metrics, { books = BOOKS, strings = I18n[lang], in_progress = in_progress })) do
            if card.id == "previous" then return card.kicker end
        end
    end
    eq(kicker("pt", false), "Em relação a 2025")
    eq(kicker("pt", true), "Em relação ao mesmo período de 2025")
    eq(kicker("en", true), "Compared to the same period of 2025")
    eq(kicker("es", true), "Frente al mismo período de 2025")
end)

-- Each profile must be reachable from real reading rows, not only from hand-made metrics.
local function sessions(list)
    local rows, page = {}, 0
    for _, s in ipairs(list) do
        for minute = 0, s.minutes - 1, 2 do
            page = page + 1
            rows[#rows + 1] = { s.book or 1, at(s.month, s.day, s.hour, 0) + minute * 60, 120, page % 90 + 1, 100 }
        end
    end
    table.sort(rows, function(a, b) return a[2] < b[2] end)
    return rows
end
test("every profile is reachable with real reading", function()
    local function profile(list, books, now)
        local m = Stats.compute{ year = 2026, books = books or BOOKS, rows = sessions(list), now = now or at(12, 31, 12) }
        return Stats.archetype(m).id
    end
    local function ten_days(hour)
        local list = {}
        for day = 1, 10 do list[day] = { month = 3, day = day * 2, hour = hour, minutes = 30 } end
        return list
    end
    local no_author = { [1] = { title = "T", authors = "N/A", pages = 100 } }
    eq(profile(ten_days(23), no_author), "night_owl")
    eq(profile(ten_days(7), no_author), "early_bird")
    local daily = {}
    for day = 1, 25 do daily[day] = { month = 1, day = day, hour = 15, minutes = 20 } end
    eq(profile(daily, no_author, at(1, 25, 20)), "steady")
    local long = {}
    for day = 1, 5 do long[day] = { month = 1, day = day * 2, hour = 13, minutes = 130 } end
    eq(profile(long), "marathoner")
    eq(profile({ { month = 1, day = 6, hour = 15, minutes = 40, book = 1 }, { month = 1, day = 8, hour = 15, minutes = 30, book = 2 } }), "loyal")
    local weekend = {}
    for day = 1, 31 do
        local wday = os.date("*t", at(3, day, 12)).wday
        if wday == 1 or wday == 7 then weekend[#weekend + 1] = { month = 3, day = day, hour = 15, minutes = 30 } end
    end
    eq(profile(weekend, no_author), "weekender")
    local many, authors = {}, {}
    for i = 1, 6 do
        authors[i] = { title = "L" .. i, authors = "Autor " .. i, pages = 100 }
        many[i] = { month = 1, day = 5 + (i - 1) * 2, hour = 15, minutes = 40, book = i }
    end
    eq(profile(many, authors), "explorer")
    eq(profile({ { month = 3, day = 4, hour = 15, minutes = 20, book = 1 }, { month = 3, day = 6, hour = 16, minutes = 20, book = 3 } }), "curious")
end)
test("profile picks the strongest trait", function()
    local base = { night_share = 0, morning_share = 0, weekend_share = 0, longest_streak = 0, days_read = 20, consistency = 0, longest_session_seconds = 0, top_sessions_seconds = 0, authors = {}, authors_read = 0, effective_authors = 0, books = {}, total_seconds = 1000 }
    local function with(fields)
        local m = {}
        for k, v in pairs(base) do m[k] = v end
        for k, v in pairs(fields) do m[k] = v end
        return Stats.archetype(m)
    end
    eq(with{ night_share = 0.55 }.id, "night_owl")
    eq(with{ night_share = 0.5 }.id, "curious")
    eq(with{ morning_share = 0.42 }.id, "early_bird")
    eq(with{ longest_streak = 30 }.id, "steady")
    eq(with{ consistency = 0.5 }.id, "steady")
    eq(with{ top_sessions_seconds = 5400 }.id, "marathoner")
    eq(with{ authors = { { name = "A", books = 2, long_books = 2, seconds = 900 } }, effective_authors = 1 }.id, "loyal")
    eq(with{ authors = { { name = "A", books = 1, long_books = 1, seconds = 900 } }, effective_authors = 1 }.id, "curious")
    eq(with{ authors = { { name = "A", books = 2, long_books = 2, seconds = 100 } }, effective_authors = 1 }.id, "curious")
    eq(with{ weekend_share = 0.6 }.id, "weekender")
    eq(with{ effective_authors = 5, authors_read = 5 }.id, "explorer")
    eq(with{}.id, "curious")
    eq(with{ night_share = 0.55, longest_streak = 110 }.id, "steady")
    eq(with{ night_share = 0.85, longest_streak = 40 }.id, "night_owl")
    eq(with{ night_share = 0.5, morning_share = 0.5 }.id, "early_bird")
end)
test("the next trait becomes secondary", function()
    local base = { night_share = 0, morning_share = 0, weekend_share = 0, longest_streak = 0, days_read = 20, consistency = 0, longest_session_seconds = 0, top_sessions_seconds = 0, authors = {}, authors_read = 0, effective_authors = 0, books = {}, total_seconds = 1000 }
    local function with(fields)
        for k, v in pairs(base) do if fields[k] == nil then fields[k] = v end end
        return Stats.archetype(fields)
    end
    local both = with{ night_share = 0.8, effective_authors = 6, authors_read = 6 }
    eq(both.id, "night_owl"); eq(both.secondary, "explorer")
    local reversed = with{ night_share = 0.55, weekend_share = 0.8 }
    eq(reversed.id, "weekender"); eq(reversed.secondary, "night_owl")
    eq(with{ night_share = 0.8 }.secondary, nil)
    local books, list = {}, {}
    for i = 1, 8 do
        books[i] = { title = "L" .. i, authors = "Autor " .. i, pages = 100 }
        list[i] = { month = 1, day = i * 2, hour = 23, minutes = 40, book = i }
    end
    local metrics = compute(sessions(list), { books = books })
    local text
    for _, card in ipairs(Cards.build(metrics, { books = books, strings = I18n.pt })) do
        if card.id == "archetype" then text = card.body end
    end
    eq(text:find("Com toques de Explorador.", 1, true) ~= nil, true)
end)
test("a few days do not define a habit", function()
    local night = {}
    for day = 1, 6 do night[day] = { month = 3, day = day * 2, hour = 23, minutes = 30 } end
    local no_author = { [1] = { title = "T", authors = "N/A", pages = 100 } }
    eq(Stats.archetype(compute(sessions({ night[1] }), { books = no_author })).id, "curious")
    eq(Stats.archetype(compute(sessions(night), { books = no_author })).id, "curious")
end)
test("reading only in January is not steady", function()
    local list = {}
    for day = 1, 15 do list[day] = { month = 1, day = day, hour = 15, minutes = 20 } end
    local m = compute(sessions(list))
    eq(m.longest_streak, 15); eq(m.consistency, 15 / 365)
    eq(Stats.archetype(m).id == "steady", false)
end)
test("consistency of a year in progress counts past days only", function()
    local list = {}
    for day = 1, 15 do list[day] = { month = 1, day = day, hour = 15, minutes = 20 } end
    eq(compute(sessions(list), { now = at(1, 15, 20) }).consistency, 1)
end)
test("one huge session does not outweigh the whole year", function()
    local list = {}
    for day = 1, 20 do list[day] = { month = 2, day = day, hour = 23, minutes = 25 } end
    list[#list + 1] = { month = 8, day = 3, hour = 23, minutes = 420 }
    local m = compute(sessions(list), { books = { [1] = { title = "T", authors = "N/A", pages = 100 } } })
    eq(m.longest_session_seconds, 25200)
    eq(Stats.archetype(m).id, "night_owl")
end)
test("repeated long sessions make the marathoner", function()
    local list = {}
    for day = 1, 5 do list[day] = { month = 2, day = day * 3, hour = 14, minutes = 300 } end
    local m = compute(sessions(list), { books = { [1] = { title = "T", authors = "N/A", pages = 100 } } })
    eq(m.top_sessions_seconds, 18000)
    eq(Stats.archetype(m).id, "marathoner")
end)
test("authors opened for a few minutes do not make an explorer", function()
    local books, rows = {}, {}
    for i = 1, 8 do
        books[i] = { title = "L" .. i, authors = "Autor " .. i, pages = 100 }
        rows[i] = { i, at(1, i * 2, 15), 61, 1, 100 }
    end
    local m = compute(rows, { books = books })
    eq(#m.authors, 8); eq(m.authors_read, 0)
    eq(Stats.archetype(m).id, "curious")
end)
test("a dominant author lowers the effective number of authors", function()
    local books = {
        { title = "A", authors = "Um", pages = 100 }, { title = "B", authors = "Dois", pages = 100 },
        { title = "C", authors = "Tres", pages = 100 },
    }
    local even = compute({ { 1, at(1, 2, 15), 3600, 1, 100 }, { 2, at(1, 3, 15), 3600, 1, 100 }, { 3, at(1, 4, 15), 3600, 1, 100 } }, { books = books })
    eq(math.floor(even.effective_authors + 0.5), 3)
    local dominant = compute({ { 1, at(1, 2, 15), 72000, 1, 100 }, { 2, at(1, 3, 15), 1800, 1, 100 }, { 3, at(1, 4, 15), 1800, 1, 100 } }, { books = books })
    eq(dominant.effective_authors < 1.2, true); eq(dominant.authors_read, 3)
end)
test("the devoured book is the fastest read from start to end in the year", function()
    local books = {
        [1] = { title = "Lento", authors = "A", pages = 100 },
        [2] = { title = "Rápido", authors = "B", pages = 120 },
        [3] = { title = "Antigo", authors = "C", pages = 90 },
        [4] = { title = "Curto", authors = "D", pages = 10 },
        [5] = { title = "Sem Fim", authors = "E", pages = 200 },
    }
    local rows = {}
    local function add(list)
        for _, row in ipairs(list) do rows[#rows + 1] = row end
    end
    add(pages_read(1, 1, 50, 100, at(1, 1, 10))); add(pages_read(1, 51, 100, 100, at(1, 20, 10)))
    add(pages_read(3, 1, 90, 90, at(2, 1, 10)))
    add(pages_read(2, 1, 60, 120, at(3, 1, 10))); add(pages_read(2, 61, 120, 120, at(3, 3, 10)))
    add(pages_read(4, 1, 10, 10, at(4, 1, 10)))
    add(pages_read(5, 1, 40, 200, at(5, 1, 10)))
    local m = Stats.compute{ year = 2026, books = books, rows = rows, earlier_pages = earlier(3, 1, 10, 90), now = at(12, 31, 12) }
    eq(m.devoured.book.title, "Rápido")
    eq(m.devoured.days, 3)
    eq(m.devoured.pages_per_day, 40)
end)
test("no eligible book means no devoured book", function()
    local m = compute({ { 1, at(1, 1, 10), 200, 1, 100 } })
    eq(m.devoured, nil)
end)
test("timeline groups finished books by the month of the last reading", function()
    local rows = pages_read(1, 1, 50, 100, at(1, 5, 10))
    for _, row in ipairs(pages_read(1, 51, 100, 100, at(3, 2, 10))) do rows[#rows + 1] = row end
    for _, row in ipairs(pages_read(2, 1, 200, 200, at(3, 9, 10))) do rows[#rows + 1] = row end
    local m = compute(rows)
    local timeline
    for _, card in ipairs(Cards.build(m, { books = BOOKS, strings = I18n.pt })) do
        if card.id == "timeline" then timeline = card end
    end
    eq(#timeline.months_books[1], 0)
    eq(#timeline.months_books[3], 2)
    eq(timeline.months_books[3][1].title, "Livro A")
    eq(timeline.label, "2 livros lidos até o fim")
end)
test("language follows KOReader, with English for the others", function()
    eq(I18n.language_from("pt_BR"), "pt"); eq(I18n.language_from("pt"), "pt"); eq(I18n.language_from("en_GB"), "en")
    eq(I18n.language_from("es"), "es"); eq(I18n.language_from("fr"), "en"); eq(I18n.language_from(nil), "en")
    eq(I18n.language_from("language_from"), "en")
end)
test("the three languages have the same texts", function()
    for key, value in pairs(I18n.pt) do
        for _, lang in ipairs({ "en", "es" }) do
            eq(type(I18n[lang][key]), type(value))
        end
    end
    for _, lang in ipairs({ "en", "es" }) do
        for key in pairs(I18n[lang]) do eq(I18n.pt[key] ~= nil, true) end
    end
    for id in pairs(I18n.pt.profiles) do
        eq(I18n.en.profiles[id] ~= nil, true); eq(I18n.es.profiles[id] ~= nil, true)
    end
end)
test("every profile builds its text in the three languages", function()
    local values = {
        night_owl = { 50 }, early_bird = { 50 }, steady = { 70, 30 }, marathoner = { 150 },
        loyal = { 60, "Ana Lima", 2 }, weekender = { 55 }, explorer = { 6 }, curious = { 1, 1 },
    }
    for _, lang in ipairs({ "pt", "en", "es" }) do
        for id, v in pairs(values) do
            local name, reason = Cards.profile_text({ id = id, values = v }, I18n[lang])
            eq(#name > 0, true); eq(#reason > 0, true); eq(reason:find("%", 1, true) == nil or id ~= "curious", true)
        end
    end
end)
test("date and number follow the language", function()
    local rows = { { 1, at(7, 18, 21), 700, 1, 100 }, { 1, at(7, 19, 21), 700, 2, 100 } }
    local function card(lang, id)
        for _, c in ipairs(Cards.build(compute(rows), { books = BOOKS, strings = I18n[lang] })) do
            if c.id == id then return c end
        end
    end
    eq(card("pt", "best_day").big_text, "18 de julho")
    eq(card("en", "best_day").big_text, "July 18")
    eq(card("es", "best_day").big_text, "18 de julio")
    eq(card("en", "time").kicker, "You spent reading")
    eq(card("es", "time").label, "en 2 días")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
