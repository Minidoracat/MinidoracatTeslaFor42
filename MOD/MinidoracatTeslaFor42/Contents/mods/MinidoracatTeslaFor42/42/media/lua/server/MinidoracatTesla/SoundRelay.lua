-- Server side of the motor sound for other players (client/MinidoracatTesla/Sound.lua): `motor` { vid, on } from the
-- driver, relayed to every other online player within RELAY_TILES. No state, no timers: the driver repeats "on"
-- every 5 s and listeners forget a car on their own.
-- Accepted from the car's driver only; "off" also when the seat is already empty (the exit packet can beat it here,
-- and with no driver there is nothing left to silence). Anything else is dropped without a reply.
if isClient() then return end
require "MinidoracatTesla/Commands"

local T = MinidoracatTesla
local R = { RELAY_TILES = 120, stats = { relayed = 0, refused = 0 } } -- 120: a car on its way is known before it is heard
T.SoundRelay = R

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end

T.ServerCommands = T.ServerCommands or {}
-- returns how many players it told (the E2E counts it; the dispatcher ignores it)
T.ServerCommands.motor = function(player, args)
    local v = isInt(args.vid) and getVehicleById(args.vid) or nil
    local on = args.on == true
    local drv = v and v:getDriver()
    if not v or not T.isTesla(v) or (drv ~= player and (on or drv ~= nil)) then
        R.stats.refused = R.stats.refused + 1
        return 0
    end
    if not isServer() then return 0 end -- SP: no one else (the driver does not send there anyway)
    local out, n = { vid = v:getId(), on = on }, 0
    local x, y, r2 = v:getX(), v:getY(), R.RELAY_TILES * R.RELAY_TILES
    local list = getOnlinePlayers() -- LuaManager.java:4457
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        local dx, dy = p:getX() - x, p:getY() - y
        if p ~= player and dx * dx + dy * dy <= r2 then
            sendServerCommand(p, T.MODULE, "motor", out) -- LuaManager.java:8966-8970
            n = n + 1
        end
    end
    R.stats.relayed = R.stats.relayed + n
    return n
end

return R
