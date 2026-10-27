-- VehicleManager link on the client (optional, detected at run time; plan-phone-app-v2-1027 2.2):
--   * V.cars(playerNum): the Teslas in the player's VehicleManager fleet (own + shared with them) from its listOwned:
--     { oid, keyId?, name?, script, x?, y?, z?, ageMs?, mine }. UX only: the server asks VehicleManager itself
--     (server/MinidoracatTesla/Remote.lua R.mayTrack). {} without VehicleManager or before its fleet data arrives.
--   * "Open Tesla App" in VehicleManager's vehicle menu (its MVM.clientMenuHooks), only on a Tesla the player carries
--     a phone key for (K.phoneKey); otherwise not shown at all.
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"

local T = MinidoracatTesla
local K = T.Keys
local V = {}
T.VMLink = V

function V.cars(playerNum)
    local api = MinidoracatVehicleManagerAPI
    local list = api and type(api.listOwned) == "function" and api.listOwned(playerNum) or nil
    local out = {}
    for _, c in ipairs(list or {}) do
        if T.Specs[c.script] then out[#out + 1] = c end
    end
    return out
end

function V.openApp(playerNum, keyId)
    local App = T.PhoneApp
    if App then App.open(playerNum, { keyId = keyId }) end
end

-- hook(player, sub, vehicle, row): VehicleManager's Client.lua, after its own rows in the "Vehicle management" submenu
function V.menuHook(player, sub, vehicle)
    if not (vehicle and T.isTesla(vehicle) and K.phoneKey(player, vehicle)) then return end
    sub:addOption(getText("ContextMenu_MinidoracatTesla_OpenApp"), player:getPlayerNum(), V.openApp, vehicle:getKeyId())
end

-- VehicleManager isn't a require (AGENTS.md): hook in once all client Lua is loaded, only when it is there
function V.install()
    local mvm = MinidoracatVehicleManager
    if not mvm or V.installed then return end
    V.installed = true
    mvm.clientMenuHooks = mvm.clientMenuHooks or {}
    table.insert(mvm.clientMenuHooks, V.menuHook)
end
Events.OnGameStart.Add(V.install)

return V
