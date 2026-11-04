local SQ3 = require("lua-ljsqlite3/init")
local ffi = require("ffi")
local logger = require("logger")

local Store = {}

local function open(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    file:close()
    local ok, conn = pcall(SQ3.open, path, "ro")
    return ok and conn or nil
end

-- The connection is always closed, and a database that cannot be read counts as having no data.
local function with_connection(path, work)
    local conn = open(path)
    if not conn then
        return nil
    end
    local ok, result = pcall(work, conn)
    conn:close()
    if not ok then
        logger.warn("Book Rewind: could not read", path, result)
        return nil
    end
    return result
end

local function year_bounds(year)
    return os.time{ year = year, month = 1, day = 1, hour = 0 }, os.time{ year = year + 1, month = 1, day = 1, hour = 0 }
end

local function number(value)
    return tonumber(value) or 0
end

local function single_value(conn, query)
    local result = conn:exec(query)
    return result and tonumber(result[1][1]) or nil
end

local function seconds_in_year(conn, year)
    local first, after = year_bounds(year)
    return single_value(conn, string.format("SELECT SUM(duration) FROM page_stat_data WHERE start_time >= %d AND start_time < %d", first, after)) or 0
end

function Store.year_seconds(path, year)
    return with_connection(path, function(conn) return seconds_in_year(conn, year) end) or 0
end

-- The years with at least min_seconds of reading, newest first. Walks the start_time index,
-- so the cost follows the number of years and not the number of pages read.
function Store.years(path, min_seconds)
    return with_connection(path, function(conn)
        local years = {}
        local time = single_value(conn, "SELECT MIN(start_time) FROM page_stat_data")
        while time do
            local year = os.date("*t", time).year
            local _, after = year_bounds(year)
            if seconds_in_year(conn, year) >= (min_seconds or 0) then
                table.insert(years, 1, year)
            end
            time = single_value(conn, string.format("SELECT MIN(start_time) FROM page_stat_data WHERE start_time >= %d", after))
        end
        return years
    end) or {}
end

-- A year in progress is compared with the same part of the previous one, not with all of it.
local function previous_period_end(year, first, now)
    local today = os.date("*t", now)
    if today.year ~= year then
        return first
    end
    today.year = year - 1
    today.isdst = nil
    return math.min(first, os.time(today))
end

function Store.load_year(path, year, now)
    return with_connection(path, function(conn)
        local first, after = year_bounds(year)
        local rows = {}
        local result = conn:exec(string.format(
            "SELECT id_book, start_time, duration, page, total_pages FROM page_stat_data WHERE start_time >= %d AND start_time < %d ORDER BY start_time",
            first, after))
        if result then
            for i = 1, #result[1] do
                rows[i] = { number(result[1][i]), number(result[2][i]), number(result[3][i]), number(result[4][i]), number(result[5][i]) }
            end
        end

        local books = {}
        result = conn:exec("SELECT id, title, authors, pages FROM book")
        if result then
            for i = 1, #result[1] do
                books[number(result[1][i])] = { title = result[2][i], authors = result[3][i], pages = number(result[4][i]) }
            end
        end

        local earlier_pages = {}
        result = conn:exec(string.format(
            "SELECT DISTINCT id_book, page, total_pages FROM page_stat_data WHERE start_time < %d AND total_pages > 0 AND id_book IN (SELECT id_book FROM page_stat_data WHERE start_time >= %d AND start_time < %d)",
            first, first, after))
        if result then
            for i = 1, #result[1] do
                earlier_pages[i] = { number(result[1][i]), number(result[2][i]), number(result[3][i]) }
            end
        end

        local previous_first = year_bounds(year - 1)
        local previous_seconds = single_value(conn, string.format(
            "SELECT SUM(duration) FROM page_stat_data WHERE start_time >= %d AND start_time < %d",
            previous_first, previous_period_end(year, first, now or os.time())))
        return { rows = rows, books = books, earlier_pages = earlier_pages, previous_seconds = previous_seconds or 0, year = year }
    end)
end

-- Covers live in the cache of the Cover browser plugin, found here by title and author.
function Store.load_cover(path, title, authors)
    return with_connection(path, function(conn)
        local Blitbuffer = require("ffi/blitbuffer")
        local zstd = require("ffi/zstd")
        local query = "SELECT cover_w, cover_h, cover_bb_type, cover_bb_stride, cover_bb_data FROM bookinfo WHERE has_cover = 'Y' AND cover_bb_data IS NOT NULL AND title = ?"
        local cover
        local function read(statement)
            local row = statement:step()
            if row then
                local w, h, kind, stride = tonumber(row[1]), tonumber(row[2]), tonumber(row[3]), tonumber(row[4])
                local data, size = zstd.zstd_uncompress_ctx(row[5][1], row[5][2])
                if size == stride * h then
                    cover = Blitbuffer.new(w, h, kind, data, stride)
                    cover:setAllocated(1)
                else
                    ffi.C.free(data)
                end
            end
            statement:clearbind():reset()
        end
        local statement = conn:prepare(query .. " AND authors = ?")
        read(statement:bind(title, authors or ""))
        statement:close()
        if not cover then
            statement = conn:prepare(query)
            read(statement:bind(title))
            statement:close()
        end
        return cover
    end)
end

return Store
