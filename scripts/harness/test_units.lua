-- Units.lua (client): the conversions and the mod option. What each display shows in imperial is in test_hud.lua
-- ("units") and test_phone_app.lua ("units"); the real options page and screens are E2E units-sp.
local check = H.check
H.side(true, false)
require "MinidoracatTesla/Units"
local T = MinidoracatTesla
local U = T.Units
local FILE = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/client/MinidoracatTesla/Units.lua"

H.section("units: reading the option")
local value
check(U.opt == nil and U.imperial() == false and U.len(70) == 70, "no option (no PZAPI): metric, numbers as they are")
U.opt = { getValue = function() return value end }
local metric = true
for _, v in ipairs({ 1, 3, 0, "2", false }) do -- only the combo's second item is imperial
    value = v
    metric = metric and U.imperial() == false
end
value = nil
check(metric and U.imperial() == false, "the option at 1, 3, 0, \"2\", false or nil: metric")
value = 2
check(U.imperial() == true, "the option at 2: imperial")

H.section("units: conversions")
local lens = { [0] = 0, [1] = 1, [69] = 43, [70] = 43, [71] = 44, [86] = 53, [105] = 65, [120] = 75, [600] = 373 }
local bad = {}
for km, want in pairs(lens) do
    if U.len(km) ~= want then bad[#bad + 1] = km .. "->" .. tostring(U.len(km)) end
end
check(#bad == 0, "len: whole km and km/h to whole miles and mph, 70 -> 43 like AutoDrive's card (" .. table.concat(bad, ", ") .. ")")
bad = {}
for _, e in ipairs({ { 1, 3 }, { 2, 7 }, { 3, 10 }, { 50, 160 }, { 64, 210 }, { 152.8, 500 } }) do
    if U.feet(e[1]) ~= e[2] then bad[#bad + 1] = e[1] .. "->" .. tostring(U.feet(e[1])) end
end
check(#bad == 0, "feet: tens from 10 ft, whole feet below (a 1 tile Bluetooth range is not 0 ft) (" .. table.concat(bad, ", ") .. ")")
bad = {}
for _, e in ipairs({ { 3, "Feet", "10" }, { 50, "Feet", "160" }, { 152.8, "Feet", "500" }, { 152.9, "Miles", "0.1" },
    { 241, "Miles", "0.1" }, { 242, "Miles", "0.2" }, { 1609, "Miles", "1.0" }, { 16093, "Miles", "10.0" } }) do
    local key, n = U.dist(e[1])
    if key ~= e[2] or n ~= e[3] then bad[#bad + 1] = e[1] .. "->" .. tostring(key) .. " " .. tostring(n) end
end
check(#bad == 0, "dist: feet up to 500, then miles to one decimal, never 0.0 mi (" .. table.concat(bad, ", ") .. ")")
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 1000 do if U.imperial() then U.len(70) end end
local grew = collectgarbage("count") - kb
collectgarbage("restart")
check(grew == 0, "imperial() and len() x1000 allocate nothing (" .. grew .. " KB)")

H.section("units: the mod option")
-- Units.lua again with a PZAPI.ModOptions (PZAPI/ModOptions.lua: create, addDescription, addComboBox, addItem)
local created, boot = {}, nil
local savedPZAPI, savedUI, savedAdd = PZAPI, MinidoracatUI, Events.OnGameBoot.Add
PZAPI = { ModOptions = { create = function(_, id, name)
    local o = { id = id, name = name, texts = {}, combos = {} }
    function o:addDescription(text) self.texts[#self.texts + 1] = text end
    function o:addComboBox(cid, cname, tooltip)
        local c = { id = cid, name = cname, tooltip = tooltip, items = {} }
        function c:addItem(iname, selected) self.items[#self.items + 1] = { iname, selected } end
        self.combos[#self.combos + 1] = c
        return c
    end
    created[#created + 1] = o
    return o
end } }
Events.OnGameBoot.Add = function(fn) boot = fn end
dofile(FILE)
Events.OnGameBoot.Add = savedAdd
local o = created[1]
local c = o and o.combos[1]
check(#created == 1 and o.id == "MinidoracatTesla" and o.name == "IGUI_MinidoracatTesla_Options",
    "one options section, id MinidoracatTesla (in players' ModOptions.ini)")
check(o and #o.texts == 1 and #o.combos == 1 and c.id == "Units" and c.tooltip == nil,
    "a description (vanilla shows a combo box no tooltip) and the combo box \"Units\"")
check(c and #c.items == 2 and c.items[1][2] == true and not c.items[2][2] and T.Units.opt == c,
    "two items, Metric first and the default; Units.opt is the combo box")
-- the family UI framework's backup, only when it is there and new enough (ModOptionsBackup: API revision 23)
local protected, restored = {}, 0
local function framework(rev, cap)
    return { v1 = { API_MAJOR = 1, API_REVISION = rev, CAPABILITIES = { modOptionsBackup = cap },
        ModOptionsBackup = { protect = function(opts) protected[#protected + 1] = opts; return restored end } } }
end
MinidoracatUI = nil
local ok = boot ~= nil and pcall(boot)
check(ok and #protected == 0, "OnGameBoot without the UI framework: nothing called, no error")
MinidoracatUI = framework(22, true)
boot()
MinidoracatUI = framework(23, false)
boot()
check(#protected == 0, "an older framework (revision 22) or one without the capability: not called")
MinidoracatUI = framework(23, true)
boot()
check(#protected == 1 and protected[1] == o, "revision 23 with modOptionsBackup: protect(this mod's options) once")
restored = 2
check(pcall(boot) and #protected == 2, "the backup restored 2 settings: logged, no error")

PZAPI, MinidoracatUI = savedPZAPI, savedUI
T.Units = U -- the displays hold the first load's table
U.opt = nil
H.side(false, true)
