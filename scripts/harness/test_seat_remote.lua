-- Another player seated in a Tesla drawn from its seat (client/MinidoracatTesla/RemoteSeat.lua): who is watched
-- (SeatPose.lua's handler of the server's `seat` relay and its game-minute scan call RemoteSeat.watch), the OnTick
-- putting them on the seat's world position, and the OnTick going once nobody is watched. The engine's update order
-- and what the frame draws are E2E seat-remote-mp (`RENDERPOS`, `ORDER`).
local check = H.check
local T = MinidoracatTesla
local saved = { Vector3f = Vector3f, byId = getPlayerByOnlineID, online = getOnlinePlayers }
Vector3f = { new = function()
    local v = { _x = 0, _y = 0, _z = 0 }
    function v:set(x, y, z) self._x, self._y, self._z = x, y, z; return self end
    function v:x() return self._x end
    function v:y() return self._y end
    function v:z() return self._z end
    return v
end }

H.section("remote seat")
H.require("MinidoracatTesla/SeatPose") -- the relay handler and the minute scan
H.require("MinidoracatTesla/RemoteSeat")
local R = T.RemoteSeat

local function rider(name, isLocal)
    local p = H.player({ name = name })
    function p:isLocalPlayer() return isLocal == true end
    function p:setX(x) self.x = x end
    function p:setY(y) self.y = y end
    function p:setZ(z) self.z = z end
    function p:setVariable() end -- SeatPose's game-minute sync runs too
    function p:clearVariable() end
    return p
end
local function car(script, x, y)
    local v = H.vehicle({ script = script, x = x, y = y })
    v.seats = {}
    function v:getSeat(p) return self.seats[p] or -1 end
    function v:getPassengerWorldPos(seat, out) return out:set(self.x + 0.5 + seat, self.y - 0.25 * seat, 0.3) end
    return v
end
local function sit(p, v, seat)
    if p.vehicle then p.vehicle.seats[p] = nil end
    p.vehicle = v
    if v then
        v.seats[p] = seat
        p.x, p.y, p.z = v.x, v.y, v.z -- where the engine's own update leaves a remote passenger: the car centre
    end
end
local a, b, me = rider("a"), rider("b"), rider("me", true)
local byId = { [a.oid] = a, [b.oid] = b, [me.oid] = me }
function getPlayerByOnlineID(id) return byId[id] end
local tesla, van = car("Base.MinidoracatTesla_Cybertruck", 200.5, 300.5), car("Base.CarNormal", 220.5, 300.5)
H.side(true, false)

local ticks = H.count("OnTick")
T.ClientCommands.seat({ id = a.oid })
check(R.count() == 1 and H.count("OnTick") == ticks + 1, "relay: a watched, one OnTick added")
H.fire("OnTick")
check(a.x == 100 and a.y == 100, "relay ahead of their vehicle packet: not in a car yet, left alone")
sit(a, tesla, 1)
H.fire("OnTick")
check(a.x == 202 and a.y == 300.25 and a.z == 0.3, "in the Tesla's front passenger seat: put on the seat's world position")
sit(a, tesla, 1)
H.advanceMs(R.GRACE_MS * 10)
H.fire("OnTick")
check(a.x == 202 and a.y == 300.25 and R.count() == 1, "every frame while seated, past the grace time too")
sit(a, tesla, 3)
H.fire("OnTick")
check(a.x == 204 and a.y == 299.75, "switched to a rear seat: that seat")

T.ClientCommands.seat({ id = b.oid })
sit(b, tesla, 0)
check(R.count() == 2 and H.count("OnTick") == ticks + 1, "a second passenger: still one OnTick")
T.ClientCommands.seat({ id = b.oid })
check(R.count() == 2, "the relay again (1 s later): not watched twice")
H.fire("OnTick")
check(b.x == 200.5 + 0.5 and b.y == 300.5, "both put on their seats")

sit(a, van, 0)
T.ClientCommands.seat({ id = a.oid }) -- the relay of a's exit
H.fire("OnTick")
check(a.x == van.x and R.count() == 2, "a in a vanilla car: left at the car centre, still watched within the grace time")
H.advanceMs(R.GRACE_MS + 1)
H.fire("OnTick")
check(R.count() == 1 and H.count("OnTick") == ticks + 1, "past the grace time: a dropped, b stays")
byId[b.oid] = nil -- b gone from this client (logged out, no relay)
local removes = R.stats.tickRemoves
H.fire("OnTick")
check(R.count() == 0 and H.count("OnTick") == ticks and R.stats.tickRemoves == removes + 1,
    "b not found here, its last relay's grace time over: dropped, nobody watched, the OnTick removed")
byId[b.oid] = b

T.ClientCommands.seat({ id = "7" })
T.ClientCommands.seat({})
check(R.count() == 0 and H.count("OnTick") == ticks, "an id that is not a number: nothing watched")

-- the game minute: every remote player in a Tesla, on an MP client only
sit(a, tesla, 2)
sit(b, van, 0)
sit(me, tesla, 0)
local online = { a, b, me }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
H.side(false, true)
H.fire("EveryOneMinute")
H.side(false, false)
H.fire("EveryOneMinute")
check(R.count() == 0, "every minute: nothing on a server or in SP")
H.side(true, false)
H.fire("EveryOneMinute")
check(R.count() == 1 and H.count("OnTick") == ticks + 1, "every minute (MP client): the remote player in a Tesla only "
    .. "(not one in a vanilla car, not the local player)")
H.fire("OnTick")
check(a.x == 203 and a.y == 300, "and put on the seat")
sit(a, nil)
H.advanceMs(R.GRACE_MS + 1)
H.fire("OnTick")
check(R.count() == 0 and H.count("OnTick") == ticks, "got out: dropped after the grace time, the OnTick removed")
-- the clock set back while someone out of a Tesla is within the grace time: dropped on the next frame, not once the
-- clock catches up (AGENTS.md rule 2: the OnTick only while someone is watched)
T.ClientCommands.seat({ id = a.oid })
check(R.count() == 1 and H.count("OnTick") == ticks + 1, "a watched again (a relay), out of any car")
H.advanceMs(-3600 * 1000)
H.fire("OnTick")
check(R.count() == 0 and H.count("OnTick") == ticks, "the clock set back an hour: dropped at once, the OnTick removed")
H.advanceMs(3600 * 1000)
check(R.stats.tickAdds == R.stats.tickRemoves, "every OnTick added was removed (" .. R.stats.tickAdds .. ")")

H.side(false, false)
Vector3f, getPlayerByOnlineID, getOnlinePlayers = saved.Vector3f, saved.byId, saved.online
