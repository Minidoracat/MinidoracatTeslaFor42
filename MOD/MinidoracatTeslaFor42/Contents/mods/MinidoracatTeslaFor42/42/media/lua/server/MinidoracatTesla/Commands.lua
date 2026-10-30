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

-- MP server -> the clients with an online player for which near(player) is true: `cmd` once per client, none to
-- `except`'s client. sendServerCommand(player, ...) goes to the player's connection (GameServer.java:3562-3569) and
-- the client runs OnServerCommand once per packet with no player in it (GameClient.java:1055-1071), so one per player
-- near would replay the anim or sound on a split-screen client for each of its players. A client is its online ids'
-- slot: id = slot * 4 + split-screen index (GameServer.java:2686, ConnectCoopPacket.java:125). Returns how many.
function T.sendClients(near, cmd, args, except)
    local done, n = {}, 0
    if except then done[math.floor(except:getOnlineID() / 4)] = true end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        local c = math.floor(p:getOnlineID() / 4)
        if not done[c] and near(p) then
            done[c] = true
            sendServerCommand(p, T.MODULE, cmd, args)
            n = n + 1
        end
    end
    return n
end

-- ---- per-player budget (a modified client can send any command, as often as it likes) ----
-- MP: every command passes a fixed window per player and bucket before its handler (VehicleManager's rateLimited,
-- MinidoracatVehicleManager_Server.lua:535-541): at most `max` per `ms`, the rest dropped and counted in
-- CR.dropped[bucket]; the first drop of a window logs one line. Commands without a row share `default`. SP: no other
-- client, no budget. "legit" below = the real client's busiest window, assuming a person clicks at most twice a
-- second; the harness plays that minute through this dispatch (test_cmd_rate.lua lists where) and every row is at
-- least 1.5 times it, motor exactly it. No reply: past these only a modified client gets, and a reply per drop would
-- grow with the flood. Not played there, one per click or per login, inside `default`: camp, sentry, chargeInfo,
-- phoneUnpair, inboxPull, and the Cybertruck's radial slices roofLight, psOn, psOff, outletOn, outletOff.
local CR = { dropped = {} }
CR.LIMITS = {
    default = { max = 40, ms = 10000 },      -- legit 20: one per click (charge card, camp, sentry, pairing), autoLock 2 a
                                             -- second for 3 s, keySweep 1 a second; keyTap / autoLock chirp like the
                                             -- app's lock but are walk-paced (a timed action, 6 tries per exit)
    motor = { max = 10, ms = 5000 },         -- legit 10: a beat per 5 s, +2 per motor stop and start (SoundRelay.lua)
    appStatus = { max = 20, ms = 10000 },    -- legit ~10: a poll per 2 s, one per car picked (App:select) instead; each
                                             -- builds the car's state, VehicleManager's whole ledger with it
    appStatusAll = { max = 15, ms = 10000 }, -- legit 10: the car list sends one a second (PhoneApp LIST_MS) however
                                             -- many cars or opens; each = 16 appStatus
    appAlerts = { max = 20, ms = 10000 },    -- legit ~10: one per car picked or security page opened (2 clicks each)
    appAction = { max = 30, ms = 10000 },    -- legit 20: one per button press (lock and unlock chirp to everyone near)
    liftgate = { max = 30, ms = 10000 },     -- legit 20: one per click on the car picture; each tells the players near
}
T.CommandRate = CR

-- online id -> { sid = SteamID, [bucket] = { start, n } }. Keyed by the id (slot * 4 + split-screen index,
-- GameServer.java:2686, ConnectCoopPacket.java:125), not the username: a respawn or a split-screen guest names itself
-- (Core.lua T.account), so a name change must not open a fresh budget. A respawn keeps the id (ConnectCoopPacket.java:
-- 93,100); a new connection may get a freed one (GameServer.java:2669-2676), so the table stays as small as the
-- server. The SteamID beside it (the connection's, IsoPlayer.setSteamID in GameServer.java:2843-2845; guests share
-- it) tells a new occupant on a Steam server, who starts with fresh windows. A no-steam server has none (0 for all):
-- there a newcomer on a freed id inherits what is left of the last occupant's windows (each ends at most 10 s after
-- it started), and a login inboxPull dropped then waits for the next login (the inbox stays).
-- ponytail: no engine floor, but the id is given at connect and the newcomer then loads the world before its first
-- command (E2E tesla-harden2-1028-*: "game loading took" 24-36 s); key by a per-connection counter if a no-steam
-- server ever logs a rate-limit line right after a join.
-- Not the IsoPlayer: a kept reference would hold a player who left until the id is used again (family pitfalls.md).
local windows = {}
function CR.limited(player, command)
    local b = CR.LIMITS[command] and command or "default"
    local lim, id, t = CR.LIMITS[b], player:getOnlineID(), getTimestampMs() -- IsoPlayer.java:6490 (GameServer.java:2835-2839)
    local sid, mine = T.sidOf(player), windows[id] -- Core.lua: a double, compared only
    if not mine or mine.sid ~= sid then mine = { sid = sid }; windows[id] = mine end
    local w = mine[b]
    if not w then w = {}; mine[b] = w end
    -- t < start: the wall clock was set back (getTimestampMs = System.currentTimeMillis); start over, do not stretch it
    if not w.start or t < w.start or t - w.start >= lim.ms then w.start, w.n = t, 0 end
    w.n = w.n + 1
    if w.n <= lim.max then return false end
    CR.dropped[b] = (CR.dropped[b] or 0) + 1
    if w.n == lim.max + 1 then
        T.log("rate limit: " .. b .. " over " .. lim.max .. " per " .. lim.ms .. " ms, dropping " .. tostring(command)
            .. " from " .. tostring(player:getUsername()) .. " oid=" .. tostring(id))
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
