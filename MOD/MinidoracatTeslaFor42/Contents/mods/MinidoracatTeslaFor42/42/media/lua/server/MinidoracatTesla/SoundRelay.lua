-- Server side of the motor sound for other players (client/MinidoracatTesla/Sound.lua): `motor` { vid, on } from the
-- driver, relayed to every other online player within RELAY_TILES. No car state, no timers: the driver repeats "on"
-- every 5 s and listeners forget a car on their own.
-- Accepted from the car's driver only; "off" also when the seat is already empty (the exit packet can beat it here,
-- and with no driver there is nothing left to silence). Anything else is dropped without a reply.
-- At most RATE_MAX commands per player per RATE_WINDOW_MS (the fixed window of VehicleManager's rateLimited,
-- MinidoracatVehicleManager_Server.lua:535-541); the rest are dropped. A driver sends one beat per 5 s plus an "off"
-- and an "on" each time the motor stops and starts (power key, seat, charge cable); a dropped "on" comes again with
-- the next beat, a dropped "off" ends on the listener's HEARD_MS expiry.
-- A summoned car (Remote.lua, AutoDrive drives it empty) has no driver to send beats: the server itself tells everyone
-- near the car, the summoner too, when the summon starts and ends (R.summon; { vid, on, sum = true }).
if isClient() then return end
require "MinidoracatTesla/Commands"

local T = MinidoracatTesla
local R = { RELAY_TILES = 120, stats = { relayed = 0, refused = 0, limited = 0 } } -- 120: a car on its way is known before it is heard
R.RATE_WINDOW_MS, R.RATE_MAX = 5000, 10 -- driving: 1 per 5 s; each stop and start of the motor: +2
T.SoundRelay = R

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end

-- online id -> { start, n }. The id, not the username: a split-screen guest names itself (Core.lua T.account), and
-- no IsoPlayer keys (Kahlua has no weak tables, family pitfalls.md). Ids are per connected player and get reused, so
-- the table stays as small as the server; a reused id inherits a window at most RATE_WINDOW_MS old.
local windows = {}
local function rateLimited(player)
    local t, who = getTimestampMs(), player:getOnlineID() -- IsoPlayer.java:6490, set at login GameServer.java:2835-2839
    local w = windows[who]
    if not w or t - w.start >= R.RATE_WINDOW_MS then w = { start = t, n = 0 }; windows[who] = w end
    w.n = w.n + 1
    return w.n > R.RATE_MAX
end

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
    if rateLimited(player) then
        R.stats.limited = R.stats.limited + 1
        return 0
    end
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
