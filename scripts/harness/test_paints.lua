-- Factory paints, every Tesla: Core.lua colors = the 8 official codes, one vehicle script skin per entry in the same
-- order, and every new car lands on one of them (references/models.md "車漆").
local T = MinidoracatTesla
local check = H.check

-- Model Y and Model 3 Performance design-studio codes (US, DE, TW)
local OFFICIAL = { PN01 = true, PPSW = true, PX02 = true, PN00 = true, PR01 = true, PB01 = true, PB02 = true, PB00 = true,
    PPSB = true }
local media = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/"

for _, car in ipairs({ "MinidoracatTesla_ModelY", "MinidoracatTesla_Model3" }) do
    local colors = T.Specs["Base." .. car].colors

    H.section("paint table " .. car)
    local seen, bad = {}, {}
    for _, c in ipairs(colors) do
        if not OFFICIAL[c.code] or seen[c.code] then bad[#bad + 1] = tostring(c.code) end
        seen[c.code] = true
        for _, k in ipairs({ "h", "s", "v" }) do
            if type(c[k]) ~= "number" or c[k] < 0 or c[k] > 1 then bad[#bad + 1] = c.name .. "." .. k end
        end
    end
    check(#colors == 8 and #bad == 0, "8 colours, each an official code once, HSV in 0..1 (" .. table.concat(bad, ",") .. ")")

    -- skins in the vehicle script, in file order (= skin index)
    local f = assert(io.open(media .. "scripts/vehicles/" .. car .. ".txt", "r"))
    local text = f:read("*a")
    f:close()
    local skins = {}
    for tex in text:gmatch("skin%s*{%s*texture%s*=%s*([%w_/]+)") do skins[#skins + 1] = tex end
    local order = #skins == #colors
    for i, c in ipairs(colors) do
        order = order and skins[i] == "Vehicles/" .. car .. "_" .. c.name
    end
    check(order, "vehicle script skins match the colour table one to one (" .. #skins .. " skins)")
    local missing = {}
    for _, tex in ipairs(skins) do
        local t = io.open(media .. "textures/" .. tex .. ".png", "rb")
        if t then t:close() else missing[#missing + 1] = tex end
    end
    check(#missing == 0, "every skin texture exists (" .. table.concat(missing, ",") .. ")")

    H.section("paint pick " .. car)
    local hits = {}
    for k = 0, 15 do
        H.setRand((k + 0.5) / 16)
        local v = H.vehicle({ script = "Base." .. car })
        T.Create.Motor(v, v:getPartById("Engine"))
        local c = v.skin and colors[v.skin + 1]
        check(c ~= nil and v.hsv[1] == c.h and v.hsv[2] == c.s and v.hsv[3] == c.v, "rand " .. k .. ": skin " .. tostring(v.skin) .. " with its HSV")
        if c then hits[v.skin] = true end
        H.removeVehicle(v)
    end
    local n = 0
    for _ in pairs(hits) do n = n + 1 end
    check(n == 8, "the 16 draws reach all 8 skins (" .. n .. ")")
    H.setRand(0.5)
end

-- Cybertruck: stainless ($PDD, the only factory finish) and Tesla's 11 Color Paint Film wraps (shop 2024-06), drawn
-- by weight so stainless takes half the spawns (T.pickColor)
local CT = "MinidoracatTesla_Cybertruck"
local FILMS = { "Stainless", "SatinStealthBlack", "SatinCeramicWhite", "SatinRoseGold", "SatinTacticalGreen", "SatinDarkGrey",
    "SatinForestGreen", "SatinAbyssBlue", "CopperTintedClear", "SatinCrimsonRed", "SatinIridescentPurple", "SlipGrey" }
local colors = T.Specs["Base." .. CT].colors
H.section("paint table " .. CT)
local bad, total = {}, 0
for i, c in ipairs(colors) do
    if c.name ~= FILMS[i] then bad[#bad + 1] = i .. ":" .. tostring(c.name) end
    if (i == 1) ~= (c.code == "PDD") then bad[#bad + 1] = c.name .. ".code" end
    for _, k in ipairs({ "h", "s", "v" }) do
        if type(c[k]) ~= "number" or c[k] < 0 or c[k] > 1 then bad[#bad + 1] = c.name .. "." .. k end
    end
    total = total + (c.weight or 1)
end
check(#colors == 12 and #bad == 0, "12 finishes in the published order, $PDD on stainless only (" .. table.concat(bad, ",") .. ")")
check(colors[1].weight * 2 == total, "stainless weighs half of all (" .. tostring(colors[1].weight) .. " of " .. total .. ")")
local f = assert(io.open(media .. "scripts/vehicles/" .. CT .. ".txt", "r"))
local text = f:read("*a")
f:close()
local skins = {}
for tex in text:gmatch("skin%s*{%s*texture%s*=%s*([%w_/]+)") do skins[#skins + 1] = tex end
local order = #skins == 12
for i, c in ipairs(colors) do order = order and skins[i] == "Vehicles/" .. CT .. "_" .. c.name end
check(order, "12 skins, matching the table one to one (" .. #skins .. ")")

H.section("paint pick " .. CT .. " (weighted)")
local hits = {}
for k = 0, total - 1 do -- one draw per weight unit: each finish lands exactly its weight times
    H.setRand((k + 0.5) / total)
    local v = H.vehicle({ script = "Base." .. CT })
    T.Create.Motor(v, v:getPartById("Engine"))
    local c = v.skin and colors[v.skin + 1]
    if c and v.hsv[1] == c.h and v.hsv[3] == c.v then hits[v.skin + 1] = (hits[v.skin + 1] or 0) + 1 end
    H.removeVehicle(v)
end
local ok = true
for i, c in ipairs(colors) do ok = ok and hits[i] == (c.weight or 1) end
check(ok, "draws follow the weights: stainless " .. tostring(hits[1]) .. " of " .. total .. ", each film once")
-- no weight = 1: an unweighted table stays even; a planted weight shifts the draw
H.setRand(0.4)
check(T.pickColor({ {}, {} }) == 1 and T.pickColor({ { weight = 3 }, {} }) == 1, "rand 0.4: { 1, 1 } -> 1, { 3, 1 } -> 1")
H.setRand(0.6)
check(T.pickColor({ {}, {} }) == 2 and T.pickColor({ { weight = 3 }, {} }) == 1, "rand 0.6: { 1, 1 } -> 2, { 3, 1 } -> 1 (weight counts)")
H.setRand(0.5)
