package.path = "./?.lua;" .. package.path
local Scenes = require("book_rewind/ui/scenes")
local Themes = require("book_rewind/ui/themes")

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

local THEMES = { "gray", "eink", "vibrant" }
local FAMILY_COLORS = { "bg", "ink", "second", "text", "inner", "t1", "t2" }

local function luminance(color)
    local function channel(value)
        local v = value / 255
        return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(color[1]) + 0.7152 * channel(color[2]) + 0.0722 * channel(color[3])
end
local function contrast(a, b)
    local la, lb = luminance(a) + 0.05, luminance(b) + 0.05
    return math.max(la, lb) / math.min(la, lb)
end
local function is_color(value)
    return type(value) == "table" and #value == 3 and value[1] >= 0 and value[1] <= 255
end

test("all themes have the same families, with every color", function()
    for family in pairs(Themes.vibrant.families) do
        for _, name in ipairs(THEMES) do
            local palette = Themes[name].families[family]
            assert(palette, name .. " has no family " .. family)
            for _, key in ipairs(FAMILY_COLORS) do
                assert(is_color(palette[key]), name .. "." .. family .. " has no " .. key)
            end
        end
    end
end)

test("gray theme uses only gray tones, so it can be drawn in 8 bits", function()
    local function gray(color)
        assert(color[1] == color[2] and color[2] == color[3], "not gray")
    end
    for _, palette in pairs(Themes.gray.families) do
        for _, key in ipairs(FAMILY_COLORS) do
            gray(palette[key])
        end
    end
    for _, color in ipairs(Themes.gray.spines) do
        gray(color)
    end
    for _, pair in ipairs(Themes.gray.covers) do
        gray(pair[1]); gray(pair[2])
    end
    for _, h in pairs(Themes.gray.hours) do
        gray(h.bg); gray(h.text)
    end
end)

test("every card uses a family and a scene that exist", function()
    for key, spec in pairs(Themes.cards) do
        assert(Themes.vibrant.families[spec.family], key .. " has no family")
        for _, name in ipairs(THEMES) do
            local layers = Scenes.card(spec.scene, Themes[name].families[spec.family])
            assert(#layers > 0, key .. " has no layers")
        end
    end
end)

test("what continues past the card is not drawn on a device", function()
    for _, id in ipairs({ "session", "summary", "best_day" }) do
        local found = false
        for _, layer in ipairs(Themes.layers(Themes.gray, { id = id })) do
            found = found or layer.beyond_card == true
        end
        assert(found, id .. " does not continue past the card")
    end
end)

test("the 41 cards besides the four hour scenes are all listed", function()
    local count = 0
    for _ in pairs(Themes.cards) do
        count = count + 1
    end
    eq(count, 41)
end)

test("the hour of day picks the period", function()
    eq(Themes.period(0), "dawn"); eq(Themes.period(4), "dawn")
    eq(Themes.period(5), "morning"); eq(Themes.period(11), "morning")
    eq(Themes.period(12), "afternoon"); eq(Themes.period(17), "afternoon")
    eq(Themes.period(18), "night"); eq(Themes.period(23), "night")
end)

test("every period has its scene in every theme", function()
    for _, name in ipairs(THEMES) do
        for _, hour in ipairs({ 3, 8, 15, 22 }) do
            local layers = Themes.layers(Themes[name], { id = "hours", best_hour = hour })
            assert(#layers > 0)
        end
    end
end)

test("text stays readable on its background", function()
    for _, name in ipairs(THEMES) do
        for family, palette in pairs(Themes[name].families) do
            local ratio = contrast(palette.text, palette.bg)
            assert(ratio >= 4.5, string.format("%s.%s has contrast %.1f", name, family, ratio))
        end
        for period, h in pairs(Themes[name].hours) do
            local ratio = contrast(h.text, h.bg)
            assert(ratio >= 4.5, string.format("%s.hours.%s has contrast %.1f", name, period, ratio))
        end
    end
end)

test("the profile card is found by its art", function()
    local palette = Themes.palette(Themes.vibrant, { id = "archetype", art = "profile_night_owl" })
    eq(palette, Themes.vibrant.families[Themes.cards.profile_night_owl.family])
end)

test("a card missing from the list still gets colors and a scene", function()
    assert(Themes.palette(Themes.gray, { id = "future_card" }).bg)
    assert(#Themes.layers(Themes.gray, { id = "future_card" }) > 0)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
