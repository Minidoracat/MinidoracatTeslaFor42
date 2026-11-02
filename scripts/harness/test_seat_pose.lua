-- The seated pose in a Tesla (client/MinidoracatTesla/SeatPose.lua): MinidoracatTeslaSeated is set while a player
-- sits in any Tesla seat, MinidoracatTeslaRecline only in the two front seats; both cleared in any other car and after
-- getting out. The anim nodes they gate (AnimSets/player-vehicle/idle/MinidoracatTesla_idle_recline.xml,
-- aim/MinidoracatTesla_aim_seated.xml, aim/MinidoracatTesla_aim_recline.xml) are engine behaviour: E2E seat-head-sp
-- and aim-seat-sp.
local check = H.check

H.section("seat pose variables")
H.stub("Vehicles/ISUI/ISVehicleDashboard")
H.require("MinidoracatTesla/SeatPose")
check(H.count("OnEnterVehicle") >= 1 and H.count("OnExitVehicle") >= 1 and H.count("OnSwitchVehicleSeat") >= 1,
    "listens to enter, exit and seat switches")

MinidoracatTeslaHatLoc = MinidoracatTeslaHatLoc or "MinidoracatTesla:HatHide"
local function varPlayer(name)
    local o = H.player({ name = name })
    o.vars, o.worn, o.num = {}, {}, 0
    function o:setVariable(k, v) self.vars[k] = v end
    function o:clearVariable(k) self.vars[k] = nil end
    function o:isLocalPlayer() return true end
    function o:getWornItem(loc) return self.worn[loc] end
    return o
end
local function car(script)
    local v = H.vehicle({ script = script })
    v.seats = {}
    function v:getSeat(p) return self.seats[p] or -1 end
    return v
end
local p = varPlayer("sitter")
local tesla, van = car("Base.MinidoracatTesla_Model3"), car("Base.CarNormal")
local function sit(v, seat)
    p.vehicle = v
    if v then v.seats[p] = seat end
end

sit(tesla, 0)
local sent = #H.clientSent
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == true and p.vars.MinidoracatTeslaRecline == true, "driver of a Tesla: seated, reclined")
check(#H.clientSent == sent + 1 and H.clientSent[#H.clientSent].command == "seat",
    "the local player's enter sends seat (server/MinidoracatTesla/HatHide.lua: the hat hider, the relay to the clients near)")

sit(tesla, 2)
H.fire("OnSwitchVehicleSeat", p)
check(p.vars.MinidoracatTeslaSeated == true and p.vars.MinidoracatTeslaRecline == nil,
    "switched to a rear seat: still seated, upright")

sit(tesla, 1)
H.fire("OnSwitchVehicleSeat", p)
check(p.vars.MinidoracatTeslaRecline == true, "switched to the front passenger seat: reclined again")

