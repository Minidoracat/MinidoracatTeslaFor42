-- Server side of the motor sound for other players (client/MinidoracatTesla/Sound.lua): `motor` { vid, on } from the
-- driver, relayed to every other online player within RELAY_TILES. No car state, no timers: the driver repeats "on"
-- every 5 s and listeners forget a car on their own.
-- Accepted from the car's driver only; "off" also when the seat is already empty (the exit packet can beat it here,
-- and with no driver there is nothing left to silence). Anything else is dropped without a reply.
-- Its budget (10 per player per 5 s) is the dispatcher's (Commands.lua CommandRate): a driver sends one beat per 5 s
-- plus an "off" and an "on" each time the motor stops and starts (power key, seat, charge cable, a joypad player's
-- inventory hiding the dashboard, ISInventoryPage.lua:739-775); a dropped "on" comes again with the next beat, a dropped
-- "off" ends on the listener's HEARD_MS expiry (and the listener already mutes a car with no driver or a stopped motor).
-- A summoned car (Remote.lua, AutoDrive drives it empty) has no driver to send beats: the server itself tells everyone
-- near the car, the summoner too, when the summon starts and ends (R.summon; { vid, on, sum = true }).
if isClient() then return end
require "MinidoracatTesla/Commands"

local T = MinidoracatTesla
local R = { RELAY_TILES = 120, stats = { relayed = 0, refused = 0 } } -- 120: a car on its way is known before it is heard
T.SoundRelay = R

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end

T.ServerCommands = T.ServerCommands or {}

-- every online player within RELAY_TILES of car v but `except`: `motor` msg. Returns how many.
local function relay(v, msg, except)
    local n = 0
    local x, y, r2 = v:getX(), v:getY(), R.RELAY_TILES * R.RELAY_TILES
    local list = getOnlinePlayers() -- LuaManager.java:4457
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        local dx, dy = p:getX() - x, p:getY() - y
        if p ~= except and dx * dx + dy * dy <= r2 then
            sendServerCommand(p, T.MODULE, "motor", msg) -- LuaManager.java:8966-8970
            n = n + 1
        end
    end
    R.stats.relayed = R.stats.relayed + n
    return n
end

-- the summon's motor layers on (start) or off (end) for everyone near; SP: the one player (T.send runs the handler).
-- back: a straight reverse (no forward PWS: listeners far away read no speed sign, Sound.lua estimates it from moves)
-- ponytail: players who walk into range after the start hear nothing until the next summon, and far listeners hear
-- the forward PWS while a come / target summon backs out of a dead end; beats from the summoner's game if that matters.
function R.summon(v, on, back)
    local msg = { vid = v:getId(), on = on, sum = true, back = back == true or nil }
    if not isServer() then return T.send(nil, "motor", msg) end
    return relay(v, msg, nil)
end

-- a car AutoDrive is summoning (Remote.lua): its sound belongs to the server's R.summon, nobody's "off" ends it
local function summoned(v)
    local api = T.Remote and T.Remote.summonApi and T.Remote.summonApi()
    return api ~= nil and api.summonInfo(v) ~= nil
end

-- returns how many players it told (the E2E counts it; the dispatcher ignores it)
T.ServerCommands.motor = function(player, args)
    local v = isInt(args.vid) and getVehicleById(args.vid) or nil
    local on = args.on == true
    local drv = v and v:getDriver()
    if not v or not T.isTesla(v) or (drv ~= player and (on or drv ~= nil or summoned(v))) then
        R.stats.refused = R.stats.refused + 1
        return 0
    end
    if not isServer() then return 0 end -- SP: no one else (the driver does not send there anyway)
    return relay(v, { vid = v:getId(), on = on }, player)
end

return R
