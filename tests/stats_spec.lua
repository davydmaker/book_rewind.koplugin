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
-- The tests write rows as { book, start, duration, page, total_pages }, which is easier to read.
local function run(opts)
    opts.rows = Stats.columns(opts.rows)
    return Stats.compute(opts)
end
local function compute(rows, extra)
    local opts = { year = 2026, books = BOOKS, rows = rows, now = at(12, 31, 12) }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return run(opts)
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
test("placeholders in the author field do not count as authors", function()
    for _, name in ipairs({ "Unknown", "unknown", "Desconhecido", "Autor Desconhecido", "Desconocido", "N/A", "  N/A  " }) do
        eq(#Stats.split_authors(name), 0)
    end
    eq(Stats.split_authors("Unknown\nAna Lima")[1], "Ana Lima")
    local books = { { title = "T", authors = "Unknown", pages = 100 } }
    eq(#compute({ { 1, at(1, 1, 10), 900, 1, 100 } }, { books = books }).authors, 0)
end)
test("titles lose the site mark and the language edition, and nothing else", function()
    eq(Stats.clean_title("20 Regras de Ouro [e-Livros]"), "20 Regras de Ouro")
    eq(Stats.clean_title("Outro Livro [LeLivros.xyz] "), "Outro Livro")
    eq(Stats.clean_title("4 horas para o corpo (Portuguese Edition)"), "4 horas para o corpo")
    eq(Stats.clean_title("Um Livro (Edición en español)"), "Um Livro")
    eq(Stats.clean_title("1984"), "1984")
    eq(Stats.clean_title("A 3ª alternativa: resolvendo problemas"), "A 3ª alternativa: resolvendo problemas")
    eq(Stats.clean_title("Um Título [Parte 1]"), "Um Título [Parte 1]")
    eq(Stats.clean_title("Todas as Suas (Im)perfeições"), "Todas as Suas (Im)perfeições")
    eq(Stats.clean_title("Manual (2ª edição)"), "Manual (2ª edição)")
    eq(Stats.clean_title("[e-Livros]"), "[e-Livros]")
    eq(Stats.clean_title("N/A"), nil); eq(Stats.clean_title("Unknown"), nil); eq(Stats.clean_title(nil), nil)
    local m = compute({ { 1, at(1, 1, 10), 900, 1, 100 } }, { books = { { title = "Um Livro [e-Livros]", authors = "X", pages = 100 } } })
    eq(m.books[1].title, "Um Livro")
end)
test("generic labels, sites and very short names do not count as authors", function()
    for _, name in ipairs({ "Windows User", "USER", "Usuário", "Administrador", "Microsoft Office User", "Vários Autores", "VÁRIOS", "www.example.com", "http://example.net", "Autor Example.com", "m", "HP" }) do
        eq(#Stats.split_authors(name), 0)
    end
    eq(Stats.split_authors("Anônimo")[1], "Anônimo")
end)
test("several authors in one field are separated, but names stay whole", function()
    local function names(field)
        return table.concat(Stats.split_authors(field), "|")
    end
    eq(names("Ana Lima; Bruno Dias"), "Ana Lima|Bruno Dias")
    eq(names("Ana Lima & Bruno Dias"), "Ana Lima|Bruno Dias")
    eq(names("Ana Lima, Bruno Dias"), "Ana Lima|Bruno Dias")
    eq(names("Ana Lima, Bruno Dias, Carla Reis"), "Ana Lima|Bruno Dias|Carla Reis")
    eq(names("Lima, Ana"), "Lima, Ana")
    eq(names("Tolkien, J. R. R."), "Tolkien, J. R. R.")
    eq(names("Martin Luther King, Jr."), "Martin Luther King, Jr.")
    eq(names("Cruz e Sousa"), "Cruz e Sousa")
    eq(names("Ana Lima\nBruno Dias; Carla Reis"), "Ana Lima|Bruno Dias|Carla Reis")
    eq(names("site.com & Ana Lima"), "Ana Lima")
end)
test("titles lose file names and tags from the program that made them", function()
    eq(Stats.clean_title("Microsoft Word - Um Bom Livro.doc"), "Um Bom Livro")
    eq(Stats.clean_title("MICROSOFT WORD - Outro Livro.DOCX"), "Outro Livro")
    eq(Stats.clean_title("Doc11-11.PDF"), "Doc11-11")
    eq(Stats.clean_title("03 - O Guardião_cs6.indd"), "03 - O Guardião")
    eq(Stats.clean_title("Dias Melhores(Oficial)"), "Dias Melhores")
    eq(Stats.clean_title("Magia do Sangue (Oficial)"), "Magia do Sangue")
    eq(Stats.clean_title("Um Livro (Em Português do Brasil)"), "Um Livro")
    eq(Stats.clean_title("Node.js na Prática"), "Node.js na Prática")
    eq(Stats.clean_title("Um Livro.Com Ponto"), "Um Livro.Com Ponto")
end)
test("sites at the edges of a title are removed, but not a site the book is about", function()
    eq(Stats.clean_title("Um Bom Livro - www.exemplo.com"), "Um Bom Livro")
    eq(Stats.clean_title("Um Bom Livro - exemplo.com.br"), "Um Bom Livro")
    eq(Stats.clean_title("exemplo.net - Um Bom Livro"), "Um Bom Livro")
    eq(Stats.clean_title("Um Bom Livro https://exemplo.org/livro"), "Um Bom Livro")
    eq(Stats.clean_title("Um Bom Livro (exemplo.xyz)"), "Um Bom Livro")
    eq(Stats.clean_title("Como Vender na Amazon.com"), "Como Vender na Amazon.com")
    eq(Stats.clean_title("Amazon.com e o Futuro"), "Amazon.com e o Futuro")
    eq(Stats.clean_title("Node.js - Um Guia"), "Node.js - Um Guia")
    eq(Stats.clean_title("Dois Pontos: Um Estudo"), "Dois Pontos: Um Estudo")
end)
test("and and with separate authors, but names containing them stay whole", function()
    local function names(field)
        return table.concat(Stats.split_authors(field), "|")
    end
    eq(names("Ana Lima and Bruno Dias"), "Ana Lima|Bruno Dias")
    eq(names("Ana Lima, Bruno Dias, and Carla Reis"), "Ana Lima|Bruno Dias|Carla Reis")
    eq(names("Ana Lima with Bruno Dias"), "Ana Lima|Bruno Dias")
    eq(names("Sandra Anderson"), "Sandra Anderson")
    eq(names("Andrew Withers"), "Andrew Withers")
end)
test("program names, dates and alphabets in the author field", function()
    for _, name in ipairs({ "Digital Source", "PDFCreator", "Adolix Split & Merge PDF", "anonymous", "PERSONAL", "?????????" }) do
        eq(#Stats.split_authors(name), 0)
    end
    eq(Stats.split_authors("Albert Camus, 1958.")[1], "Albert Camus")
    eq(Stats.split_authors("Croce, Benedetto, 1866-1952")[1], "Croce, Benedetto")
    eq(Stats.split_authors("Лев Толстой")[1], "Лев Толстой")
    eq(Stats.split_authors("村上春樹")[1], "村上春樹")
    eq(Stats.split_authors("Ana Lima, Prefácio")[1], "Ana Lima, Prefácio")
end)
test("a shorter name inside a single longer one is the same author", function()
    local books = {
        { title = "A", authors = "Friedrich Nietzsche", pages = 100 },
        { title = "B", authors = "Friedrich Wilhelm Nietzsche", pages = 100 },
        { title = "C", authors = "Ana Maria", pages = 100 },
        { title = "D", authors = "Ana Maria Lima", pages = 100 },
        { title = "E", authors = "Ana Maria Souza", pages = 100 },
        { title = "F", authors = "Nietzsche", pages = 100 },
    }
    local m = compute({ { 1, at(1, 3, 15), 7000, 1, 100 }, { 2, at(2, 3, 15), 3000, 1, 100 } }, { books = books })
    eq(#m.authors, 1); eq(m.authors[1].name, "Friedrich Nietzsche"); eq(m.authors[1].seconds, 10000); eq(m.authors[1].books, 2)
    local ambiguous = compute({ { 3, at(1, 3, 15), 700, 1, 100 }, { 4, at(2, 3, 15), 700, 1, 100 }, { 5, at(3, 3, 15), 700, 1, 100 } }, { books = books })
    eq(#ambiguous.authors, 3)
    local one_word = compute({ { 6, at(1, 3, 15), 700, 1, 100 }, { 1, at(2, 3, 15), 700, 1, 100 } }, { books = books })
    eq(#one_word.authors, 2)
end)
test("titles that look like file names become readable", function()
    eq(Stats.clean_title("(Microsoft Word - Um Bom Livro.doc)"), "Um Bom Livro")
    eq(Stats.clean_title("Microsoft Word - Crime_e_Castigo_Final_.doc"), "Crime e Castigo Final")
    eq(Stats.clean_title("entendimento_humano.PDF"), "entendimento humano")
    eq(Stats.clean_title("sem_espacos_nenhum"), "sem espacos nenhum")
    eq(Stats.clean_title("Com Espaço_e Sublinhado"), "Com Espaço_e Sublinhado")
    eq(Stats.clean_title("Eric Hobsbawm - A Era das Revoluções", "Eric Hobsbawm"), "A Era das Revoluções")
    eq(Stats.clean_title("Hobsbawm, Eric - A Era das Revoluções", "Eric Hobsbawm"), "A Era das Revoluções")
    eq(Stats.clean_title("Microsoft Word - Eric Hobsbawm - A Era.doc", "Eric Hobsbawm"), "A Era")
    eq(Stats.clean_title("Eric Hobsbawm - A Era das Revoluções", "Ana Lima"), "Eric Hobsbawm - A Era das Revoluções")
    eq(Stats.clean_title("Eric Hobsbawm - A Era das Revoluções"), "Eric Hobsbawm - A Era das Revoluções")
    local m = compute({ { 1, at(1, 1, 10), 900, 1, 100 } }, { books = { { title = "Ana Lima - Um Livro", authors = "Ana Lima", pages = 100 } } })
    eq(m.books[1].title, "Um Livro")
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
        local m = run{ year = 2026, books = books or BOOKS, rows = sessions(list), now = now or at(12, 31, 12) }
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
    local profile_card
    for _, card in ipairs(Cards.build(metrics, { books = books, strings = I18n.pt })) do
        if card.id == "archetype" then profile_card = card end
    end
    eq(profile_card.secondary, "Com traços de Explorador")
    eq(profile_card.body:find("Explorador", 1, true), nil)
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
        { title = "A", authors = "Uno", pages = 100 }, { title = "B", authors = "Dois", pages = 100 },
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
    local m = run{ year = 2026, books = books, rows = rows, earlier_pages = earlier(3, 1, 10, 90), now = at(12, 31, 12) }
    eq(m.devoured.book.title, "Rápido")
    eq(m.devoured.days, 3)
    eq(m.devoured.pages_per_day, 40)
end)
test("no eligible book means no devoured book", function()
    local m = compute({ { 1, at(1, 1, 10), 200, 1, 100 } })
    eq(m.devoured, nil)
end)
test("timeline groups finished books by the month they reached the end", function()
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

-- Wildcards
local Wildcards = require("book_rewind/wildcards")
local AFTER_THE_YEAR = os.time{ year = 2027, month = 2, day = 1, hour = 12 }
local function has(metrics, id)
    for _, candidate in ipairs(Wildcards.candidates(metrics)) do
        if candidate.id == id then return candidate end
    end
    return nil
end
local function joined(...)
    local rows = {}
    for _, list in ipairs({ ... }) do
        for _, row in ipairs(list) do rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return a[2] < b[2] end)
    return rows
end
local function card_of(metrics, id, lang)
    for _, card in ipairs(Cards.build(metrics, { books = BOOKS, strings = I18n[lang or "pt"] })) do
        if card.id == id then return card end
    end
    return nil
end
test("wildcard: the comeback needs a 30-day pause", function()
    local long = compute({ { 1, at(1, 5, 10), 700, 1, 100 }, { 1, at(3, 10, 10), 700, 2, 100 }, { 1, at(3, 12, 10), 700, 3, 100 } })
    local found = has(long, "comeback")
    eq(found.data.days, os.date("*t", at(3, 10, 10)).yday - os.date("*t", at(1, 5, 10)).yday - 1)
    eq(found.data.after, 1)
    eq(has(compute({ { 1, at(1, 5, 10), 700, 1, 100 }, { 1, at(2, 3, 10), 700, 2, 100 } }), "comeback"), nil)
end)
test("wildcard: waves need 3 returns", function()
    local three = compute({ { 1, at(1, 1, 10), 700, 1, 100 }, { 1, at(2, 1, 10), 700, 2, 100 }, { 1, at(3, 1, 10), 700, 3, 100 }, { 1, at(4, 1, 10), 700, 4, 100 } })
    eq(#has(three, "waves").data.returns, 3)
    eq(has(compute({ { 1, at(1, 1, 10), 700, 1, 100 }, { 1, at(2, 1, 10), 700, 2, 100 }, { 1, at(3, 1, 10), 700, 3, 100 } }), "waves"), nil)
end)
test("waves and the comeback do not appear together", function()
    local rows = { { 1, at(1, 1, 10), 700, 1, 100 }, { 1, at(2, 15, 10), 700, 2, 100 }, { 1, at(3, 15, 10), 700, 3, 100 }, { 1, at(4, 15, 10), 700, 4, 100 } }
    local count = 0
    for _, picked in ipairs(Wildcards.pick(compute(rows))) do
        if picked.group == "return" then count = count + 1 end
    end
    eq(count, 1)
end)
test("wildcard: back after years compares with the last year read", function()
    local last = os.time{ year = 2024, month = 3, day = 10, hour = 12 }
    local m = compute({ { 1, at(8, 10, 10), 700, 1, 100 } }, { last_read_before = last, last_year_seconds = 7200 })
    local found = has(m, "back_after_years")
    eq(found.data.years, 2); eq(found.data.months, 5); eq(found.data.last_year, 2024)
    local card = card_of(m, "back_after_years")
    eq(card.big, "2 anos"); eq(card.label, "e 5 meses sem ler"); eq(card.gap_label, "2025"); eq(card.last_year, 2024)
    eq(has(compute({ { 1, at(1, 10, 10), 700, 1, 100 } }, { last_read_before = os.time{ year = 2025, month = 12, day = 1, hour = 12 }, last_year_seconds = 7200 }), "back_after_years"), nil)
end)
test("wildcard: the book that waited shows that book's pause", function()
    local rows = joined(pages_read(1, 1, 40, 100, at(2, 1, 10)), pages_read(1, 41, 100, 100, at(6, 1, 10)))
    local found = has(compute(rows), "book_waited")
    eq(found.data.book.pause.page, 40)
    eq(has(compute(pages_read(1, 1, 40, 100, at(2, 1, 10))), "book_waited"), nil)
end)
test("wildcard: a whole book in one day", function()
    local m = compute(pages_read(1, 1, 100, 100, at(5, 2, 10)))
    eq(has(m, "one_sitting").data.book.title, "Livro A")
    eq(card_of(m, "one_sitting").big, "No mesmo dia")
    eq(card_of(m, "devoured"), nil)
    eq(has(compute(pages_read(1, 1, 50, 100, at(5, 2, 10))), "one_sitting"), nil)
end)
test("wildcard: slow burn needs 90 days", function()
    local rows = joined(pages_read(1, 1, 50, 100, at(1, 5, 10)), pages_read(1, 51, 100, 100, at(6, 5, 10)))
    eq(has(compute(rows), "slow_burn") ~= nil, true)
    local short = joined(pages_read(1, 1, 50, 100, at(1, 5, 10)), pages_read(1, 51, 100, 100, at(2, 5, 10)))
    eq(has(compute(short), "slow_burn"), nil)
end)
test("wildcard: reread counts the times and the first year", function()
    local m = compute(pages_read(1, 1, 100, 100, at(5, 2, 10)), {
        earlier_pages = earlier(1, 1, 100, 100),
        earlier_reads = { [1] = { first = os.time{ year = 2023, month = 4, day = 1, hour = 12 }, rows = 100 } },
    })
    local book = has(m, "reread").data.book
    eq(book.read_count, 2); eq(book.first_read_year, 2023)
    local card = card_of(m, "reread", "en")
    eq(card.big, "For the 2nd time"); eq(card.later, "3 years later")
    eq(card_of(m, "reread", "es").big, "Por 2ª vez")
end)
test("wildcard: series needs 3 finished books, from the metadata", function()
    local books = {
        { title = "A", authors = "X", pages = 40, series = "Saga #1" },
        { title = "B", authors = "X", pages = 40, series = "Saga #2" },
        { title = "C", authors = "X", pages = 40, series = "saga #3.5" },
        { title = "D", authors = "X", pages = 40, series = "N/A" },
    }
    local function rows_for(count)
        local rows = {}
        for book = 1, count do
            for _, row in ipairs(pages_read(book, 1, 40, 40, at(book + 1, 3, 10))) do rows[#rows + 1] = row end
        end
        return rows
    end
    eq(has(compute(rows_for(2), { books = books }), "series_run"), nil)
    local found = has(compute(rows_for(3), { books = books }), "series_run")
    eq(#found.data.books, 3); eq(found.data.name, "Saga"); eq(found.data.in_a_row, true)
    local no_metadata = { { title = "A", authors = "X", pages = 40 }, { title = "B", authors = "X", pages = 40, series = "N/A" }, { title = "C", authors = "X", pages = 40 } }
    eq(has(compute(rows_for(3), { books = no_metadata }), "series_run"), nil)
end)
test("wildcard: series from the volume in the title, with no metadata", function()
    local books = {
        { title = "Primeiro Caso - Clube das Leitoras - Vol 1", authors = "X", pages = 40 },
        { title = "Segundo Caso - Clube das Leitoras - Vol 2", authors = "X", pages = 40 },
        { title = "Terceiro Caso - Clube das Leitoras - Vol. 3", authors = "X", pages = 40 },
        { title = "Saga Longa (Vol. 1)", authors = "Y", pages = 40 },
        { title = "Saga Longa (Vol. 2)", authors = "Y", pages = 40 },
    }
    local function read(ids)
        local rows = {}
        for index, book in ipairs(ids) do
            for _, row in ipairs(pages_read(book, 1, 40, 40, at(index + 1, 3, 10))) do rows[#rows + 1] = row end
        end
        return rows
    end
    local found = has(compute(read({ 1, 2, 3 }), { books = books }), "series_run")
    eq(found.data.name, "Clube das Leitoras"); eq(#found.data.books, 3)
    eq(has(compute(read({ 4, 5 }), { books = books }), "series_run"), nil)
end)
test("wildcard: series from the title opening needs the same author and 3 books", function()
    local books = {
        { title = "Maria Lua e o Farol", authors = "Ana", pages = 40 },
        { title = "Maria Lua e a Ilha", authors = "Ana", pages = 40 },
        { title = "Maria Lua e o Rio", authors = "Ana", pages = 40 },
        { title = "Maria Lua e o Mar", authors = "Bia", pages = 40 },
        { title = "O Mar e a Terra", authors = "Ana", pages = 40 },
        { title = "O Mar e o Céu", authors = "Ana", pages = 40 },
        { title = "O Sol de Março", authors = "Ana", pages = 40 },
        { title = "O a Mais", authors = "Ana", pages = 40 },
        { title = "O a Menos", authors = "Ana", pages = 40 },
        { title = "O a Melhor", authors = "Ana", pages = 40 },
        { title = "1974 em Dois Atos", authors = "Ana", pages = 40 },
        { title = "1974 em Três Atos", authors = "Ana", pages = 40 },
        { title = "1974 em Quatro Atos", authors = "Ana", pages = 40 },
    }
    local function read(ids)
        local rows = {}
        for index, book in ipairs(ids) do
            for _, row in ipairs(pages_read(book, 1, 40, 40, at(index, 3, 10))) do rows[#rows + 1] = row end
        end
        return rows
    end
    local found = has(compute(read({ 1, 2, 3 }), { books = books }), "series_run")
    eq(found.data.name, "Maria Lua"); eq(#found.data.books, 3)
    eq(has(compute(read({ 1, 2, 4 }), { books = books }), "series_run"), nil)
    eq(has(compute(read({ 5, 6, 7 }), { books = books }), "series_run"), nil)
    eq(has(compute(read({ 8, 9, 10 }), { books = books }), "series_run"), nil)
    eq(has(compute(read({ 11, 12, 13 }), { books = books }), "series_run"), nil)
end)
test("wildcard: series from a bracket or a repeated parenthesis", function()
    local function run(titles, authors)
        local books, rows = {}, {}
        for index, title in ipairs(titles) do
            books[index] = { title = title, authors = authors and authors[index] or "Ana", pages = 40 }
            for _, row in ipairs(pages_read(index, 1, 40, 40, at(index, 3, 10))) do rows[#rows + 1] = row end
        end
        return has(compute(rows, { books = books }), "series_run")
    end
    eq(run({ "[Saga Azul 1] Partida", "[Saga Azul 2] Chegada", "[Saga Azul 3] Volta" }).data.name, "Saga Azul")
    eq(run({ "[Norte01]Vento", "[Norte02]Chuva", "[Norte03]Sol" }).data.name, "Norte")
    eq(run({ "Um Dia [Parte 1]", "Dois Dias [Parte 2]", "Tres Dias [Parte 3]" }), nil)
    eq(run({ "Vento (Os Legados)", "Chuva (Os Legados)", "Sol (Os Legados)" }).data.name, "Os Legados")
    eq(run({ "Vento (A Saga do Mago Livro 1)", "Chuva (A Saga do Mago Livro 2)", "Sol (A Saga do Mago Livro 3)" }).data.name, "A Saga do Mago")
    eq(run({ "Vento (Os Legados)", "Chuva (Os Legados)", "Sol (Os Legados)" }, { "Ana", "Bia", "Cris" }), nil)
    eq(run({ "Vento (Coleção Azul)", "Chuva (Coleção Azul)", "Sol (Coleção Azul)" }), nil)
    eq(run({ "Vento (1888-1937)", "Chuva (1888-1937)", "Sol (1888-1937)" }), nil)
end)
test("wildcard: series from more volume markers and roman numerals", function()
    local function name_of(titles, authors)
        local books, rows = {}, {}
        for index, title in ipairs(titles) do
            books[index] = { title = title, authors = authors and authors[index] or "Ana", pages = 40 }
            for _, row in ipairs(pages_read(index, 1, 40, 40, at(index, 3, 10))) do rows[#rows + 1] = row end
        end
        local found = has(compute(rows, { books = books }), "series_run")
        return found and found.data.name or nil
    end
    local mixed = { "Ana", "Bia", "Cris" }
    eq(name_of({ "Reino Azul - Livro 1", "Reino Azul - Livro 2", "Reino Azul - Livro 3" }, mixed), "Reino Azul")
    eq(name_of({ "Reino Azul Book 1", "Reino Azul Book 2", "Reino Azul Book 3" }, mixed), "Reino Azul")
    eq(name_of({ "Reino Azul (Tomo 1)", "Reino Azul (Tomo 2)", "Reino Azul (Tomo 3)" }, mixed), "Reino Azul")
    eq(name_of({ "Reino Azul - Vol. I", "Reino Azul - Vol. II", "Reino Azul - Vol. III" }, mixed), "Reino Azul")
    eq(name_of({ "Primeiro - Reino Azul - Vol IV", "Segundo - Reino Azul - Vol V", "Terceiro - Reino Azul - Vol VI" }, mixed), "Reino Azul")
    eq(name_of({ "Terras Altas I", "Terras Altas II", "Terras Altas III" }, mixed), "Terras Altas")
    eq(name_of({ "Terras Altas I - O Início", "Terras Altas II: O Meio", "Terras Altas III - O Fim" }, mixed), "Terras Altas")
    eq(name_of({ "Henrique IV", "Henrique V", "Henrique VI" }, mixed), nil)
    eq(name_of({ "O Meu Livro Civil", "Outro Livro Civil", "Mais Um Livro Civil" }, mixed), nil)
    eq(name_of({ "Direito Civil II", "Direito Penal III", "Direito Público IV" }, mixed), nil)
end)
test("wildcard: a series from the opening takes the name its titles share", function()
    local function name_of(titles)
        local books, rows = {}, {}
        for index, title in ipairs(titles) do
            books[index] = { title = title, authors = "Ana", pages = 40 }
            for _, row in ipairs(pages_read(index, 1, 40, 40, at(index, 3, 10))) do rows[#rows + 1] = row end
        end
        return has(compute(rows, { books = books }), "series_run").data.name
    end
    eq(name_of({ "Cavalo de Pedra 2 Massada", "Cavalo de Pedra 3 Saidan", "Cavalo de Pedra 4 Nazaré" }), "Cavalo de Pedra")
    eq(name_of({ "Maria Lua e o Farol", "Maria Lua e a Ilha", "Maria Lua e o Rio" }), "Maria Lua")
    eq(name_of({ "Reino Azul: A Partida", "Reino Azul: A Volta", "Reino Azul: O Fim" }), "Reino Azul")
    eq(name_of({ "Cavalo de Pedra, 9: Caná", "Cavalo de Pedra 3 Saidan", "Cavalo de Pedra: Nazaré" }), "Cavalo de Pedra")
    eq(name_of({ "Revista Lua - Edição 01", "Revista Lua - Edição 02", "Revista Lua - Edição 03" }), "Revista Lua")
    eq(name_of({ "A Garota do Mês: Março", "A Garota do Mês: Abril", "A GAROTA DO MÊS: Maio" }), "A Garota do Mês")
end)
test("wildcard: generic title openings are not a series", function()
    local function run(titles)
        local books, rows = {}, {}
        for index, title in ipairs(titles) do
            books[index] = { title = title, authors = "Ana", pages = 40 }
            for _, row in ipairs(pages_read(index, 1, 40, 40, at(index, 3, 10))) do rows[#rows + 1] = row end
        end
        return has(compute(rows, { books = books }), "series_run")
    end
    eq(run({ "Curso de Direito Civil", "Curso de Direito Penal", "Curso de Processo Civil" }), nil)
    eq(run({ "O Livro das Mulheres", "O Livro do Ego", "O Livro das Crianças" }), nil)
    eq(run({ "História da Arte", "História da Música", "História da Filosofia" }), nil)
    eq(run({ "Microsoft Word - Azul Claro.doc", "Microsoft Word - Azul Escuro.doc", "Microsoft Word - Azul Marinho.doc" }), nil)
end)
test("wildcard: series metadata wins over the title", function()
    local books = {
        { title = "Maria Lua e o Farol", authors = "Ana", pages = 40, series = "Nome Oficial #1" },
        { title = "Maria Lua e a Ilha", authors = "Ana", pages = 40, series = "Nome Oficial #2" },
        { title = "Maria Lua e o Rio", authors = "Ana", pages = 40, series = "Nome Oficial #3" },
    }
    local rows = {}
    for book = 1, 3 do
        for _, row in ipairs(pages_read(book, 1, 40, 40, at(book, 3, 10))) do rows[#rows + 1] = row end
    end
    eq(has(compute(rows, { books = books }), "series_run").data.name, "Nome Oficial")
end)
test("a long title does not cut the pace sentence", function()
    local long = string.rep("Um Título Bem Comprido ", 5)
    local books = { { title = "Rápido", authors = "X", pages = 100 }, { title = long, authors = "Y", pages = 100 } }
    local function read(book, seconds, month)
        local rows = pages_read(book, 1, 100, 100, at(month, 1, 10))
        for _, row in ipairs(rows) do row[3] = seconds end
        return rows
    end
    local foot = card_of(compute(joined(read(1, 30, 2), read(2, 100, 3)), { books = books }), "pace_change").foot
    eq(foot:find("levou mais que o triplo do tempo.", 1, true) ~= nil, true)
    eq(foot:find("…", 1, true) ~= nil, true)
end)
test("wildcard: juggler counts books open at the same time", function()
    local books = { { title = "A", authors = "X", pages = 100 }, { title = "B", authors = "Y", pages = 100 }, { title = "C", authors = "Z", pages = 100 }, { title = "D", authors = "W", pages = 100 } }
    local function span(book, start_day, end_day)
        return { { book, at(3, start_day, 10), 120, 1, 100 }, { book, at(3, end_day, 10), 120, 2, 100 } }
    end
    local together = joined(span(1, 1, 10), span(2, 3, 12), span(3, 5, 14))
    eq(#has(compute(together, { books = books }), "juggler").data.rows, 3)
    local apart = joined(span(1, 1, 3), span(2, 6, 8), span(3, 11, 13))
    eq(has(compute(apart, { books = books }), "juggler"), nil)
end)
test("wildcard: so close only in a closed year with no later reading", function()
    local rows = pages_read(1, 1, 85, 100, at(5, 2, 10))
    for _, row in ipairs(rows) do row[3] = 60 end
    eq(has(compute(rows), "almost_there"), nil)
    local found = has(compute(rows, { now = AFTER_THE_YEAR }), "almost_there")
    eq(math.floor(found.data.book.overall * 100 + 0.5), 85)
    eq(card_of(compute(rows, { now = AFTER_THE_YEAR }), "almost_there").foot, "Faltaram 15 páginas.")
    eq(has(compute(rows, { now = AFTER_THE_YEAR, read_later = { [1] = true } }), "almost_there"), nil)
end)
test("wildcard: shortest to longest needs a big difference", function()
    local books = { { title = "Curto", authors = "X", pages = 50 }, { title = "Longo", authors = "Y", pages = 400 }, { title = "Médio", authors = "Z", pages = 100 } }
    local big = joined(pages_read(1, 1, 50, 50, at(2, 1, 10)), pages_read(2, 1, 400, 400, at(3, 1, 10)))
    local found = has(compute(big, { books = books }), "extremes")
    eq(found.data.short.title, "Curto"); eq(found.data.long.title, "Longo"); eq(found.data.ratio, 8)
    local close = joined(pages_read(1, 1, 50, 50, at(2, 1, 10)), pages_read(3, 1, 100, 100, at(3, 1, 10)))
    eq(has(compute(close, { books = books }), "extremes"), nil)
end)
test("wildcard: the most marked book must be finished", function()
    local books = { { title = "Marcado", authors = "X", pages = 40, highlights = 42, notes = 3 } }
    local m = compute(pages_read(1, 1, 40, 40, at(2, 1, 10)), { books = books })
    eq(has(m, "most_marked").data.book.highlights, 42)
    eq(has(compute(pages_read(1, 1, 10, 40, at(2, 1, 10)), { books = books }), "most_marked"), nil)
end)
test("wildcard: end to end only in a closed year", function()
    local books = {}
    local rows = {}
    for i = 1, 5 do
        books[i] = { title = "L" .. i, authors = "A" .. i, pages = 100 }
        rows[#rows + 1] = { i, at(i * 2, 3, 10), 120, 1, 100 }
    end
    eq(has(compute(rows, { books = books }), "bookends"), nil)
    local found = has(compute(rows, { books = books, now = AFTER_THE_YEAR }), "bookends")
    eq(found.data.first.title, "L1"); eq(found.data.last.title, "L5"); eq(found.data.between, 3)
end)
test("wildcard: ritual needs many days at the same time", function()
    local same, scattered = {}, {}
    for day = 1, 25 do
        same[day] = { month = 1, day = day, hour = 22, minutes = 10 }
        scattered[day] = { month = 1, day = day, hour = day % 24, minutes = 10 }
    end
    local found = has(compute(sessions(same)), "ritual")
    eq(found.data.share, 1)
    eq(card_of(compute(sessions(same)), "ritual").big, "Às 22h")
    eq(has(compute(sessions(scattered)), "ritual"), nil)
end)
test("wildcard: past midnight counts sessions crossing midnight", function()
    local rows = {}
    for day = 1, 6 do
        rows[#rows + 1] = { 1, at(2, day * 2, 23, 58), 120, day, 100 }
        rows[#rows + 1] = { 1, at(2, day * 2, 23, 58) + 120, 120, day + 50, 100 }
    end
    local found = has(compute(rows), "past_midnight")
    eq(found.data.count, 6); eq(found.data.latest, 2)
    eq(card_of(compute(rows), "past_midnight").foot, "A mais tarde foi até as 0h02.")
    eq(has(compute({ { 1, at(2, 2, 22), 120, 1, 100 } }), "past_midnight"), nil)
end)
test("wildcard: a day to remember replaces the biggest day", function()
    local rows = { { 1, at(3, 2, 8), 11000, 1, 100 }, { 1, at(3, 2, 12), 400, 2, 100 }, { 2, at(4, 2, 8), 900, 1, 200 } }
    local m = compute(rows)
    local found = has(m, "memorable_day")
    eq(found.data.pages, 2); eq(found.data.book.title, "Livro A")
    eq(card_of(m, "memorable_day") ~= nil, true); eq(card_of(m, "best_day"), nil)
    local small = compute({ { 1, at(3, 2, 8), 700, 1, 100 }, { 1, at(3, 3, 8), 700, 2, 100 } })
    eq(has(small, "memorable_day"), nil); eq(card_of(small, "best_day") ~= nil, true)
end)
test("wildcard: pace compares the fastest and slowest books", function()
    local books = { { title = "Rápido", authors = "X", pages = 100 }, { title = "Lento", authors = "Y", pages = 100 } }
    local function read(book, seconds, month)
        local rows = pages_read(book, 1, 100, 100, at(month, 1, 10))
        for _, row in ipairs(rows) do row[3] = seconds end
        return rows
    end
    local m = compute(joined(read(1, 30, 2), read(2, 100, 3)), { books = books })
    local found = has(m, "pace_change")
    eq(found.data.fast.book.title, "Rápido"); eq(found.data.slow.book.title, "Lento")
    local card = card_of(m, "pace_change")
    eq(card.fast_value, "30 s"); eq(card.slow_value, "1 min 40 s")
    eq(card.foot, "Cada página de Lento levou mais que o triplo do tempo.")
    eq(has(compute(joined(read(1, 40, 2), read(2, 60, 3)), { books = books }), "pace_change"), nil)
end)
test("at most 3 wildcards, and one book does not star in two", function()
    local book = { { title = "A", authors = "X", pages = 200, highlights = 80 } }
    local rows = joined(pages_read(1, 1, 100, 200, at(1, 5, 10)), pages_read(1, 101, 200, 200, at(7, 5, 10)))
    local m = compute(rows, { books = book })
    eq(has(m, "book_waited") ~= nil, true); eq(has(m, "slow_burn") ~= nil, true); eq(has(m, "most_marked") ~= nil, true)
    local picked = Wildcards.pick(m)
    local starring = 0
    for _, candidate in ipairs(picked) do
        if candidate.books then starring = starring + 1 end
    end
    eq(starring, 1)
    eq(#picked <= Wildcards.MAX, true)
end)
test("a year with nothing remarkable has no wildcard", function()
    eq(#Wildcards.pick(compute({ { 1, at(3, 2, 10), 700, 1, 100 } })), 0)
    eq(#Wildcards.pick(compute({})), 0)
end)

-- A finished book opened again later, to look something up, keeps the day it reached the end.
local function finished_then_reopened()
    return joined(pages_read(1, 1, 100, 100, at(1, 10, 10)), pages_read(1, 50, 51, 100, at(6, 20, 10)),
        pages_read(2, 1, 100, 200, at(3, 9, 10)), pages_read(2, 101, 200, 200, at(3, 12, 10)))
end
test("a book reopened after the end keeps the day it was finished", function()
    local m = compute(finished_then_reopened())
    local book = m.books[1].id == 1 and m.books[1] or m.books[2]
    eq(book.finished, true)
    eq(book.finish_yday, 10); eq(book.finish_seconds, 5000)
    eq(book.last_yday, os.date("*t", at(6, 20, 10)).yday)
    eq(m.devoured.book.id, 1); eq(m.devoured.days, 1)
end)
test("reopening a finished book makes no slow burn and no waiting", function()
    local m = compute(finished_then_reopened())
    eq(has(m, "slow_burn"), nil)
    eq(has(m, "book_waited"), nil)
    local sitting = has(m, "one_sitting")
    eq(sitting ~= nil, true)
    eq(card_of(m, "one_sitting").label, "100 páginas em 1 h 23 min")
end)
test("the timeline puts a reopened book in the month it was finished", function()
    local m = compute(finished_then_reopened())
    local timeline
    for _, card in ipairs(Cards.build(m, { books = BOOKS, strings = I18n.pt })) do
        if card.id == "timeline" then timeline = card end
    end
    eq(#timeline.months_books[1], 1)
    eq(#timeline.months_books[3], 1)
    eq(#timeline.months_books[6], 0)
    eq(timeline.months_books[1][1].title, "Livro A")
end)
test("a pause before the end still counts, and a pause after it does not", function()
    local rows = joined(pages_read(1, 1, 40, 100, at(2, 1, 10)), pages_read(1, 41, 100, 100, at(6, 1, 10)), pages_read(1, 1, 2, 100, at(12, 1, 10)))
    local m = compute(rows)
    local waited = has(m, "book_waited")
    eq(waited.data.book.pause.days, os.date("*t", at(6, 1)).yday - os.date("*t", at(2, 1)).yday - 1)
    eq(card_of(m, "book_waited").end_label, "junho")
    eq(has(m, "slow_burn").data.days, os.date("*t", at(6, 1)).yday - os.date("*t", at(2, 1)).yday + 1)
end)
test("a reread finishes when the whole book is read again, not when it is reopened", function()
    local rows = joined(pages_read(1, 1, 100, 100, at(3, 1, 10)), pages_read(1, 10, 12, 100, at(8, 1, 10)))
    local m = compute(rows, { earlier_pages = earlier(1, 1, 100, 100) })
    eq(m.books[1].reread, true)
    eq(m.books[1].finish_yday, os.date("*t", at(3, 1)).yday)
end)
test("the pages of the biggest day follow the rule of the year", function()
    local books = { { title = "X", authors = "Ana Lima", pages = 100 } }
    -- The same first half, read at two font sizes on the same day.
    local rows = joined(pages_read(1, 1, 50, 100, at(3, 1, 8)), pages_read(1, 1, 100, 200, at(3, 1, 14)))
    local m = compute(rows, { books = books })
    eq(m.total_pages, 50)
    eq(m.best_day.pages, 50)
end)
test("the biggest day of a book with no page count uses the pages of its rows", function()
    local books = { { title = "X", authors = "Ana Lima", pages = 0 } }
    local m = compute(pages_read(1, 1, 30, 120, at(3, 1, 8)), { books = books })
    eq(m.best_day.pages, 30)
end)
test("the page where a book stopped is in the book's own pagination", function()
    local books = { { title = "X", authors = "Ana Lima", pages = 100 } }
    -- Pages 1 to 80 of 200 at a small font are the first 40% of the book.
    local rows = joined(pages_read(1, 1, 80, 200, at(2, 1, 10)), pages_read(1, 81, 200, 200, at(6, 1, 10)))
    eq(has(compute(rows, { books = books }), "book_waited").data.book.pause.page, 40)
end)
test("passes count each reading to the end, at any font size", function()
    local function history(first, last, total)
        local list = {}
        for page = first, last do list[#list + 1] = { page, total } end
        return list
    end
    local whole = history(1, 100, 100)
    for _, row in ipairs(history(1, 30, 100)) do whole[#whole + 1] = row end
    for _, row in ipairs(history(1, 200, 200)) do whole[#whole + 1] = row end
    eq(Stats.count_passes(whole), 2)
    eq(Stats.count_passes(history(1, 50, 100)), 0)
    eq(Stats.count_passes({}), 0)
end)
test("wildcard: reread counts every earlier pass", function()
    local passes = {}
    for _ = 1, 2 do
        for page = 1, 100 do passes[#passes + 1] = { page, 100 } end
    end
    local m = compute(pages_read(1, 1, 100, 100, at(5, 2, 10)), {
        earlier_pages = earlier(1, 1, 100, 100),
        earlier_reads = { [1] = { first = os.time{ year = 2022, month = 4, day = 1, hour = 12 } } },
        earlier_history = function(id) eq(id, 1); return passes end,
    })
    eq(has(m, "reread").data.book.read_count, 3)
    eq(card_of(m, "reread", "en").big, "For the 3rd time")
    -- Pages turned back and forth do not add readings.
    local m2 = compute(pages_read(1, 1, 100, 100, at(5, 2, 10)), {
        earlier_pages = earlier(1, 1, 100, 100),
        earlier_history = function()
            local list = {}
            for page = 1, 100 do list[#list + 1] = { page, 100 } end
            for page = 1, 60 do list[#list + 1] = { page, 100 } end
            return list
        end,
    })
    eq(has(m2, "reread").data.book.read_count, 2)
end)
test("rows in columns give the same result as rows in a list", function()
    local rows = finished_then_reopened()
    local columns = Stats.columns(rows)
    eq(#columns.start, #rows); eq(columns.book[1], rows[1][1]); eq(columns.total[#rows], rows[#rows][5])
end)

-- A book where the reader uses stable page numbers: 663 screen pages, 402 stable ones.
local StablePages = require("book_rewind/stable_pages")
local function stable_books(screen_total, stable_total)
    local books = { [1] = { title = "Estável", authors = "Ana Lima", pages = screen_total, md5 = "m1" } }
    StablePages.apply(books, { m1 = stable_total })
    return books
end
test("stable page numbers count the same part of the book in stable pages", function()
    local m = compute(pages_read(1, 1, 331, 663, at(3, 1, 8)), { books = stable_books(663, 402) })
    eq(m.total_pages, 201)
    eq(m.books[1].total_pages, 402)
end)
test("the page where a book stopped follows stable page numbers", function()
    local rows = joined(pages_read(1, 1, 265, 663, at(2, 1, 8)), pages_read(1, 266, 663, 663, at(6, 1, 8)))
    local found = has(compute(rows, { books = stable_books(663, 402) }), "book_waited")
    eq(found.data.book.pause.page, 161)
end)
test("a book under 30 stable pages is not the devoured book, even with more screen pages", function()
    local rows = pages_read(1, 1, 35, 35, at(4, 1, 10))
    eq(compute(rows, { books = stable_books(35, 35) }).devoured ~= nil, true)
    eq(compute(rows, { books = stable_books(35, 25) }).devoured, nil)
end)

-- Books marked as finished in KOReader and missing from the statistics, for example after a reset.
local Marked = require("book_rewind/marked")
local function marked_entry(md5, modified, title)
    return { md5 = md5, status = "complete", modified = modified, percent = 1, title = title or "Marcado", authors = "Rui Paz", doc_pages = 120 }
end
local function with_md5(id, md5)
    local books = {}
    for key, book in pairs(BOOKS) do
        books[key] = { title = book.title, authors = book.authors, pages = book.pages }
    end
    books[id].md5 = md5
    return books
end
test("marked books count on the books card and in the summary", function()
    local m = compute(pages_read(1, 1, 50, 100, at(3, 1, 10)))
    Marked.add(m, { marked_entry("x", "2026-04-15") }, BOOKS, 2026)
    local card = card_of(m, "books")
    eq(card.big, "2"); eq(card.body, "E chegou ao fim de 1.")
    eq(#card.books, 2); eq(card.books[2].id < 0, true)
    local summary = card_of(m, "summary")
    local found = false
    for _, row in ipairs(summary.ranks) do
        if row.meta == "2, com 1 até o fim" then found = true end
    end
    eq(found, true)
end)
test("marked books go on the timeline in the month they were marked, even to make up its two books", function()
    local m = compute(pages_read(1, 1, 100, 100, at(2, 1, 10)))
    eq(card_of(m, "timeline"), nil)
    Marked.add(m, { marked_entry("x", "2026-06-20") }, BOOKS, 2026)
    local card = card_of(m, "timeline")
    eq(#card.months_books[2], 1); eq(#card.months_books[6], 1); eq(card.months_books[6][1].id < 0, true)
end)
test("a book read in part before a reset and marked as finished is not almost finished", function()
    local rows = pages_read(1, 1, 85, 100, at(5, 2, 10))
    for _, row in ipairs(rows) do row[3] = 60 end
    local books = with_md5(1, "m1")
    local m = compute(rows, { now = AFTER_THE_YEAR, books = books })
    eq(has(m, "almost_there") ~= nil, true)
    Marked.add(m, { marked_entry("m1", "2026-05-20") }, books, 2026)
    eq(has(m, "almost_there"), nil)
    local card = card_of(m, "books")
    eq(card.big, "1"); eq(card.body, "E chegou ao fim de 1.")
end)
test("marked books change no time, pages, profile or devoured book", function()
    local rows = joined(pages_read(1, 1, 100, 100, at(2, 1, 10)), pages_read(2, 1, 60, 200, at(3, 1, 22)))
    local m = compute(rows)
    local seconds, pages, profile, devoured = m.total_seconds, m.total_pages, Stats.archetype(m).id, m.devoured and m.devoured.book.id
    Marked.add(m, { marked_entry("x", "2026-04-15"), marked_entry("y", "2026-07-01", "Outro") }, BOOKS, 2026)
    eq(m.total_seconds, seconds); eq(m.total_pages, pages); eq(Stats.archetype(m).id, profile)
    eq(m.devoured and m.devoured.book.id, devoured)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
