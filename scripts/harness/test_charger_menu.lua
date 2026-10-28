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
    local sq = { getX = function() return x end, getY = function() return 5 end, getZ = function() return 0 end }
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
    v.locked = true
    local own = menu(H.player({ name = "own", keys = { [77] = true } }), iso)
    check(own ~= nil and not own.notAvailable, k[1] .. ": the key holder's Unplug row is live (car locked)")
    local mal = menu(H.player({ name = "mal" }), iso)
    check(mal ~= nil and mal.notAvailable == true and mal.toolTip.description == "IGUI_MinidoracatTesla_Deny_CAR_LOCKED",
        k[1] .. ": no key, car locked -> Unplug greyed with the server's CAR_LOCKED reason, no code appended")
    v.locked = false
    mal = menu(H.player({ name = "mal" }), iso)
    check(mal ~= nil and not mal.notAvailable, k[1] .. ": no key, car unlocked -> Unplug live")
end
local calls = 0
local rule = T.mayUseCable
T.mayUseCable = function(...) calls = calls + 1; return rule(...) end
menu(H.player({ name = "mal" }), charger(30, "minidoracat_tesla_01_9", v:getId()))
T.mayUseCable = rule
check(calls == 1, "the menu asks the shared cable rule (T.mayUseCable), not a copy of it")

ISWorldObjectContextMenu = savedMenu
H.side(false, true)
