-- Server side of module "MinidoracatTesla": one OnClientCommand dispatch into MinidoracatTesla.ServerCommands.
-- SP routes sendClientCommand here too (SinglePlayerClient.java:101-123 -> OnClientCommand).
if isClient() then return end
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
T.ServerCommands = T.ServerCommands or {}
T.NEAR = 10 -- tiles between player and car for commands sent from outside

local function isInt(n) return type(n) == "number" and n == n and math.floor(n) == n end

-- Shared validation for handlers: player, Tesla by args.vid, distance. Denies and returns nil on failure.
function T.commandVehicle(player, args, maxDist)
    if not player then return nil end
    local vid = args and args.vid
    local v = isInt(vid) and getVehicleById(vid) or nil -- whole numbers only: fractions truncate to another id
    if not v or not T.isTesla(v) then
        T.deny(player, "NO_VEHICLE", isInt(vid) and vid or nil)
        return nil
    end
    if player:getVehicle() ~= v and player:DistTo(v) > (maxDist or T.NEAR) then
        T.deny(player, "TOO_FAR", vid)
        return nil
    end
    return v
end

-- ---- per-player budget (a modified client can send any command, as often as it likes) ----
-- MP: every command passes a fixed window per player and bucket before its handler (VehicleManager's rateLimited,
-- MinidoracatVehicleManager_Server.lua:535-541): at most `max` per `ms`, the rest dropped and counted in
-- CR.dropped[bucket]; the first drop of a window logs one line. No reply: every budget sits well above the real
-- client's busiest window (the harness plays a minute of each), so only a modified client is cut, and a reply per
-- drop would grow with the flood. Commands without a row share `default`. SP: no other client, no budget.
-- legit = the real client's busiest window; a person clicks at most about twice a second.
local CR = { dropped = {} }
CR.LIMITS = {
    default = { max = 40, ms = 10000 },      -- legit ~20: one per click (charge card, camp, sentry, pairing, key tap),
                                             -- autoLock 2 a second for 3 s, keySweep at most 1 a second
    motor = { max = 10, ms = 5000 },         -- legit 10: a beat per 5 s, +2 per motor stop and start (SoundRelay.lua)
    appStatus = { max = 20, ms = 10000 },    -- legit ~15: a poll per 2 s and one per car picked (App:select); each
                                             -- builds the car's state, VehicleManager's whole ledger with it
    appStatusAll = { max = 15, ms = 10000 }, -- legit 10: one per car list opened (per 16 other cars); each = 16 appStatus
    appAlerts = { max = 20, ms = 10000 },    -- legit 10: one per car picked or security page opened
    appAction = { max = 30, ms = 10000 },    -- legit 20: one per button press (lock and unlock chirp to everyone near)
    liftgate = { max = 30, ms = 10000 },     -- legit 20: one per click on the car picture; each tells every online player
}
T.CommandRate = CR

-- online id -> bucket -> { start, n }. The id, not the username: a split-screen guest names itself (Core.lua
-- T.account), and no IsoPlayer keys (Kahlua has no weak tables, family pitfalls.md). Ids are per connected player and
-- get reused, so the table stays as small as the server; a reused id inherits windows at most 10 s old.
local windows = {}
function CR.limited(player, command)
    local b = CR.LIMITS[command] and command or "default"
    local lim, who, t = CR.LIMITS[b], player:getOnlineID(), getTimestampMs() -- IsoPlayer.java:6490 (GameServer.java:2835-2839)
    local mine = windows[who]
    if not mine then mine = {}; windows[who] = mine end
    local w = mine[b]
    if not w then w = {}; mine[b] = w end
    -- t < start: the wall clock was set back (getTimestampMs = System.currentTimeMillis); start over, do not stretch it
    if not w.start or t < w.start or t - w.start >= lim.ms then w.start, w.n = t, 0 end
    w.n = w.n + 1
    if w.n <= lim.max then return false end
    CR.dropped[b] = (CR.dropped[b] or 0) + 1
    if w.n == lim.max + 1 then
        T.log("rate limit: " .. b .. " over " .. lim.max .. " per " .. lim.ms .. " ms, dropping " .. tostring(command)
            .. " from " .. tostring(player:getUsername()) .. " oid=" .. tostring(who))
    end
    return true
end

if not T.serverDispatch then
    T.serverDispatch = true
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= T.MODULE then return end
        local fn = T.ServerCommands[command]
        if not fn or (isServer() and CR.limited(player, command)) then return end
        local ok, err = pcall(fn, player, type(args) == "table" and args or {})
        if not ok then T.log("command " .. tostring(command) .. " failed: " .. tostring(err)) end
    end)
end
