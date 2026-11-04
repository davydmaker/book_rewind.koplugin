local SQ3 = require("lua-ljsqlite3/init")

local SampleDb = {}

local SCHEMA = [[
CREATE TABLE book (id integer PRIMARY KEY autoincrement, title text, authors text, notes integer, last_open integer, highlights integer, pages integer, series text, language text, md5 text, total_read_time integer, total_read_pages integer);
CREATE TABLE page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0, start_time integer NOT NULL DEFAULT 0, duration integer NOT NULL DEFAULT 0, total_pages integer NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time));
CREATE INDEX page_stat_data_start_time ON page_stat_data(start_time);
]]

local BOOKS = {
    { "A Casa das Marés", "Helena Vargas", 320 },
    { "O Inventário do Silêncio", "Helena Vargas", 280 },
    { "Crônicas de um Elevador Parado com um Título Bem Comprido de Verdade", "Otávio Brandão", 410 },
    { "Mapa para Lugar Nenhum", "Otávio Brandão\nLia Serrano", 190 },
    { "Manual Sem Autor", "N/A", 120 },
    { "privesc_marker", "N/A", 1 },
}

function SampleDb.write(path, year, opts)
    opts = opts or {}
    os.remove(path)
    local conn = SQ3.open(path)
    conn:exec(SCHEMA)
    local ids = {}
    for i, book in ipairs(BOOKS) do
        conn:exec(string.format("INSERT INTO book (title, authors, pages) VALUES ('%s', '%s', %d)", book[1], book[2], book[3]))
        ids[i] = i
    end
    math.randomseed(opts.seed or 11)
    conn:exec("BEGIN")
    local function session(book, month, day, hour, pages, first_page)
        local t = os.time{ year = opts.year_override or year, month = month, day = day, hour = hour, min = 5 }
        local total = BOOKS[book][3]
        for i = 0, pages - 1 do
            local duration = 30 + math.random(0, 60)
            conn:exec(string.format("INSERT OR IGNORE INTO page_stat_data VALUES (%d, %d, %d, %d, %d)", book, (first_page + i - 1) % total + 1, t, duration, total))
            t = t + duration
        end
    end
    if opts.sparse then
        session(1, 1, 3, 21, 5, 1)
        session(6, 1, 3, 22, 1, 1)
    else
        local page = { 1, 1, 1, 1, 1 }
        for month = 1, 12 do
            for day = 1, 22, 3 do
                local book = (month + day) % 5 + 1
                local hour = day % 4 == 0 and 7 or 21 + day % 3
                local pages = 8 + math.random(0, 25)
                session(book, month, day, hour, pages, page[book])
                page[book] = page[book] + pages
            end
        end
        session(3, 7, 15, 14, 130, 40)
        session(6, 1, 2, 12, 1, 1)
    end
    conn:exec("COMMIT")
    if opts.previous then
        conn:exec("BEGIN")
        -- Early in the year, so it stays inside the period compared with a year in progress.
        local previous_time = os.time{ year = year - 1, month = 1, day = 1, hour = 1 }
        for i = 1, 60 do
            conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, %d, %d, 60, 320)", i, previous_time + i * 60))
        end
        conn:exec("COMMIT")
    end
    conn:close()
end

return SampleDb
