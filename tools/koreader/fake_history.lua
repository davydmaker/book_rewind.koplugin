local SQ3 = require("lua-ljsqlite3/init")

local FakeHistory = {}

-- Same schema as KOReader's statistics plugin (user_version 20221111), so the file can stand in for a real one.
local SCHEMA = [[
CREATE TABLE book (id integer PRIMARY KEY autoincrement, title text, authors text, notes integer, last_open integer, highlights integer, pages integer, series text, language text, md5 text, total_read_time integer, total_read_pages integer);
CREATE UNIQUE INDEX book_title_authors_md5 ON book(title, authors, md5);
CREATE TABLE page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0, start_time integer NOT NULL DEFAULT 0, duration integer NOT NULL DEFAULT 0, total_pages integer NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time), FOREIGN KEY(id_book) REFERENCES book(id));
CREATE INDEX page_stat_data_start_time ON page_stat_data(start_time);
CREATE TABLE numbers (number INTEGER PRIMARY KEY);
CREATE VIEW page_stat AS SELECT id_book, first_page + idx - 1 AS page, start_time, duration / (last_page - first_page + 1) AS duration FROM (SELECT id_book, page, total_pages, pages, start_time, duration, ((page - 1) * pages) / total_pages + 1 AS first_page, max(((page - 1) * pages) / total_pages + 1, (page * pages) / total_pages) AS last_page, idx FROM page_stat_data JOIN book ON book.id = id_book JOIN (SELECT number as idx FROM numbers) AS N ON idx <= (last_page - first_page + 1));
PRAGMA user_version = 20221111;
]]

-- { title, authors, pages, share of the book to read, seconds per page, series = , highlights = , notes = }.
-- The share below 0.9 makes an abandoned book.
local PREVIOUS_YEAR = {
    { "A Hora da Estrela", "Clarice Lispector", 88, 1, 55 },
    { "Capitães da Areia", "Jorge Amado", 280, 1, 50 },
    { "O Hobbit", "J.R.R. Tolkien", 320, 1, 60 },
    { "Quarto de Despejo", "Carolina Maria de Jesus", 200, 1, 55 },
}
local NIGHT_YEAR = {
    { "O Nome da Rosa", "Umberto Eco", 520, 1, 60 },
    { "Drácula", "Bram Stoker", 400, 1, 52 },
    { "Frankenstein", "Mary Shelley", 280, 1, 50 },
}
local STEADY_YEAR = {
    { "Os Sertões", "Euclides da Cunha", 640, 1, 72 },
    { "Iracema", "José de Alencar", 160, 1, 50, highlights = 84, notes = 9 },
    { "Moby Dick", "Herman Melville", 720, 0.8, 62 },
    { "Guerra e Paz", "Liev Tolstói", 1200, 0.6, 70 },
}
local LOYAL_YEAR = {
    { "O Leão, a Feiticeira e o Guarda-Roupa", "C.S. Lewis", 180, 1, 55, series = "As Crônicas de Nárnia #1" },
    { "Príncipe Caspian", "C.S. Lewis", 210, 1, 58, series = "As Crônicas de Nárnia #2" },
    { "A Viagem do Peregrino da Alvorada", "C.S. Lewis", 220, 1, 56, series = "As Crônicas de Nárnia #3" },
    { "A Cadeira de Prata", "C.S. Lewis", 230, 1, 56, series = "As Crônicas de Nárnia #4" },
    { "O Primo Basílio", "Eça de Queirós", 120, 0.5, 50 },
}
local EXPLORER_YEAR = {
    { "O Pequeno Príncipe", "Antoine de Saint-Exupéry", 96, 1, 40 },
    { "A Metamorfose", "Franz Kafka", 110, 1, 48 },
    { "O Estrangeiro", "Albert Camus", 140, 1, 50 },
    { "Fahrenheit 451", "Ray Bradbury", 200, 1, 46 },
    { "O Velho e o Mar", "Ernest Hemingway", 120, 1, 44 },
    { "Ensaio sobre a Cegueira", "José Saramago", 260, 0.6, 60 },
    { "Cem Anos de Solidão", "Gabriel García Márquez", 380, 0.3, 58 },
}
local CURIOUS_YEAR = {
    { "O Guarani", "José de Alencar", 240, 0.35, 55 },
    { "A Moreninha", "Joaquim Manuel de Macedo", 200, 0.25, 50 },
}
local TWO_YEARS_AGO = {
    { "Vidas Secas", "Graciliano Ramos", 176, 0.5, 58 },
    { "Dom Quixote", "Miguel de Cervantes", 900, 0.45, 60 },
    { "O Cortiço", "Aluísio Azevedo", 300, 1, 55 },
    { "Orgulho e Preconceito", "Jane Austen", 420, 1, 52 },
    { "Manual Sem Autor", "N/A", 90, 0.2, 35 },
}
local THIS_YEAR = {
    { "Dom Casmurro", "Machado de Assis", 256, 1, 62 },
    { "1984", "George Orwell", 416, 1, 48 },
    { "Vidas Secas", "Graciliano Ramos", 176, 1, 58 },
    { "Duna", "Frank Herbert", 680, 0.55, 45 },
    { "Memórias Póstumas de Brás Cubas", "Machado de Assis", 240, 1, 66 },
    { "O Alquimista", "Paulo Coelho", 180, 1, 40 },
    { "A Casa das Marés: uma Ficção Inventada para Testes", "Helena Vargas", 310, 0.92, 52 },
    { "Manual Sem Autor", "N/A", 90, 0.3, 35 },
    { "O Hobbit", "J.R.R. Tolkien", 320, 1, 55 },
    { "A Sociedade do Anel", "J.R.R. Tolkien", 520, 1, 58 },
    { "Grande Sertão: Veredas", "Guimarães Rosa", 608, 1, 70 },
}

