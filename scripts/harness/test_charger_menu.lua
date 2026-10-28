-- Charger right-click menu (client/MinidoracatTesla/ChargerMenu.lua): plug and unplug rows are greyed with the
-- server's NOT_OWNER exactly when the shared cable rule (Chargers.lua T.mayUseCable) refuses, both charger kinds.
local check = H.check
H.side(true, false)
for _, m in ipairs({ "Map/CGlobalObjectSystem", "Map/CGlobalObject", "TimedActions/ISBaseTimedAction" }) do H.stub(m) end
local function derive(base, name) local c = setmetatable({ Type = name }, { __index = base }); c.__index = c; return c end
CGlobalObject = CGlobalObject or { derive = derive }
CGlobalObjectSystem = CGlobalObjectSystem or { derive = derive, RegisterSystemClass = function() end }
ISBaseTimedAction = ISBaseTimedAction or { derive = derive }
local savedMenu = ISWorldObjectContextMenu
ISWorldObjectContextMenu = { addToolTip = function() return { description = "" } end }
require "MinidoracatTesla/ChargerMenu"
local T = MinidoracatTesla

-- one plugged charger per kind; the client's synced GOS object says which car
local synced = {}
CMinidoracatTeslaChargerSystem.instance = { system = { getObjectAt = function(_, x, y, z)
    local o = synced[x .. "," .. y .. "," .. z]
    return o and { getModData = function() return o end } or nil
end } }
local function charger(x, sprite, vid)
    synced[x .. ",5,0"] = { x = x, y = 5, z = 0, vid = vid }
    local sq = { getX = function() return x end, getY = function() return 5 end, getZ = function() return 0 end,
        isOutside = function() return false end, isNoPower = function() return false end, -- indoors on the grid
        hasGridPower = function() return true end, getRoom = function() return {} end }
    return { getSquare = function() return sq end, getSprite = function() return { getName = function() return sprite end } end }
end
local function menu(playerObj, iso)
    local rows = {}
    local ctx = { addOption = function(_, text, target, fn, a, b)
        local opt = { name = text, target = target, onSelect = fn, param1 = a, param2 = b }
        rows[#rows + 1] = opt
        return opt
    end }
    local savedPlayer = getSpecificPlayer
    getSpecificPlayer = function() return playerObj end
    H.fire("OnFillWorldObjectContextMenu", 0, ctx, { iso }, false)
    getSpecificPlayer = savedPlayer
    for _, r in ipairs(rows) do
        if r.name == "ContextMenu_MinidoracatTesla_Unplug" then return r end
    end
end

local v = H.vehicle({ kwh = 20 })
for _, k in ipairs({ { "WallConnector", "minidoracat_tesla_01_0", 10 }, { "MobileConnector", "minidoracat_tesla_01_8", 20 } }) do
    local iso = charger(k[3], k[2], v:getId())
    local own = menu(H.player({ name = "own", keys = { [77] = true } }), iso)
    check(own ~= nil and not own.notAvailable, k[1] .. ": the key holder's Unplug row is live")
    local mal = menu(H.player({ name = "mal" }), iso)
    check(mal ~= nil and mal.notAvailable == true and mal.toolTip.description:find("IGUI_MinidoracatTesla_Deny_NOT_OWNER", 1, true) == 1,
        k[1] .. ": no key -> Unplug greyed with the server's NOT_OWNER reason")
end
local calls = 0
local rule = T.mayUseCable
T.mayUseCable = function(...) calls = calls + 1; return rule(...) end
menu(H.player({ name = "mal" }), charger(30, "minidoracat_tesla_01_9", v:getId()))
T.mayUseCable = rule
check(calls == 1, "the menu asks the shared cable rule (T.mayUseCable), not a copy of it")

-- Mobile Connector without power (decisions.md 2026-10-28): one greyed row says where it works; with power, none
local function fakeSq(x, y, f)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
        getVehicleContainer = function() return nil end, isNoPower = function() return false end,
        hasGridPower = function() return f.grid == true end, getRoom = function() return f.room end,
        getAdjacentSquare = function() return nil end, isOutside = function() return f.room == nil end,
        haveElectricity = function() return f.elec == true end, getGenerator = function() return f.gen end }
end
local function hintRow(f, genNext, sprite, vid)
    local here = fakeSq(40, 5, f)
    local running = { isActivated = function() return true end, getFuel = function() return 5 end }
    local gsq = genNext and fakeSq(41, 6, { gen = running })
    local savedCell, savedPlayer = getCell, getSpecificPlayer
    getCell = function() return { getGridSquare = function(_, x, y)
        if x == 40 and y == 5 then return here elseif gsq and x == 41 and y == 6 then return gsq end
    end } end
    getSpecificPlayer = function() return H.player({ name = "own" }) end
    synced["40,5,0"] = { x = 40, y = 5, z = 0, vid = vid or false }
    local iso = { getSquare = function() return here end,
        getSprite = function() return { getName = function() return sprite or "minidoracat_tesla_01_8" end } end }
    local rows = {}
    local ctx = { addOption = function(_, text) local o = { name = text }; rows[#rows + 1] = o; return o end }
    H.fire("OnFillWorldObjectContextMenu", 0, ctx, { iso }, false)
    getCell, getSpecificPlayer = savedCell, savedPlayer
    for _, r in ipairs(rows) do
        if r.name == "ContextMenu_MinidoracatTesla_MobileNoPower" then return r end
    end
end
local noPow = hintRow({ elec = true })
check(noPow ~= nil and noPow.notAvailable == true, "Mobile Connector outdoors, only in a generator's range: a greyed 'no power here' row")
check(hintRow({ elec = true }, true) == nil, "running generator next to it: no hint")
check(hintRow({ room = {}, grid = true }) == nil, "indoors on the grid: no hint")
check(hintRow({ room = {}, elec = true }) == nil, "indoors on a generator's power: no hint")
check(hintRow({}, false, "minidoracat_tesla_01_0") == nil, "Wall Connector: no such row")
check(hintRow({ elec = true }, false, nil, v:getId()) ~= nil, "plugged in with no power: the row is there too (the card says nopower)")
ISWorldObjectContextMenu = savedMenu
H.side(false, true)
