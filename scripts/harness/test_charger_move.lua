-- Move cursor on a charger with a car plugged in (client/MinidoracatTesla/ChargerMenu.lua C.guardMoveCursor and the
-- cursor panel line in shared Chargers.lua): pick up and rotate are refused, with the reason, exactly when the shared
-- cable rule (T.mayMoveCharger -> T.mayUseCable) refuses; other tiles and other cursor modes stay vanilla. The server
-- side (ISMoveablesAction:complete) is in test_charging.lua "keyless rules".
local check = H.check
H.side(true, false)
require "MinidoracatTesla/ChargerMenu"
local T, C = MinidoracatTesla, MinidoracatTesla.Charge
local MCS = "minidoracat_tesla_01_8"

local v = H.vehicle({ kwh = 20 })
T.Battery.part(v):getModData().chg = { x = 5, y = 5, z = 0 } -- the car's side of the cable (Charging.lua C.plug)
local vid = v:getId()
local savedSys = CMinidoracatTeslaChargerSystem.instance
CMinidoracatTeslaChargerSystem.instance = { system = { getObjectAt = function(_, x, y, z)
    return x == 5 and y == 5 and z == 0 and { getModData = function() return { vid = vid } end } or nil
end } }
local sq = { getX = function() return 5 end, getY = function() return 5 end, getZ = function() return 0 end }
local empty = { getX = function() return 6 end, getY = function() return 5 end, getZ = function() return 0 end }

-- vanilla's cursor, only what the wrap reads: isValid sets canCreate and the props (ISMoveableCursor.lua:486-700)
local savedCursor = ISMoveableCursor
ISMoveableCursor = { mode = {}, invalidColor = "invalid" }
function ISMoveableCursor:isValid(square)
    self.canCreate, self.colorMod = true, "normal"
    self.origMoveProps, self.currentMoveProps = { spriteName = self.sprite }, { spriteName = self.sprite }
    return true
end
function ISMoveableCursor:setInfoPanel() self.panels, self.cached = (self.panels or 0) + 1, self.cacheSquare end
C.guardMoveCursor()
C.guardMoveCursor() -- OnGameStart again (a second game): wrapped once
local mal = H.player({ name = "mal" })
mal.getInventory = function() return { haveThisKeyId = function() return nil end, getFirstTypeEvalArgRecurse = function() return nil end } end
local function cursor(mode, sprite, square)
    ISMoveableCursor.mode[0] = mode
    local c = setmetatable({ player = 0, character = mal, sprite = sprite or MCS }, { __index = ISMoveableCursor })
    local r = c:isValid(square or sq)
    return c, r
end

v.locked = true
local c, r = cursor("pickup")
check(r == true and c.canCreate == false and c.colorMod == "normal" and c.panels == 1,
    "pick up, no key, locked car plugged in: refused (vanilla's normal tint, panel repainted as refused)")
c = cursor("rotate")
check(c.canCreate == false and c.colorMod == "invalid", "rotate, no key, locked car plugged in: refused, red")
c = cursor("pickup", "some_other_tile")
check(c.canCreate == true and c.panels == nil, "another tile on that square: vanilla")
c = cursor("pickup", MCS, empty)
check(c.canCreate == true, "a charger nobody is plugged into: vanilla")
c = cursor("place")
check(c.canCreate == true, "place mode: not this rule's business")
local panel = ISMoveableSpriteProps.getInfoPanelDescription({ spriteName = MCS }, sq, nil, mal, "pickup")
check(#panel == 1 and panel[1][1].txt == "IGUI_MinidoracatTesla_Deny_CAR_LOCKED" and panel[1][1].r == 255,
    "cursor panel: a red line with the reason (CAR_LOCKED)")
check(#ISMoveableSpriteProps.getInfoPanelDescription({ spriteName = MCS }, sq, nil, mal, "scrap") == 0,
    "cursor panel, other modes: vanilla text only")
v.locked = false
c = cursor("pickup")
check(c.canCreate == true and #ISMoveableSpriteProps.getInfoPanelDescription({ spriteName = MCS }, sq, nil, mal, "rotate") == 0,
    "unlocked car: pick up and rotate as vanilla, no reason line")
v.locked = true
c = cursor("pickup")
c.cacheSquare = sq
c:isValid(sq)
check(c.canCreate == false and c.panels == 2 and c.cached == sq, "still cursor, still refused: the cached panel text stays")
v.locked = false
c:isValid(sq)
check(c.canCreate == true and c.panels == 3 and c.cached == nil,
    "unlocked under a still cursor: the panel text is redone (the red line goes), the picture as allowed")
c:isValid(sq)
check(c.panels == 3, "then allowed and unchanged: vanilla's panel only")
vid = 98765 -- the charger names a car this client has not loaded
c = cursor("pickup")
check(c.canCreate == false and select(2, T.mayMoveCharger(mal, sq, MCS)) == "NOT_LOADED",
    "the plugged car is not loaded: refused (NOT_LOADED), not let go without the rule")
vid = v:getId()
T.Battery.part(v):getModData().chg = { x = 9, y = 9, z = 0 }
check(select(2, T.mayMoveCharger(mal, sq, MCS)) == "NOT_LOADED", "the id names a car whose cable is elsewhere (ids are reused): NOT_LOADED")
T.Battery.part(v):getModData().chg = { x = 5, y = 5, z = 0 }
v.hotwired, v.locked = true, true
check(cursor("rotate").canCreate == true, "locked but hotwired: allowed (the key in the ignition)")
v.hotwired = false
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NOT_AUTHORIZED" end }
v.locked = false
c = cursor("pickup")
local deny = ISMoveableSpriteProps.getInfoPanelDescription({ spriteName = MCS }, sq, nil, mal, "pickup")
check(c.canCreate == false and deny[1][1].txt == "IGUI_MinidoracatTesla_Deny_NOT_OWNER",
    "VehicleManager says no on an unlocked car: refused, NOT_OWNER")
MinidoracatVehicleManagerAPI = nil

ISMoveableCursor = savedCursor
CMinidoracatTeslaChargerSystem.instance = savedSys
H.side(false, true)