local function escape(text)
    return (text:gsub("'", "''"))
end

function FakeHistory.write(path, now)
    now = now or os.time()
    os.remove(path)
    local conn = SQ3.open(path)
    conn:exec(SCHEMA)
    conn:exec("BEGIN")
    for i = 1, 2000 do
        conn:exec(string.format("INSERT INTO numbers VALUES (%d)", i))
    end
    local ids = {}
    local function book_id(book)
        local key = book[1] .. "|" .. book[2]
        if not ids[key] then
            conn:exec(string.format("INSERT INTO book (title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages) VALUES ('%s', '%s', %d, %d, %d, %d, '%s', 'pt', '%032x', 0, 0)", escape(book[1]), escape(book[2]), book.notes or 0, now, book.highlights or 0, book[3], escape(book.series or "N/A"), #ids + 1 + (ids.count or 0)))
            ids.count = (ids.count or 0) + 1
            ids[key] = ids.count
        end
        return ids[key]
    end
    conn:exec(string.format("INSERT INTO book (title, authors, pages, md5) VALUES ('privesc_marker', 'N/A', 1, 'residual')"))
    ids.count = 1
    conn:exec(string.format("INSERT INTO page_stat_data VALUES (1, 1, %d, 34, 1)", os.time{ year = tonumber(os.date("%Y", now)), month = 1, day = 2, hour = 12 }))

    local random = math.random
    local rows = 0
    -- One year per reader profile. Each year has its own seed, so adding a year does not change the others.
    local function read_year(year, books, stop, habits)
        math.randomseed(year)
        local book_index, page = 1, 1
        local day = os.time{ year = year, month = 1, day = 3, hour = 12 }
        local last = os.time{ year = year, month = 12, day = 31, hour = 12 }
        local streak_left = 0
        while day <= last and day < stop and book_index <= #books do
            local date = os.date("*t", day)
            local weekend = date.wday == 1 or date.wday == 7
            if habits.streak and streak_left == 0 and date.month == 9 and date.day == 1 then
                streak_left = habits.streak
            end
            local marathon = habits.marathon and date.month == 7 and date.day >= 18 and date.day <= 22
            local chance = habits.reading_days + (weekend and habits.weekend_bonus or 0)
            local reads = marathon or streak_left > 0 or random() < chance
            if streak_left > 0 then
                streak_left = streak_left - 1
            end
            if reads then
                local sessions = (weekend and random() < 0.4) and 2 or 1
                for session = 1, sessions do
                    local t = os.time{ year = date.year, month = date.month, day = date.day, hour = habits.hour(session), min = random(0, 45) }
                    local minutes = math.floor((weekend and random(20, 55) or random(8, 28)) * habits.pace)
                    if marathon and session == 1 then
                        minutes = 240
                    end
                    local spent = 0
                    while spent < minutes * 60 and book_index <= #books and t < stop do
                        local book = books[book_index]
                        local id = book_id(book)
                        local duration = math.min(120, math.max(5, book[5] + random(-15, 25)))
                        conn:exec(string.format("INSERT OR IGNORE INTO page_stat_data VALUES (%d, %d, %d, %d, %d)", id, page, t, duration, book[3]))
                        rows = rows + 1
                        spent = spent + duration
                        t = t + duration
                        page = page + 1
                        if page > math.floor(book[3] * book[4]) then
                            book_index, page = book_index + 1, 1
                        end
                    end
                end
            end
            day = day + 86400
        end
    end
    local year = tonumber(os.date("%Y", now))
    local afternoon = function() return random(14, 17) end
    read_year(year - 8, CURIOUS_YEAR, now, { reading_days = 0.06, weekend_bonus = -0.05, pace = 0.5, hour = afternoon })
    read_year(year - 6, EXPLORER_YEAR, now, { reading_days = 0.3, weekend_bonus = -0.25, pace = 0.45, hour = afternoon })
    read_year(year - 5, LOYAL_YEAR, now, { reading_days = 0.2, weekend_bonus = -0.02, pace = 0.55, hour = afternoon })
    read_year(year - 4, STEADY_YEAR, now, { reading_days = 0.85, weekend_bonus = 0, pace = 0.3, hour = afternoon })
    read_year(year - 3, NIGHT_YEAR, now, { reading_days = 0.2, weekend_bonus = 0.05, pace = 0.45, hour = function() return 23 end })
    read_year(year - 2, TWO_YEARS_AGO, now, {
        reading_days = 0.02, weekend_bonus = 0.5, pace = 0.75,
        hour = function() return 15 end,
    })
    read_year(year - 1, PREVIOUS_YEAR, now, {
        reading_days = 0.2, weekend_bonus = 0.2, pace = 0.45,
        hour = function() return random(6, 8) end,
    })
    read_year(year, THIS_YEAR, now, {
        reading_days = 0.34, weekend_bonus = 0.2, pace = 0.68, streak = 24, marathon = true,
        hour = function(session)
            if session == 2 then return 15 end
            return random() < 0.15 and 7 or 21 + random(0, 2)
        end,
    })

    -- Reading scenes that the habits above do not produce, so every wildcard shows up in some year.
    local function read_span(book, first_page, last_page, start, seconds)
        local id = book_id(book)
        for page = first_page, last_page do
            local t = start + (page - first_page) * seconds
            if t < now then
                conn:exec(string.format("INSERT OR IGNORE INTO page_stat_data VALUES (%d, %d, %d, %d, %d)", id, page, t, seconds, book[3]))
                rows = rows + 1
            end
        end
    end
    local function moment(wanted_year, month, day, hour, minute)
        return os.time{ year = wanted_year, month = month, day = day, hour = hour, min = minute or 0 }
    end
    -- Waited for months: half a book in February, the rest in August.
    local waited = { "Noites Brancas", "Fiódor Dostoiévski", 150 }
    read_span(waited, 1, 70, moment(year - 6, 2, 8, 15), 50)
    read_span(waited, 71, 150, moment(year - 6, 8, 20, 15), 50)
    -- A whole book on one Saturday.
    local saturday = moment(year - 2, 5, 1, 12)
    while os.date("*t", saturday).wday ~= 7 do
        saturday = saturday + 86400
    end
    read_span({ "Noite na Taverna", "Álvares de Azevedo", 150 }, 1, 150, saturday + 3600, 55)
    -- Reading past midnight, again and again.
    local tales = { "Histórias Extraordinárias", "Edgar Allan Poe", 900 }
    local next_page = 1
    for night = 1, 16 do
        local pages = night == 16 and 200 or 45
        read_span(tales, next_page, next_page + pages - 1, moment(year - 3, 9, night * 2, 23, 25), 60)
        next_page = next_page + pages
    end
    -- A tiny book in the same year as a huge one.
    read_span({ "A Cartomante", "Machado de Assis", 32 }, 1, 32, moment(year - 4, 6, 6, 15), 60)
    -- One very fast book next to the slower ones.
    read_span({ "Poemas Breves", "Paulo Leminski", 120 }, 1, 120, moment(year - 1, 4, 11, 7), 18)
    -- Several books open at once in March.
    for index, book in ipairs({
        { "Contos Novos", "Mário de Andrade", 200 },
        { "Sagarana", "João Guimarães Rosa", 260 },
        { "Laços de Família", "Clarice Lispector", 180 },
        { "A Hora dos Ruminantes", "José J. Veiga", 220 },
        { "Primeiras Estórias", "João Guimarães Rosa", 200 },
    }) do
        read_span(book, 1, 30, moment(year, 3, 8 + index, 15), 60)
        read_span(book, 31, 60, moment(year, 3, 18 + index, 15), 60)
    end
    conn:exec("COMMIT")
    conn:exec("UPDATE book SET total_read_time = (SELECT COALESCE(SUM(duration), 0) FROM page_stat_data WHERE id_book = book.id), total_read_pages = (SELECT COUNT(DISTINCT page) FROM page_stat_data WHERE id_book = book.id)")
    conn:close()
    return rows
end

-- A cache with the schema of the Cover browser plugin and one solid black cover per book,
-- to prove that a real cover wins over a generated one.
local COVER_SCHEMA = [[
CREATE TABLE bookinfo (bcid INTEGER PRIMARY KEY AUTOINCREMENT, directory TEXT NOT NULL, filename TEXT NOT NULL, filesize INTEGER, filemtime INTEGER, in_progress INTEGER, unsupported TEXT, cover_fetched TEXT, has_meta TEXT, has_cover TEXT, cover_sizetag TEXT, ignore_meta TEXT, ignore_cover TEXT, pages INTEGER, title TEXT, authors TEXT, series TEXT, series_index REAL, language TEXT, keywords TEXT, description TEXT, cover_w INTEGER, cover_h INTEGER, cover_bb_type INTEGER, cover_bb_stride INTEGER, cover_bb_data BLOB);
CREATE UNIQUE INDEX dir_filename ON bookinfo(directory, filename);
CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT);
PRAGMA user_version = 20201210;
]]

-- opts.file_names: the cache keeps no title, only the file name, as for PDFs and CBZs without metadata.
function FakeHistory.write_real_covers(path, opts)
    opts = opts or {}
    local Blitbuffer = require("ffi/blitbuffer")
    local zstd = require("ffi/zstd")
    os.remove(path)
    local conn = SQ3.open(path)
    conn:exec(COVER_SCHEMA)
    local insert = conn:prepare("INSERT INTO bookinfo (directory, filename, in_progress, cover_fetched, has_meta, has_cover, pages, title, authors, cover_w, cover_h, cover_bb_type, cover_bb_stride, cover_bb_data) VALUES (?, ?, 0, 'Y', 'Y', 'Y', ?, ?, ?, ?, ?, ?, ?, ?)")
    for index, book in ipairs(THIS_YEAR) do
        local w, h = 200, 300
        local cover = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        cover:fill(Blitbuffer.COLOR_BLACK)
        local data, compressed = zstd.zstd_compress(cover.data, tonumber(cover.stride) * h)
        if opts.file_names then
            insert:reset():bind("/fake/", book[1] .. ".cbz", book[3], nil, nil, w, h, cover:getType(), tonumber(cover.stride), SQ3.blob(data, compressed)):step()
        else
            insert:reset():bind("/fake/", index .. ".epub", book[3], book[1], book[2], w, h, cover:getType(), tonumber(cover.stride), SQ3.blob(data, compressed)):step()
        end
        cover:free()
    end
    insert:close()
    conn:close()
end

return FakeHistory
