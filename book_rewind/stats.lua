local Stats = {}

local SESSION_GAP = 300
local MIN_BOOK_SECONDS = 60
local MIN_AUTHOR_SECONDS = 1800
local FINISHED_FRACTION = 0.9
local DEVOURED_MIN_PAGES = 30
local COVERAGE_STEPS = 1000
local TOP_SESSIONS = 5
local MIN_PATTERN_DAYS = 7
local MIN_STEADY_DAYS = 14
local NIGHT_HOURS = { [22] = true, [23] = true, [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
local MORNING_HOURS = { [5] = true, [6] = true, [7] = true, [8] = true }
local NIGHT_CHANCE, MORNING_CHANCE, WEEKEND_CHANCE = 7 / 24, 4 / 24, 2 / 7

local ACCENTS = {}
for plain, chars in pairs({
    a = "áàâãäÁÀÂÃÄ", c = "çÇ", e = "éèêëÉÈÊË", i = "íìîïÍÌÎÏ", n = "ñÑ", o = "óòôõöÓÒÔÕÖ", u = "úùûüÚÙÛÜ",
}) do
    for char in chars:gmatch("\195[\128-\191]") do
        ACCENTS[char] = plain
    end
end

local function known(value)
    return type(value) == "string" and value ~= "" and value ~= "N/A"
end

function Stats.split_authors(authors)
    local out = {}
    if known(authors) then
        for name in authors:gmatch("[^\n]+") do
            if known(name) then
                out[#out + 1] = name
            end
        end
    end
    return out
end

-- The same person under different spellings: "J.R.R. Tolkien", "Tolkien, J. R. R.", "José"/"Jose".
function Stats.author_key(name)
    local folded = name:gsub("\195[\128-\191]", ACCENTS):lower()
    local words = {}
    for word in folded:gmatch("[%w\128-\255]+") do
        words[#words + 1] = word
    end
    table.sort(words)
    return #words > 0 and table.concat(words, " ") or name
end

-- Time zones change on multiples of 15 minutes, so a bucket never crosses a local hour or day.
local function date_parts(cache, timestamp)
    local key = math.floor(timestamp / 900)
    local parts = cache[key]
    if not parts then
        parts = os.date("*t", timestamp)
        cache[key] = parts
    end
    return parts
end

local function ranked(map)
    local list = {}
    for key, value in pairs(map) do
        list[#list + 1] = { key = key, seconds = value }
    end
    table.sort(list, function(a, b)
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

local function best_index(values, first, last)
    local best
    for i = first, last do
        if values[i] > 0 and (not best or values[i] > values[best]) then
            best = i
        end
    end
    return best
end

local function filled(first, last)
    local values = {}
    for i = first, last do
        values[i] = 0
    end
    return values
end

-- Marks the part of the book a page covers, so the same passage read at another font size counts once.
local function mark_page(marks, page, total)
    if page < 1 or total <= 0 then
        return
    end
    local first = math.floor((page - 1) * COVERAGE_STEPS / total) + 1
    local last = math.max(first, math.floor(page * COVERAGE_STEPS / total))
    for step = first, math.min(last, COVERAGE_STEPS) do
        marks[step] = true
    end
end

local function covered_share(marks, other)
    local steps = 0
    for step = 1, COVERAGE_STEPS do
        if marks[step] or (other and other[step]) then
            steps = steps + 1
        end
    end
    return steps / COVERAGE_STEPS
end

local function days_elapsed(year, now)
    local today = os.date("*t", now)
    if today.year == year then
        return today.yday
    end
    return os.date("*t", os.time{ year = year, month = 12, day = 31, hour = 12 }).yday
end

-- opts.rows must be ordered by start_time. Each row is { book, start, duration, page, total_pages }.
-- opts.earlier_pages has the pages of these books read before the year, each as { book, page, total_pages }.
function Stats.compute(opts)
    local year, books = opts.year, opts.books
    local result = {
        year = year,
        total_seconds = 0,
        hours = filled(0, 23),
        weekdays = filled(1, 7),
        months = filled(1, 12),
        previous_seconds = opts.previous_seconds or 0,
    }
    local cache, days, book_seconds, year_marks = {}, {}, {}, {}
    local book_first, book_last = {}, {}
    local last_end, session_seconds, session_start, session_book_seconds
    local longest = { seconds = 0 }
    local session_lengths = {}

    local function close_session()
        if not session_seconds then
            return
        end
        session_lengths[#session_lengths + 1] = session_seconds
        if session_seconds > longest.seconds then
            local book, most = nil, -1
            for id, seconds in pairs(session_book_seconds) do
                if seconds > most then
                    book, most = id, seconds
                end
            end
            longest = { seconds = session_seconds, start = session_start, book = book }
        end
    end

    for _, row in ipairs(opts.rows) do
        local book, start, duration = row[1], row[2], row[3]
        local parts = date_parts(cache, start)
        if parts.year == year then
            result.total_seconds = result.total_seconds + duration
            result.hours[parts.hour] = result.hours[parts.hour] + duration
            result.weekdays[parts.wday] = result.weekdays[parts.wday] + duration
            result.months[parts.month] = result.months[parts.month] + duration
            days[parts.yday] = (days[parts.yday] or 0) + duration
            book_seconds[book] = (book_seconds[book] or 0) + duration
            if not book_first[book] then
                book_first[book] = start
                year_marks[book] = {}
            end
            book_last[book] = start
            mark_page(year_marks[book], row[4], row[5])

            if not last_end or start - last_end > SESSION_GAP then
                close_session()
                session_seconds, session_start, session_book_seconds = 0, start, {}
            end
            session_seconds = session_seconds + duration
            session_book_seconds[book] = (session_book_seconds[book] or 0) + duration
            last_end = start + duration
        end
    end
    close_session()
    result.longest_session = longest

    local earlier_marks = {}
    for _, row in ipairs(opts.earlier_pages or {}) do
        local marks = earlier_marks[row[1]]
        if not marks then
            marks = {}
            earlier_marks[row[1]] = marks
        end
        mark_page(marks, row[2], row[3])
    end

    table.sort(session_lengths, function(a, b) return a > b end)
    local top_sum = 0
    for i = 1, math.min(TOP_SESSIONS, #session_lengths) do
        top_sum = top_sum + session_lengths[i]
    end
    result.top_sessions_seconds = top_sum / TOP_SESSIONS

    local yday_list = {}
    local best_day = { seconds = 0 }
    for yday, seconds in pairs(days) do
        yday_list[#yday_list + 1] = yday
        if seconds > best_day.seconds or (seconds == best_day.seconds and yday < (best_day.yday or math.huge)) then
            best_day = { yday = yday, seconds = seconds }
        end
    end
    table.sort(yday_list)
    local streak, best_streak, best_streak_end = 0, 0, nil
    for i, yday in ipairs(yday_list) do
        streak = (i > 1 and yday == yday_list[i - 1] + 1) and streak + 1 or 1
        if streak > best_streak then
            best_streak, best_streak_end = streak, yday
        end
    end
    result.days = days
    result.longest_streak_end = best_streak_end
    result.days_read = #yday_list
    result.longest_streak = best_streak
    result.best_day = best_day
    result.first_yday, result.last_yday = yday_list[1], yday_list[#yday_list]
    result.consistency = math.min(1, #yday_list / days_elapsed(year, opts.now or os.time()))

    result.best_hour = best_index(result.hours, 0, 23)
    result.best_weekday = best_index(result.weekdays, 1, 7)
    result.best_month = best_index(result.months, 1, 12)
    local active_months = 0
    for month = 1, 12 do
        if result.months[month] > 0 then
            active_months = active_months + 1
        end
    end
    result.active_months = active_months

    local night, morning = 0, 0
    for hour = 0, 23 do
        if NIGHT_HOURS[hour] then night = night + result.hours[hour] end
        if MORNING_HOURS[hour] then morning = morning + result.hours[hour] end
    end
    local total = result.total_seconds
    result.night_share = total > 0 and night / total or 0
    result.morning_share = total > 0 and morning / total or 0
    result.weekend_share = total > 0 and (result.weekdays[1] + result.weekdays[7]) / total or 0

    result.books, result.finished_books = {}, {}
    local author_names, author_seconds, author_books, author_long_books = {}, {}, {}, {}
    local total_pages = 0
    for _, entry in ipairs(ranked(book_seconds)) do
        local id, seconds = entry.key, entry.seconds
        local book = books[id] or {}
        local page_count = (book.pages and book.pages > 0) and book.pages or 0
        local this_year = covered_share(year_marks[id])
        local read = math.floor(this_year * page_count + 0.5)
        total_pages = total_pages + read
        local earlier = earlier_marks[id]
        local before = earlier and covered_share(earlier) or 0
        local reached_end = covered_share(year_marks[id], earlier) >= FINISHED_FRACTION
        -- The last pages of a book started in another year count, however quick they were.
        local completed_now = earlier ~= nil and before < FINISHED_FRACTION and reached_end
        if seconds >= MIN_BOOK_SECONDS or completed_now then
            -- Finished in the year it reached the end, or in a later year when read again from start to end.
            local finished = reached_end and (before < FINISHED_FRACTION or this_year >= FINISHED_FRACTION)
            local first_date, last_date = date_parts(cache, book_first[id]), date_parts(cache, book_last[id])
            local info = {
                id = id,
                title = known(book.title) and book.title or nil,
                seconds = seconds,
                pages = read,
                total_pages = page_count,
                finished = finished,
                finished_earlier = not finished and before >= FINISHED_FRACTION,
                first_yday = first_date.yday,
                last_yday = last_date.yday,
                last_month = last_date.month,
                last_time = book_last[id],
                started_before_year = earlier ~= nil,
            }
            result.books[#result.books + 1] = info
            if finished then
                result.finished_books[#result.finished_books + 1] = info
            end
            for _, name in ipairs(Stats.split_authors(book.authors)) do
                local key = Stats.author_key(name)
                author_names[key] = author_names[key] or name
                author_seconds[key] = (author_seconds[key] or 0) + seconds
                author_books[key] = (author_books[key] or 0) + 1
                if seconds >= MIN_AUTHOR_SECONDS then
                    author_long_books[key] = (author_long_books[key] or 0) + 1
                end
            end
        end
    end
    result.total_pages = total_pages
    -- The fastest book read from start to end inside this year. Very short files would always win.
    for _, book in ipairs(result.finished_books) do
        if not book.started_before_year and book.total_pages >= DEVOURED_MIN_PAGES then
            local days_taken = book.last_yday - book.first_yday + 1
            local best = result.devoured
            if not best or days_taken < best.days or (days_taken == best.days and book.total_pages > best.book.total_pages) then
                result.devoured = { book = book, days = days_taken, pages_per_day = math.floor(book.total_pages / days_taken + 0.5) }
            end
        end
    end
    result.pages_per_hour = total > 0 and total_pages * 3600 / total or 0

    result.authors = {}
    local authors_read, read_seconds, squared = 0, 0, 0
    for _, entry in ipairs(ranked(author_seconds)) do
        result.authors[#result.authors + 1] = {
            name = author_names[entry.key],
            seconds = entry.seconds,
            books = author_books[entry.key],
            long_books = author_long_books[entry.key] or 0,
        }
        if entry.seconds >= MIN_AUTHOR_SECONDS then
            authors_read = authors_read + 1
            read_seconds = read_seconds + entry.seconds
            squared = squared + entry.seconds * entry.seconds
        end
    end
    result.authors_read = authors_read
    -- How many authors the time really went to: 3 equal authors give 3, and one dominant author gives close to 1.
    result.effective_authors = squared > 0 and read_seconds * read_seconds / squared or 0

    result.longest_session_seconds = longest.seconds
    return result
end

-- A trait counts once it reaches its threshold. The score goes from 1 at the threshold to 2 at
-- what is exceptional for it, and stops there, so one huge number cannot outweigh a whole year.
local function strength(value, threshold, exceptional)
    if value < threshold then
        return 0
    end
    return math.min(2, 1 + (value - threshold) / (exceptional - threshold))
end

-- How far a share goes beyond chance, from 0 to 1, because time windows have different sizes.
-- A few days of reading say nothing about a habit.
local function habit(share, chance, days_read)
    if days_read < MIN_PATTERN_DAYS then
        return 0
    end
    return strength((share - chance) / (1 - chance), 0.3, 0.8)
end

-- The strongest trait wins, and the next one, if any, is returned as secondary.
-- On a tie, the earlier one in the list wins.
function Stats.archetype(metrics)
    local top_author = metrics.authors[1]
    local percent = function(share) return math.floor(share * 100 + 0.5) end
    local author_share = top_author and top_author.seconds / math.max(metrics.total_seconds, 1) or 0
    local concentration = metrics.effective_authors > 0 and 1 / metrics.effective_authors or 0
    local steady_score = strength(metrics.longest_streak, 30, 180)
    if metrics.days_read >= MIN_STEADY_DAYS then
        steady_score = math.max(steady_score, strength(metrics.consistency, 0.4, 0.9))
    end
    local loyal_score = 0
    if top_author and top_author.long_books >= 2 and author_share >= 0.5 then
        loyal_score = strength(concentration, 0.4, 1)
    end
    local candidates = {
        { score = habit(metrics.night_share, NIGHT_CHANCE, metrics.days_read), id = "night_owl", values = { percent(metrics.night_share) } },
        { score = habit(metrics.morning_share, MORNING_CHANCE, metrics.days_read), id = "early_bird", values = { percent(metrics.morning_share) } },
        { score = steady_score, id = "steady", values = { percent(metrics.consistency), metrics.longest_streak } },
        { score = strength(metrics.top_sessions_seconds, 5400, 14400), id = "marathoner", values = { math.floor(metrics.longest_session_seconds / 60) } },
        {
            score = loyal_score,
            id = "loyal",
            values = { percent(author_share), top_author and top_author.name or "", top_author and top_author.long_books or 0 },
        },
        { score = habit(metrics.weekend_share, WEEKEND_CHANCE, metrics.days_read), id = "weekender", values = { percent(metrics.weekend_share) } },
        { score = strength(metrics.effective_authors, 5, 15), id = "explorer", values = { metrics.authors_read } },
    }
    local best, second
    for _, candidate in ipairs(candidates) do
        if candidate.score > 0 then
            if not best or candidate.score > best.score then
                best, second = candidate, best
            elseif not second or candidate.score > second.score then
                second = candidate
            end
        end
    end
    if not best then
        return { id = "curious", values = { #metrics.books, metrics.days_read } }
    end
    best.secondary = second and second.id or nil
    return best
end

return Stats
