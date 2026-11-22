-- Vanilla's "this part needs the key" (VehicleUtils.RequiredKeyNotFound, Vehicles.lua:1380-1389) sees only
-- haveThisKeyId, a loose key or one on a keyring. It greys the mechanics window's install / uninstall
-- (Tooltip_vehicle_keyRequired) and engine / light actions (ISVehicleMechanics.lua:324,440,484,516,721), decides
-- canInstallPart / canUninstallPart (Vehicles.lua:914,954) and whether the hood entries queue an unlock
-- (ISVehicleMenu.lua:997,1230, Vehicles.lua:851, DriveUnitMenu.lua). On a Tesla this car's key card or phone key
-- anywhere on the player counts too, the rule that starts it (Keys.lua K.bagKeyStarts) and T.authorized use: the
-- owner with the card in a bag could open the window and do nothing in it. Other cars: vanilla.
-- Not a permission: the MP server never runs a timed action's Lua isValid (NetTimedAction.java:118-120), so this is
-- the client's UI and queue; VehicleManager's own action guards still decide there.
-- In server/ because Vehicles.lua is (loaded on SP, MP clients and the dedicated server: GameLoadingState.java:149,
-- GameServer.java:1511; vanilla files before mods, LuaManager.java:1193-1194).
require "MinidoracatTesla/Keys"

local T = MinidoracatTesla
local K = T.Keys

local requiredKeyNotFound = VehicleUtils.RequiredKeyNotFound
function VehicleUtils.RequiredKeyNotFound(part, chr)
    if not requiredKeyNotFound(part, chr) then return false end
    local v = chr and part:getVehicle()
    return not (v and T.isTesla(v) and (K.phoneKey(chr, v) ~= nil or K.card(chr, v) ~= nil))
end