sit(nil)
H.fire("OnExitVehicle", p)
sit(van, 0)
sent = #H.clientSent
H.fire("OnEnterVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil and p.vars.MinidoracatTeslaRecline == nil, "cleared on getting into a vanilla car")
check(#H.clientSent == sent, "a vanilla car sends no seat")
sit(nil)
H.fire("OnExitVehicle", p)
check(#H.clientSent == sent, "out of a vanilla car, no hider: no seat")

sit(tesla, 0)
H.fire("OnEnterVehicle", p)
sit(nil)
sent = #H.clientSent
H.fire("OnExitVehicle", p)
check(p.vars.MinidoracatTeslaSeated == nil and p.vars.MinidoracatTeslaRecline == nil, "cleared after getting out of a Tesla")
check(#H.clientSent == sent + 1 and H.clientSent[#H.clientSent].command == "seat",
    "out of a Tesla: seat even though the hider has not reached this client")
sit(van, 0)
H.fire("OnEnterVehicle", p)
p.worn[MinidoracatTeslaHatLoc] = {}
sit(nil)
sent = #H.clientSent
H.fire("OnExitVehicle", p)
check(#H.clientSent == sent + 1 and H.clientSent[#H.clientSent].command == "seat",
    "out of a vanilla car still wearing a hider: seat, the server takes it off")
p.worn[MinidoracatTeslaHatLoc] = nil

H.fire("OnExitVehicle", nil)
check(true, "an event without a player is ignored")

-- other players (MP client): synced once a game minute; nothing to do on a server or in SP
local front, rear, inVan, onFoot = varPlayer("a"), varPlayer("b"), varPlayer("c"), varPlayer("d")
front.vehicle, rear.vehicle, inVan.vehicle = tesla, tesla, van
tesla.seats[front], tesla.seats[rear] = 1, 3
for _, o in ipairs({ inVan, onFoot }) do -- left over from a Tesla
    o.vars.MinidoracatTeslaSeated, o.vars.MinidoracatTeslaRecline = true, true
end
local online = { front, rear, inVan, onFoot }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
H.fire("EveryOneMinute")
check(front.vars.MinidoracatTeslaSeated == nil, "every minute: nothing on a server")
H.side(true, false)
H.fire("EveryOneMinute")
H.side(false, true)
check(front.vars.MinidoracatTeslaSeated == true and front.vars.MinidoracatTeslaRecline == true,
    "every minute (MP client): another player in a Tesla front seat is seated and reclined")
check(rear.vars.MinidoracatTeslaSeated == true and rear.vars.MinidoracatTeslaRecline == nil,
    "every minute (MP client): another player in a Tesla rear seat is seated, upright")
check(inVan.vars.MinidoracatTeslaSeated == nil and onFoot.vars.MinidoracatTeslaRecline == nil,
    "every minute (MP client): cleared on players in another car or on foot")
getOnlinePlayers = nil

-- the server's side (server/MinidoracatTesla/HatHide.lua, the hat itself is test_hat_hide's): each seat command tells
-- the clients near the sender's online id, again AGAIN_MS later (the relay can beat that player's vehicle packet to a
-- client); the command's arguments are never read
local T = MinidoracatTesla
H.side(false, true)
H.require("MinidoracatTesla/Liftgate") -- loaded already by the HUD and door tests: Liftgate.sendNear
H.require("MinidoracatTesla/HatHide") -- loaded already by test_hat_hide: ServerCommands.seat
local Hd, savedSync, savedById = T.HatHide, T.HatHide.sync, getPlayerByOnlineID
Hd.sync = function() end
local sender = H.player({ name = "sender" })
local guest = H.player({ name = "guest", num = 1 }) -- split-screen on the sender's client
guest.oid = sender.oid + 1
local near = H.player({ name = "near", x = sender.x + 5, y = sender.y - 3 })
local far = H.player({ name = "far", x = sender.x + 96.5, y = sender.y })
local corner = H.player({ name = "corner", x = sender.x - 96, y = sender.y + 96 })
local everyone, gone = { sender, guest, near, far, corner }, false
function getOnlinePlayers() return { size = function() return #everyone end, get = function(_, i) return everyone[i + 1] end } end
function getPlayerByOnlineID(id) return not gone and id == sender.oid and sender or nil end
local function relays(from)
    local to, only = {}, true
    for i = from + 1, #H.sent do
        local s = H.sent[i]
        if s.command == "seat" then
            to[#to + 1] = s.player.name
            local keys = 0
            for _ in pairs(s.args) do keys = keys + 1 end
            only = only and keys == 1 and s.args.id == sender.oid
        end
    end
    table.sort(to)
    return table.concat(to, ","), only
end
local n0, ticks = #H.sent, H.count("OnTick")
T.ServerCommands.seat(sender, { id = near.oid, vid = 7 }) -- a forged id is not read
local to, only = relays(n0)
check(to == "corner,near" and only, "server: { id = the sender's own online id } once to each client 96 tiles on both "
    .. "axes, none to the sender's (its split-screen guest too) or 96.5 tiles away (" .. to .. ")")
check(H.count("OnTick") == ticks + 1, "...and a look-again OnTick")
n0 = #H.sent
H.advanceMs(Hd.AGAIN_MS)
H.fire("OnTick")
to, only = relays(n0)
check(to == "corner,near" and only and H.count("OnTick") == ticks,
    "AGAIN_MS later: the same relay again (for a client it reached ahead of the vehicle packet), the OnTick removed")
n0 = #H.sent
T.ServerCommands.seat(sender, {})
gone = true
H.advanceMs(Hd.AGAIN_MS)
H.fire("OnTick")
check(relays(n0) == "corner,near" and H.count("OnTick") == ticks, "the sender gone by the look-again: no second relay")
gone = false
H.side(false, false)
n0 = #H.sent
T.ServerCommands.seat(sender, {})
check(#H.sent == n0, "SP: no relay (no other client)")
Hd.sync, getPlayerByOnlineID, getOnlinePlayers = savedSync, savedById, nil

-- the server's relay of another player's seat (HatHide.lua): that player synced here at once, and again on the relay
-- AGAIN_MS later, which sets them right when the first one beat their vehicle packet here
local other = varPlayer("other")
other.oid = 4242
local savedById = getPlayerByOnlineID
function getPlayerByOnlineID(id) return id == other.oid and other or nil end
H.side(true, false)
tesla.seats[other] = 0
T.ClientCommands.seat({ id = other.oid })
check(other.vars.MinidoracatTeslaSeated == nil, "relay ahead of their enter packet: nothing to set yet")
other.vehicle = tesla -- their VehicleEnter applied here
T.ClientCommands.seat({ id = other.oid })
check(other.vars.MinidoracatTeslaSeated == true and other.vars.MinidoracatTeslaRecline == true,
    "the relay again (AGAIN_MS later): seated and reclined, not a game minute later")
tesla.seats[other] = 3
T.ClientCommands.seat({ id = other.oid })
check(other.vars.MinidoracatTeslaSeated == true and other.vars.MinidoracatTeslaRecline == nil, "switched to the rear: upright")
other.vehicle = nil
T.ClientCommands.seat({ id = other.oid })
check(other.vars.MinidoracatTeslaSeated == nil and other.vars.MinidoracatTeslaRecline == nil, "got out: cleared")
local before = #H.clientSent
T.ClientCommands.seat({ id = 999 })
T.ClientCommands.seat({ id = "4242" })
T.ClientCommands.seat({})
check(#H.clientSent == before, "an id not loaded here or not a number: nothing (and a relay never sends anything back)")
getPlayerByOnlineID = savedById

-- a real client's busiest minute through the server's dispatch (Commands.lua CommandRate): in and out of a Tesla at 2
-- clicks a second, each enter twice (OnEnterVehicle at perform and on the server's echo in MP), each exit once; none
-- dropped, the busiest 10 s at most 2 / 3 of the seat budget. A seat switch sends one (E2E seat-pose-mp SEATRELAY).
local CR = T.CommandRate
local dropped, from, reached, times = CR.dropped.seat or 0, #H.clientSent, 0, {}
for i = 0, 119 do
    if i % 2 == 0 then
        sit(tesla, 0)
        H.fire("OnEnterVehicle", p)
        H.fire("OnEnterVehicle", p)
    else
        sit(nil)
        H.fire("OnExitVehicle", p)
    end
    for _ = from + 1, #H.clientSent do times[#times + 1] = i * 500 end
    local got
    got, from = H.serve(from)
    reached = reached + (got.seat or 0)
    H.advanceMs(500)
end
local busiest = H.busiest(times, CR.LIMITS.seat.ms)
check(reached == 180 and #times == 180 and (CR.dropped.seat or 0) == dropped and busiest * 1.5 <= CR.LIMITS.seat.max,
    "a minute in and out of a Tesla, 2 clicks a second (" .. busiest .. " in the busiest 10 s): all " .. reached
    .. " reach the server's handler")
H.side(false, true)
H.advanceMs(CR.LIMITS.seat.ms)
