package.path = "./?.lua;" .. package.path
-- The server only needs these from LuaSocket, so the tests run without a network.
package.loaded.socket = package.loaded.socket or { gettime = os.clock }
local Access = require("book_rewind/share/access")
local Deck = require("book_rewind/share/deck")
local Server = require("book_rewind/share/server")
local Strings = require("book_rewind/share/strings")

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

local TOKEN, HOST, PHONE, OTHER = "abc123token", "192.168.0.5:8643", "192.168.0.20", "192.168.0.99"

local function new_access(overrides)
    local asked = {}
    local opts = {
        token = TOKEN,
        host = HOST,
        strings = Strings.en,
        assets = { script = "SCRIPT", style = "STYLE" },
        deck = function(theme) return '{"theme":"' .. theme .. '"}' end,
        layer = function(theme, index, size)
            asked[#asked + 1] = { theme, index, size }
            if index > 3 then return nil end
            return { path = "/tmp/layer.png" }
        end,
        on_new_client = function(ip) asked.client = ip end,
    }
    for key, value in pairs(overrides or {}) do
        opts[key] = value
    end
    return Access.new(opts), asked
end

local function get(target, host)
    return string.format("GET %s HTTP/1.1\r\nHost: %s\r\n\r\n", target, host or HOST)
end

local function approved(overrides)
    local access, asked = new_access(overrides)
    access:handle(get("/" .. TOKEN .. "/"), PHONE)
    access:approve(PHONE)
    return access, asked
end

test("private addresses only", function()
    eq(Access.is_private_ip("10.0.0.1"), true)
    eq(Access.is_private_ip("172.16.0.1"), true)
    eq(Access.is_private_ip("172.32.0.1"), false)
    eq(Access.is_private_ip("192.168.1.1"), true)
    eq(Access.is_private_ip("8.8.8.8"), false)
    eq(Access.is_private_ip("not an ip"), false)
end)

test("the first device with the code waits for approval", function()
    local access, asked = new_access()
    local result = access:handle(get("/" .. TOKEN .. "/"), PHONE)
    eq(asked.client, PHONE)
    eq(result.status, 200)
    assert(result.body:find(Strings.en.confirm_heading, 1, true))
    eq(access.client_ip, nil)
end)

test("without the code, everything is the same 404, and nobody is asked about", function()
    local access, asked = new_access()
    eq(access:handle(get("/"), PHONE).status, 404)
    eq(access:handle(get("/wrong/"), PHONE).status, 404)
    eq(access:handle(get("/wrong/deck/vibrant"), PHONE).status, 404)
    eq(asked.client, nil)
end)

test("nothing but the style is reachable before approval", function()
    local access = new_access()
    access:handle(get("/" .. TOKEN .. "/"), PHONE)
    eq(access:handle(get("/" .. TOKEN .. "/style.css"), PHONE).body, "STYLE")
    assert(access:handle(get("/" .. TOKEN .. "/app.js"), PHONE).body:find(Strings.en.confirm_heading, 1, true))
    assert(access:handle(get("/" .. TOKEN .. "/deck/vibrant"), PHONE).body:find(Strings.en.confirm_heading, 1, true))
    eq(access:handle(get("/" .. TOKEN .. "/layer/vibrant/1/preview"), PHONE).path, nil)
end)

test("a second device gets nothing while another waits", function()
    local access = new_access()
    access:handle(get("/" .. TOKEN .. "/"), PHONE)
    eq(access:handle(get("/" .. TOKEN .. "/"), OTHER).status, 404)
end)

test("after approval, only that device is served", function()
    local access = approved()
    eq(access:handle(get("/" .. TOKEN .. "/"), PHONE).status, 200)
    eq(access:handle(get("/" .. TOKEN .. "/"), OTHER).status, 404)
    eq(access:handle(get("/" .. TOKEN .. "/deck/vibrant"), OTHER).status, 404)
end)

test("a denied device stays out, and its connection is only closed", function()
    local access = new_access()
    access:handle(get("/" .. TOKEN .. "/"), PHONE)
    access:deny(PHONE)
    eq(access:is_denied(PHONE), true)
    eq(access:handle(get("/" .. TOKEN .. "/"), PHONE).close_only, true)
end)

test("repeated bad requests lock out that address only", function()
    local access = approved()
    for _ = 1, Access.MAX_BAD_REQUESTS do
        access:handle(get("/guess/"), OTHER)
    end
    eq(access:is_denied(OTHER), true)
    for _ = 1, Access.MAX_BAD_REQUESTS + 5 do
        access:handle(get("/" .. TOKEN .. "/favicon.ico"), PHONE)
    end
    eq(access:is_denied(PHONE), false)
end)

test("outside private networks, nothing is served", function()
    local access = new_access()
    eq(access:handle(get("/" .. TOKEN .. "/"), "8.8.8.8").status, 404)
    eq(access.pending_ip, nil)
end)

test("another host name is refused, which stops DNS rebinding", function()
    local access = approved()
    eq(access:handle(get("/" .. TOKEN .. "/", "evil.example"), PHONE).status, 404)
    eq(access:handle(string.format("GET /%s/ HTTP/1.1\r\n\r\n", TOKEN), PHONE).status, 404)
end)

test("only GET exists: nothing can be sent to the device", function()
    local access = approved()
    for _, method in ipairs({ "POST", "PUT", "DELETE", "HEAD", "OPTIONS" }) do
        eq(access:handle(string.format("%s /%s/ HTTP/1.1\r\nHost: %s\r\n\r\n", method, TOKEN, HOST), PHONE).status, 404)
    end
end)

test("an oversized request is refused", function()
    local access = approved()
    eq(access:handle(get("/" .. TOKEN .. "/" .. string.rep("a", Access.MAX_REQUEST_BYTES)), PHONE).status, 404)
end)

test("themes come from a fixed list", function()
    local access = approved()
    eq(access:handle(get("/" .. TOKEN .. "/deck/gray"), PHONE).status, 200)
    eq(access:handle(get("/" .. TOKEN .. "/deck/eink"), PHONE).status, 200)
    eq(access:handle(get("/" .. TOKEN .. "/deck/vibrant"), PHONE).status, 200)
    eq(access:handle(get("/" .. TOKEN .. "/deck/other"), PHONE).status, 404)
end)

test("layers take only known themes, sizes and numbers, so no path can be chosen", function()
    local access, asked = approved()
    eq(access:handle(get("/" .. TOKEN .. "/layer/vibrant/1/preview"), PHONE).path, "/tmp/layer.png")
    eq(access:handle(get("/" .. TOKEN .. "/layer/gray/2/story"), PHONE).path, "/tmp/layer.png")
    eq(#asked, 2)
    for _, bad in ipairs({
        "/layer/other/1/preview", "/layer/vibrant/1/huge", "/layer/vibrant/x/preview", "/layer/../../etc/1/preview",
        "/layer/vibrant/1/preview/extra", "/layer/vibrant/%2e%2e/preview", "/layer/vibrant/1000/preview", "/../../etc/passwd",
    }) do
        eq(access:handle(get("/" .. TOKEN .. bad), PHONE).status, 404)
    end
    eq(#asked, 2)
end)

test("a card that does not exist is a 404", function()
    local access = approved()
    eq(access:handle(get("/" .. TOKEN .. "/layer/vibrant/9/preview"), PHONE).status, 404)
end)

test("no room and a failed drawing say so", function()
    local access = approved{ layer = function() return nil, "space" end }
    eq(access:handle(get("/" .. TOKEN .. "/layer/vibrant/1/story"), PHONE).status, 507)
    access = approved{ layer = function() return nil, "failed" end }
    eq(access:handle(get("/" .. TOKEN .. "/layer/vibrant/1/story"), PHONE).status, 500)
end)

test("responses limit what a page can do", function()
    local head = Access.response_head({ status = 200, content_type = "text/html" }, 10)
    assert(head:find("Content-Security-Policy: default-src 'none'", 1, true))
    assert(head:find("X-Content-Type-Options: nosniff", 1, true))
    assert(head:find("X-Frame-Options: DENY", 1, true))
    assert(head:find("Cache-Control: no-store", 1, true))
    assert(not head:find("unsafe", 1, true))
end)

test("the page has no inline script", function()
    local access = approved()
    local body = access:handle(get("/" .. TOKEN .. "/"), PHONE).body
    assert(body:find('<script src="/' .. TOKEN .. '/app.js"></script>', 1, true))
    eq(select(2, body:gsub("<script", "")), 1)
    eq(access:handle(get("/" .. TOKEN .. "/app.js"), PHONE).body, "SCRIPT")
end)

test("the deck carries colors and shapes, and escapes its texts", function()
    local strings = { page = { title = 'a"b<c>&' } }
    local json = Deck.build({ { id = "books" } }, "vibrant", 2026, strings)
    assert(json:find('"year":2026', 1, true))
    assert(json:find('"theme":"vibrant"', 1, true))
    assert(json:find('"bg":"#', 1, true))
    assert(json:find('"anim":"drift-x"', 1, true))
    assert(json:find('a\\"b\\u003cc\\u003e\\u0026', 1, true))
    assert(not json:find("<", 1, true))
end)

test("rows of dots go in the deck as a short rule", function()
    local json = Deck.build({ { id = "summary" } }, "gray", 2026, { page = {} })
    assert(json:find('["d",-31,-1,11,1.5,"#000000"]', 1, true))
end)

test("all three languages have the same texts", function()
    local function keys(from, into, prefix)
        for key, value in pairs(from) do
            if type(value) == "table" then
                keys(value, into, key .. ".")
            else
                into[prefix .. key] = true
            end
        end
        return into
    end
    local english = keys(Strings.en, {}, "")
    for _, language in ipairs({ "pt", "es" }) do
        local other = keys(Strings[language], {}, "")
        for key in pairs(english) do
            assert(other[key], language .. " has no " .. key)
        end
        for key in pairs(other) do
            assert(english[key], "en has no " .. key)
        end
    end
end)

test("no text names a brand of e-reader, since the plugin runs on many", function()
    local function check(from, path)
        for key, value in pairs(from) do
            if type(value) == "table" then
                check(value, path .. "." .. key)
            else
                assert(not value:lower():find("kindle", 1, true), path .. "." .. key .. " names the Kindle")
            end
        end
    end
    check(Strings, "strings")
end)

-- A connection that hands out what was queued, and keeps what it receives.
local function fake_client(ip, input)
    local client = { ip = ip, input = input or "", output = {}, closed = false }
    function client:getpeername() return self.ip end
    function client:settimeout() end
    function client:receive(size)
        if #self.input == 0 then
            if self.eof then return nil, "closed", "" end
            return nil, "timeout", ""
        end
        local chunk = self.input:sub(1, size)
        self.input = self.input:sub(size + 1)
        if #chunk == size then return chunk end
        return nil, "timeout", chunk
    end
    function client:send(data, first)
        first = first or 1
        self.output[#self.output + 1] = data:sub(first)
        return #data
    end
    function client:close() self.closed = true end
    function client:response() return table.concat(self.output) end
    return client
end

local function server_with(access, clients)
    local server = Server.new{ access = access, ip = "192.168.0.5", port = 8643, log = function() end }
    local waiting = clients
    server.listener = {
        accept = function() return table.remove(waiting, 1) end,
        close = function() end,
    }
    return server
end

local function run(server, times)
    for _ = 1, times or 5 do
        server:tick()
    end
end

test("the server answers a request and closes", function()
    local access = approved()
    local client = fake_client(PHONE, get("/" .. TOKEN .. "/deck/gray"))
    run(server_with(access, { client }))
    assert(client:response():find("HTTP/1.1 200", 1, true))
    assert(client:response():find('{"theme":"gray"}', 1, true))
    eq(client.closed, true)
end)

test("the server sends a file, with its real size", function()
    local path = os.tmpname()
    local file = io.open(path, "wb")
    file:write(string.rep("x", 100000))
    file:close()
    local access = approved{ layer = function() return { path = path } end }
    local client = fake_client(PHONE, get("/" .. TOKEN .. "/layer/gray/1/story"))
    run(server_with(access, { client }), 10)
    local response = client:response()
    assert(response:find("Content-Length: 100000", 1, true))
    assert(response:find("Content-Type: image/png", 1, true))
    eq(#response:match("\r\n\r\n(.*)$"), 100000)
    os.remove(path)
end)

test("a file that vanished ends in an error, not in a broken head", function()
    local access = approved{ layer = function() return { path = "/nonexistent/layer.png" } end }
    local client = fake_client(PHONE, get("/" .. TOKEN .. "/layer/gray/1/story"))
    run(server_with(access, { client }))
    assert(client:response():find("HTTP/1.1 500", 1, true))
end)

test("a blocked address is dropped as soon as it connects", function()
    local access = approved()
    access:deny(OTHER)
    local client = fake_client(OTHER, get("/" .. TOKEN .. "/"))
    run(server_with(access, { client }))
    eq(client.closed, true)
    eq(client:response(), "")
end)

test("strangers cannot take the places of the device in use", function()
    local access = approved()
    local clients = {}
    for i = 1, 20 do
        clients[i] = fake_client("192.168.0." .. (100 + i), "")
    end
    local server = server_with(access, clients)
    run(server, 6)
    eq(server:has_room(PHONE), true)
end)

test("an error in one request closes only that connection", function()
    local access = approved{ layer = function() error("boom") end }
    local bad = fake_client(PHONE, get("/" .. TOKEN .. "/layer/gray/1/story"))
    local good = fake_client(PHONE, get("/" .. TOKEN .. "/deck/gray"))
    run(server_with(access, { bad, good }))
    eq(bad.closed, true)
    assert(good:response():find("HTTP/1.1 200", 1, true))
end)

test("only the approved device keeps the session alive", function()
    local access = approved()
    local server = server_with(access, { fake_client(OTHER, get("/guess/")) })
    server.last_activity = 1
    run(server)
    eq(server.last_activity, 1)
    server = server_with(access, { fake_client(PHONE, get("/" .. TOKEN .. "/deck/gray")) })
    server.last_activity = 1
    run(server)
    assert(server.last_activity > 1)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
