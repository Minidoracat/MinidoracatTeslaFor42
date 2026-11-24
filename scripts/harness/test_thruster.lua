-- Thrusters (Roadster Rocket; shared/server/client Thruster.lua): the server approves and bills the air tank, refills
-- it from the pack (never under the 12V floor off a charger; a refusal changes nothing), and judges every end itself
-- (MP): off the ground by the floor under the car (H.groundZ, a flat roof counts), seen by its own looks every 500 ms
-- from approval (a boost: speed up), never a read between them; the air back only if no look saw it go; a flight
-- billed by the server's clock from the look that saw it up, less the landing (LAND_FLAT_S), whatever the client
-- says; an end said in the air hands the car on. Every action has its asker's number n: an end for another n is
-- ignored. No watchdog: due checks on a one-shot timer (gone after) on a clock that never goes back or jumps (wall
-- clock set back or forward), only for the very car approved (ids are reused) - D2 hands a car left in the air to the
-- nearest player who has not had it (thrustLand), or leaves it to the first who comes near (anyone, then: tried is
-- forgotten); D3 still up: the next one; a helper who can't says so at once; an orphan whose car unloads is dropped.
-- A stale busy flag clears on load. SP: the client's word within the server's clock, and a pause runs no due check.
-- The phone app's show: its checks, again before each start try and before the physics goes; the motor started (3
-- tries), the caller's machine given the physics, never off the ground in the looks' window: the air back. The
-- client: refusals of an ask it has not had answered, an answer for another n, a refusal stopping the soft landing
-- it started first, the driver's roll-up on the motor's cruise, the show's on the thrusters after a lift within the
-- floor (setDebugZ clamps like the engine), a flight's limit in real time (a pause not counted), the camera zoomed
-- back however often it zoomed out, aborts said as such, a helper who can't says so. The flying itself: real-game E2E
-- (thruster-sp / thruster-mp). Tested on the Model S with `thruster = {}` put in its Specs here only.
local check, near = H.check, H.near
local T = MinidoracatTesla
local B = T.Battery
local MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"
local cmds = T.ServerCommands

H.section("thrusters: server")
H.side(false, true)
-- the world: open ground (level 0) everywhere but where gone["x,y"] (that cell not loaded); a flat roof at level
-- roof["x,y"]
local roof, gone = {}, {}
local solid = { getFloor = function() return true end, TreatAsSolidFloor = function() return true end }
local saved = { addSound = addSound, getOnlinePlayers = getOnlinePlayers, fx = T.ThrusterFx, sandbox = {},
    getCell = getCell, vmRefusal = T.vmRefusal, byId = getPlayerByOnlineID, player = H.player }
function getCell()
    return { getGridSquare = function(_, x, y, z)
        local k = x .. "," .. y
        if z == 0 then return not gone[k] and solid or nil end
        return roof[k] == z and solid or nil
    end }
end
H.require("MinidoracatTesla/Thruster") -- shared
assert(loadfile(MEDIA .. "/server/MinidoracatTesla/Thruster.lua"))()
local TH = T.Thruster

local OPTS = { "Thrusters", "FlightSeconds", "FreeFlight", "ThrusterRefillMinutes", "ThrusterRefillKwh" }
for _, k in ipairs(OPTS) do saved.sandbox[k] = SandboxVars.MinidoracatTesla[k] end
local sounds, fxs, online = {}, {}, {}
function addSound(src, x, y, z, r, vol) sounds[#sounds + 1] = { src = src, r = r, vol = vol } end
T.ThrusterFx = { set = function(v, mode) fxs[#fxs + 1] = mode or "off" end }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
-- the server's IsoPlayer by online id: the newest player made with that id who has not left (left[q]: disconnected,
-- its object kept; the slot may go to a new connection, GameServer.java:2696-2726)
local made, left = {}, {}
function H.player(o) local q = saved.player(o) made[#made + 1] = q return q end
function getPlayerByOnlineID(id)
    for i = #made, 1, -1 do if not left[made[i]] and made[i]:getOnlineID() == id then return made[i] end end
end
-- the timer the server adds: captured to run it frame by frame without firing every module's OnTick
local onTick, tickAdd, tickRemove = Events.OnTick, Events.OnTick.Add, Events.OnTick.Remove
local timer, hooked = nil, false
onTick.Add = function(fn) timer, hooked = fn, true; tickAdd(fn) end
onTick.Remove = function(fn) if fn == timer then hooked = false end; tickRemove(fn) end
-- ms of real time in frames of at most 250 ms (what the server's clock takes a frame), its timer run each frame
local function wait(ms)
    while ms > 0 do
        local d = math.min(250, ms)
        H.advanceMs(d)
        ms = ms - d
        if hooked then timer() end
    end
end

local published = 0
for name, s in pairs(T.Specs) do if s.thruster ~= nil and name:find("_Roadster2", 1, true) == nil then published = published + 1 end end
local MS = T.Specs["Base.MinidoracatTesla_ModelS"]
check(published == 0, "no published car has thrusters (only the new Roadster's Specs may)")

local function car(o)
    o = o or {}
    local v = H.vehicle({ script = "Base.MinidoracatTesla_ModelS", running = o.running ~= false, noPack = o.noPack,
        x = o.x, y = o.y })
    local part = v:getPartById("GasTank")
    if part:getInventoryItem() then part:setContainerContentAmount(B.capacity(part) * (o.pct or 80) / 100) end
    v.reads = 0 -- the car's height and speed read: by a look, never by a frame between them
    function v:getVehicleTowing() return self.towing end
    function v:getDebugZ() self.reads = self.reads + 1 return self.dz or 0 end
    function v:getCurrentSpeedKmHour() self.reads = self.reads + 1 return self.speed end
    function v:authorizationChanged(q) self.npid = q and q:getOnlineID() or -1 end
    -- the motor: started at once (startsOk), or starting (startsSlow) until engineSettles runs it on into Running as the
    -- engine does by itself (VehicleEngine.java:202-212)
    function v:tryStartEngine()
        self.starts = (self.starts or 0) + 1
        if self.startsSlow then self.starting = true elseif self.startsOk then self.running = true end
    end
    function v:isEngineStarted() return self.starting == true end
    function v:engineSettles() if self.starting then self.starting, self.running = false, true end end
    function v:engineDoShuttingDown() self.running, self.starting, self.shut = false, false, (self.shut or 0) + 1 end
    local p = H.player({ name = "pilot" .. v.id, x = v.x, y = v.y })
    v.driver, p.vehicle = p, v
    return v, p, part
end
local function last() return H.sent[#H.sent] end
local N = 0
-- n: the action's number (false: none sent); returns the deny reason or the command, and its args
local function ask(p, v, act, n)
    if n == nil then N = N + 1; n = N end
    local c = #H.sent
    cmds.thrust(p, { vid = v:getId(), act = act, n = n or nil })
    local s = H.sent[#H.sent]
    if #H.sent == c then return nil end
    return s.command == "deny" and s.args.reason or s.command, s.args
end
-- a soft landing naming the unanswered ask it takes over (S3: client H.ask sends over = that ask's n)
local function askLand(p, v, over)
    N = N + 1
    local c = #H.sent
    cmds.thrust(p, { vid = v:getId(), act = "land", n = N, over = over })
    if #H.sent == c then return nil end
    local s = H.sent[#H.sent]
    return s.command == "deny" and s.args.reason or s.command, s.args
end
local function entryOf(v) return TH.pending[v:getId()] end
-- thrustEnd from pl with the action's own n (and a helper's hand-over term) unless a.n / a.term say otherwise
local function done(pl, v, a)
    a = a or {}
    a.vid = v:getId()
    if a.n == nil then a.n = entryOf(v) and entryOf(v).n end
    if a.term == nil then a.term = entryOf(v) and entryOf(v).term end
    cmds.thrustEnd(pl, a)
end
local function gas(part) return part:getModData().thr.gas end
-- what a refusal must leave as it was: the tank, its clock and flag, the pack, what was sent
local function snap(v, part)
    local thr = part:getModData().thr
    if type(thr) ~= "table" then return "none|" .. B.kwh(part) .. "|" .. v.transmits end
    return table.concat({ tostring(thr.gas), tostring(thr.at), tostring(thr.busy), tostring(B.kwh(part)),
        tostring(v.transmits) }, "|")
end

local v, p, part = car()
local s0 = snap(v, part)
check(ask(p, v, "kickflip") == "THRUST_NONE" and part:getModData().thr == nil and snap(v, part) == s0,
    "B1: a car without Specs `thruster`: THRUST_NONE, no tank made, nothing billed or sent")
MS.thruster = {}
check(TH.conf(v).apex == 8 and TH.conf(v).inertia.f == 0.387, "Specs thruster = {}: every value its default")
MS.thruster = { inertia = { f = 0.5 } }
check(TH.conf(v).inertia.f == 0.5 and TH.conf(v).inertia.r == 1.816, "inertia given in part: the rest its default, not nil")
MS.thruster = {}
MinidoracatAutoDriveAPI = { summonInfo = function(c) return c == v end }
check(ask(p, v, "boost") == "THRUST_BUSY", "AutoDrive summons it: THRUST_BUSY")
MinidoracatAutoDriveAPI = nil
check(ask(p, v, "warp") == "BAD_VALUE", "an unknown action: BAD_VALUE")
SandboxVars.MinidoracatTesla.Thrusters = false
check(ask(p, v, "kickflip") == "THRUST_OFF", "sandbox Thrusters off: THRUST_OFF")
SandboxVars.MinidoracatTesla.Thrusters = true
v.running = false
check(ask(p, v, "kickflip") == "THRUST_ENGINE", "engine off: THRUST_ENGINE")
v.running = true
-- half a tank due to refill (15 of 30 minutes): a refusal books none of it
part:getModData().thr = { gas = 0.5, at = H.hours() - 0.25 }
s0 = snap(v, part)
local q = H.player({ name = "passenger", x = v.x, y = v.y })
q.vehicle = v
check(ask(q, v, "kickflip") == "NOT_DRIVER" and snap(v, part) == s0,
    "B1: a passenger: NOT_DRIVER, the tank's refill not booked, nothing drawn or sent")
local what, args = ask(p, v, "boost", false)
check(what == "BAD_VALUE" and args.n == nil and snap(v, part) == s0 and entryOf(v) == nil,
    "D3: thrust without n: BAD_VALUE, nothing changed")
v.towing = H.vehicle()
check(ask(p, v, "boost") == "TOWED", "towing: TOWED")
v.towing = nil
part:getModData().chg = { power = "grid" }
check(ask(p, v, "boost") == "CABLE_PLUGGED", "a charge cable in: CABLE_PLUGGED")
part:getModData().chg = nil
local nv, np = car({ noPack = true })
check(ask(np, nv, "boost") == "NO_PACK", "no pack: NO_PACK")
part:getModData().thr = { gas = 1, at = H.hours() }

local tx, ns = v.transmits, #sounds
what, args = ask(p, v, "kickflip", 41)
local thr = part:getModData().thr
check(what == "thrustOk" and args.vid == v:getId() and args.act == "kickflip" and args.sec == nil and args.n == 41
    and args.pn == p:getPlayerNum(), "kickflip approved: thrustOk to the driver with its n and split-screen slot")
check(near(thr.gas, 0) and thr.busy and thr.busy.act == "kickflip" and thr.busy.by == p.name and v.transmits == tx + 1,
    "a full tank spent, busy with who asked, sent to the clients")
check(#sounds == ns + 1 and sounds[#sounds].r == 150 and sounds[#sounds].vol == 150 and fxs[#fxs] == "flip",
    "heard like the horn (150/150); the flip flames on")
check(entryOf(v) and hooked, "pending, with its timer")
-- during the action: hours pass, a second ask is refused without the refill booked
H.setHours(H.hours() + 0.25)
s0 = snap(v, part)
check(ask(p, v, "boost") == "THRUST_BUSY" and snap(v, part) == s0, "B1: a second action meanwhile: THRUST_BUSY, no refill booked")
done(q, v, { done = true })
check(thr.busy ~= nil and entryOf(v), "thrustEnd from anyone but who flies it: ignored")
done(p, v, { done = true, n = 40 })
check(thr.busy ~= nil and entryOf(v), "D3: thrustEnd with another n (a late one of the last action): ignored")
-- A2: the looks, every 500 ms; frames between read nothing
v.reads = 0
wait(250)
check(v.reads == 0, "A2: a frame with no look due reads neither height nor speed")
wait(250)
local reads1 = v.reads
check(reads1 > 0 and not entryOf(v).up, "A2: the look at 500 ms reads the car (on the ground: not up)")
wait(100)
v.dz = 1
wait(150)
check(v.reads == reads1 and not entryOf(v).up, "A2: up since 600 ms, unseen until the next look")
wait(250)
local pe = entryOf(v)
check(pe.up and pe.upMs - pe.ms == 1000, "A2: the 1000 ms look sees it up")
v.reads = 0
wait(2000)
check(v.reads == 0, "A2: seen: no more looks, only D2's due time")
v.dz = 0
done(p, v, { done = false })
check(thr.busy == nil and entryOf(v) == nil and near(thr.gas, 0) and fxs[#fxs] == "land",
    "down: billed though the client says not done (a look saw it up); the touchdown mist")
wait(250)
check(not hooked, "nothing due: the timer gone the next frame")
check(ask(p, v, "kickflip") == "THRUST_NO_AIR", "an empty tank: THRUST_NO_AIR")

H.section("thrusters: refill from the pack")
local kwh0 = B.kwh(part)
thr.at = H.hours()
H.setHours(H.hours() + 15 / 60) -- half of 30 refill minutes
local _, cut = TH.settle(v, part)
check(near(gas(part), 0.5, 1e-6) and near(kwh0 - B.kwh(part), 20, 1e-6) and cut == false,
    "half the refill time: half a tank for half of 40 kWh; the clients' estimate agrees (no send of its own)")
check(near(TH.gasNow(part:getModData().thr, H.hours() + 1), 1) and TH.minutesToFull(0.5) == 15, "estimate and minutes to full")
what = ask(p, v, "boost")
check(what == "thrustOk" and near(gas(part), 0.5 - 1 / 3, 1e-6), "boost takes a third")
done(p, v, { done = true })
check(near(gas(part), 0.5, 1e-6) and fxs[#fxs] == "off" and entryOf(v) == nil,
    "a boost the server never saw speed up: the air back at once though the client says done")
ask(p, v, "boost")
v.speed = 30
done(p, v, { done = true })
check(near(gas(part), 0.5 - 1 / 3, 1e-6) and entryOf(v) == nil, "a boost sped up 30 km/h by its end: billed (the end's look)")
v.speed = 0
-- off a charger the pack never goes under the 12V floor for the tank
part:getModData().thr.gas = 0
local cap = B.capacity(part)
part:setContainerContentAmount(cap * 0.06)
H.setHours(H.hours() + 1)
_, cut = TH.settle(v, part)
check(near(B.pct(part), T.DCDC_MIN_PCT, 1e-6) and near(gas(part), cap * 0.01 / 40, 1e-6) and cut == true,
    "6 % pack: only down to " .. T.DCDC_MIN_PCT .. " %, the tank gets what that paid; flagged to send (the estimate was wrong)")
H.setHours(H.hours() + 1)
tx = v.transmits
TH.onUpdate(v, part)
check(v.transmits == tx + 1 and near(B.pct(part), T.DCDC_MIN_PCT, 1e-6), "the parts update sends a cut refill")
part:setContainerContentAmount(cap * 0.8)
-- S4: plugged on the grid the pack still pays the refill (the charge pays it back: Charging.lua C.settle settles the
-- air first); the charger's books (chg.fed) untouched
part:getModData().thr = { gas = 0.5, at = H.hours() }
part:getModData().chg = { power = "grid", fed = 1.5 }
local k1 = B.kwh(part)
H.setHours(H.hours() + 0.25)
TH.settle(v, part)
check(near(gas(part), 1, 1e-6) and near(k1 - B.kwh(part), 20, 1e-6) and part:getModData().chg.fed == 1.5,
    "S4: on the grid 15 refill minutes: the pack pays (20 kWh), chg.fed untouched: " .. string.format("%.4f", k1 - B.kwh(part)))
-- S4: the pack at its 12V floor, plugged in: no refill this time, the tank as it was, its clock moved on (that stretch
-- is not refilled: the client's estimate from gas + at stays true)
part:getModData().thr = { gas = 0.5, at = H.hours() }
part:setContainerContentAmount(cap * T.DCDC_MIN_PCT / 100)
H.setHours(H.hours() + 0.25)
_, cut = TH.settle(v, part)
check(near(gas(part), 0.5, 1e-6) and part:getModData().thr.at == H.hours() and near(B.pct(part), T.DCDC_MIN_PCT, 1e-6) and cut == true,
    "S4: the pack at its floor, plugged in: nothing refilled, the tank's clock moved on, flagged to send")
part:setContainerContentAmount(cap * 0.8)
part:getModData().chg = nil

H.section("thrusters: flying (MP billed by the server's clock)")
local FLAT = TH.LAND_FLAT_S * 1000
part:getModData().thr.gas = 1
SandboxVars.MinidoracatTesla.FlightSeconds = 8
-- the same server timeline twice: up at the 500 ms look, down 3 s + LAND_FLAT_S later; what the client says differs
local function flight(sec)
    part:getModData().thr = { gas = 1, at = H.hours() }
    local w, a = ask(p, v, "fly")
    v.dz = 1
    wait(500)
    wait(3000 + FLAT)
    v.dz = 0
    done(p, v, { done = true, sec = sec })
    return w, a
end
what, args = flight(100)
check(what == "thrustOk" and near(args.sec, 8) and near(gas(part), 1 - 3 / 8, 1e-6),
    "A3: fly approved with 8 s of air; up 3 s + the landing: billed 3 s, the client's 100 s not taken")
flight(0)
check(near(gas(part), 1 - 3 / 8, 1e-6), "A3: the same flight said as 0 s: the same bill (no flying free under 8 s)")
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
v.dz = 1
wait(500)
wait(20000)
v.dz = 0
done(p, v, { done = true, sec = 1 })
check(near(gas(part), 0), "A3: 20 s up: billed the 8 s approved, never more")
-- G1: D2 for a flight: 3 s + its seconds + 12 s + 5 s from approval
local helper = H.player({ name = "near", x = v.x + 5, y = v.y })
online = { helper }
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
v.dz = 1
wait(27750)
check(entryOf(v) and entryOf(v).helper == nil, "G1: an 8 s flight not handed on before 3 + 8 + 12 + 5 s")
wait(250)
check(entryOf(v).helper == helper and last().command == "thrustLand", "G1: at 28 s, still up: handed on")
v.dz = 0
done(helper, v, { done = true })
v.npid = nil
-- E3: each parts update in flight renews the noise and the jets (a client that came near since starts its hiss)
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
local nf
ns, nf = #sounds, #fxs
TH.onUpdate(v, part)
check(#sounds == ns + 1 and #fxs == nf + 1 and fxs[#fxs] == "lift", "E3: a parts update in flight: the noise and the jets again")
done(p, v, { done = false })
part:getModData().thr.gas = 0.1
check(ask(p, v, "fly") == "THRUST_NO_AIR", "under one second of air: THRUST_NO_AIR")
SandboxVars.MinidoracatTesla.FreeFlight = true
what, args = ask(p, v, "fly")
check(what == "thrustOk" and args.sec == nil and hooked, "FreeFlight: no limit; the looks still run")
v.dz = 1
wait(500)
check(entryOf(v).up and not hooked, "F1: FreeFlight seen up: no D2, the timer gone")
v.dz = 0
done(p, v, { done = true, sec = 50 })
check(near(gas(part), 0.1) and fxs[#fxs] == "land", "F1: FreeFlight down: flying costs nothing, the touchdown mist")
ask(p, v, "fly")
wait(4500)
check(not hooked and entryOf(v), "FreeFlight never up: the looks over, waiting for its end")
v.driver = nil
TH.onUpdate(v, part)
check(entryOf(v) == nil and part:getModData().thr.busy == nil, "FreeFlight: driver gone, ended at the next parts update")
v.driver = p
SandboxVars.MinidoracatTesla.FreeFlight = false
v.dz = 1
what = ask(p, v, "land")
check(what == "thrustOk" and near(gas(part), 0) and entryOf(v).up and not hooked == false,
    "the soft landing is never refused for air (takes what is left); a falling car is up at once")
v.dz = 0
done(p, v, { done = true })
check(entryOf(v) == nil and near(gas(part), 0), "landed: billed")

H.section("thrusters: off the ground over a roof (A1)")
roof["300,300"] = 1
local rv, rp, rpart = car({ x = 300.5, y = 300.5 })
rpart:getModData().thr = { gas = 1, at = H.hours() }
local bystander = H.player({ name = "bystander", x = 303, y = 300 })
online = { bystander }
ask(rp, rv, "fly")
rv.dz = 0.8 -- up from the ground beside the house
wait(500)
check(entryOf(rv).up, "A1: up 0.8 floor over the ground: seen")
wait(3000 + FLAT)
rv.dz = 1.075 -- set down on the flat roof, one floor up
local sent0 = #H.sent
done(rp, rv, { done = true })
local handed = false
for i = sent0 + 1, #H.sent do if H.sent[i].command == "thrustLand" then handed = true end end
check(entryOf(rv) == nil and rpart:getModData().thr.busy == nil and not handed and gas(rpart) < 1,
    "A1: ground to a roof: on the roof is down - over, busy cleared, billed, nobody handed it")
rpart:getModData().thr = { gas = 1, at = H.hours() }
ask(rp, rv, "kickflip") -- off the roof
rv.x, rv.dz = 301.5, 0.9 -- past its edge, hanging lower than it left, nothing under it but the ground
wait(24800)
check(entryOf(rv) and entryOf(rv).helper == bystander, "A1: hanging below the roof it left, over open ground: up, handed on at D2")
rv.dz = 0.075
done(bystander, rv, { done = true })
check(entryOf(rv) == nil, "... down on the ground: over")

H.section("thrusters: the clock (A4)")
online = { helper }
-- the wall clock set back an hour mid-flight: no negative time, no early or late D2
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
v.dz = 1
wait(500)
H.advanceMs(-3600000)
timer()
v.dz = 0
done(p, v, { done = true })
check(gas(part) <= 1 and near(gas(part), 1), "A4: the wall clock an hour back, down at once: no time flown, nothing given back")
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "kickflip")
v.dz = 1
wait(500)
H.advanceMs(-3600000)
timer() -- that frame: 0 ms
wait(24050)
check(entryOf(v).helper == nil, "A4: an hour back: D2 not before its 24.8 s")
wait(250)
check(entryOf(v).helper == helper, "A4: an hour back: D2 on its time")
v.dz = 0
done(helper, v, { done = true })
v.npid = nil
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "kickflip")
v.dz = 1
wait(500)
H.advanceMs(3600000)
timer() -- that frame: 250 ms
check(entryOf(v).helper == nil, "A4: the wall clock an hour forward: no D2 yet")
wait(24050)
check(entryOf(v).helper == helper, "A4: an hour forward: D2 one frame early at most (24.55 s of 24.8 counted + the jump's 250 ms)")
v.dz = 0
done(helper, v, { done = true })
v.npid = nil

H.section("thrusters: due checks (D2, D3)")
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "kickflip")
local helper2 = H.player({ name = "near2", x = v.x + 8, y = v.y })
local far = H.player({ name = "far", x = v.x + 100, y = v.y })
online = { far, p, helper, helper2 }
wait(24750)
check(entryOf(v) and entryOf(v).helper == nil,
    "before D2 (roll-up 3 s + profile 3.8 s + off it 4 s + landing 12 s + 2 s): still pending")
v.dz = 1 -- up at D2 (no look saw it before)
wait(250)
pe = entryOf(v)
check(pe and pe.helper == helper and v.npid == helper:getOnlineID() and last().command == "thrustLand"
    and last().player == helper and last().args.pn == helper:getPlayerNum() and last().args.n == pe.n,
    "D2, still up: the nearest other player (not the driver, not 100 tiles off) lands it, told its slot and the n")
done(p, v, { done = true })
check(entryOf(v) ~= nil and pe.helper == helper, "the driver's late thrustEnd: ignored, the helper has it")
done(helper, v, { done = true, n = pe.n + 1 })
check(entryOf(v) ~= nil and pe.helper == helper, "D3: the helper's thrustEnd with another n: ignored")
wait(14750)
check(pe.helper == helper, "D3 not before the helper's 2 s wait + 12 s landing + 1 s")
wait(250)
check(pe.helper == helper2 and pe.tried[helper] and last().command == "thrustLand" and last().player == helper2,
    "D3 still up: that helper could not; the next nearest who has not had it")
done(helper2, v, { act = "land", done = false, abort = true })
wait(500)
check(pe.orphan and part:getModData().thr.busy.orphan and v.npid == -1 and pe.helper == nil and next(pe.tried) == nil,
    "the next one can't either (said at once): nobody near who has not had it, the server holds it; tried forgotten")
-- C2 + busy: the first helper flying a car of its own: not handed the orphan (its machine refuses, and the car falls
-- while it holds the physics: r2fix-mp-c, 6.79 m in 15 s); its flight over, the next adopt hands it over
local bv = car({ x = v.x + 8, y = v.y })
bv.driver, helper.vehicle = helper, bv
online = { far } -- the request's own adopt: nobody near yet
local bw = ask(helper, bv, "fly")
check(bw == "thrustOk" and entryOf(bv) and entryOf(bv).player == helper and pe.helper == nil,
    "C2 busy: the helper flies its own car")
online = { far, helper } -- the driver gone (off the seat); the second helper gone too
v.driver = nil
local auths, authOf = 0, v.authorizationChanged
function v:authorizationChanged(q) auths = auths + 1 return authOf(self, q) end
TH.onUpdate(v, part)
TH.adopt()
check(pe.orphan and pe.helper == nil and v.npid == -1 and auths == 0,
    "C2 busy: a helper flying its own car is not handed the orphan, its physics never given")
bv.dz = 0
done(helper, bv, { done = true, sec = 1 })
wait(500)
check(entryOf(bv) == nil, "C2 busy: the helper's own flight over")
TH.onUpdate(v, part)
check(pe.helper == helper and v.npid == helper:getOnlineID() and auths == 1, "C2: who could not before, free now: theirs to land")
v.authorizationChanged = authOf
v.dz = 0
done(helper, v, { done = true })
check(entryOf(v) == nil and part:getModData().thr.busy == nil and near(gas(part), 0) and v.npid == -1,
    "down: over, billed; the physics back to the server")
v.npid, v.driver = nil, p
-- C1: an orphan whose car unloads (its id not reused) is dropped
part:getModData().thr = { gas = 1, at = H.hours() }
online = {}
ask(p, v, "kickflip")
v.dz = 1
wait(24800)
check(entryOf(v).orphan, "C1: up at D2, nobody near: an orphan")
H.removeVehicle(v)
TH.adopt()
check(TH.pending[v:getId()] == nil, "C1: its car unloaded: the entry dropped")
H.addVehicle(v)
TH.onLoad(v)
check(part:getModData().thr.busy == nil, "... loaded again: its stale busy flag cleared")
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "kickflip")
wait(24800)
gone["100,100"] = true
TH.adopt()
check(TH.pending[v:getId()] == nil, "C1: the ground under it gone (its cell unloaded): the entry dropped")
gone["100,100"] = nil
TH.onLoad(v)
v.dz, v.npid = 0, nil
online = { far, p, helper, helper2 }
-- never seen up by D2: the air back
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "backflip")
wait(23800)
check(entryOf(v) == nil and near(gas(part), 1), "D2 on the ground, never seen up: over, the air back")
-- the late thrustEnd of the last action does not end the next
ask(p, v, "boost", 90)
done(p, v, { done = true })
ask(p, v, "boost", 91)
done(p, v, { done = true, n = 90 })
check(entryOf(v) and entryOf(v).n == 91, "D3: the last action's late thrustEnd (n 90): the next one (n 91) goes on")
done(p, v, { done = true })
-- the id reused by another car before a due check: that car is never touched
ask(p, v, "kickflip")
H.removeVehicle(v)
local v2 = H.vehicle({ id = v:getId(), script = "Base.MinidoracatTesla_ModelS" })
function v2:authorizationChanged() self.touched = true end
wait(30000)
check(TH.pending[v:getId()] == nil and not v2.touched and v2.transmits == 0, "its id now another car's: the entry dropped, that car untouched")
H.addVehicle(v)
-- the stale busy flag left behind: cleared when the car loads, the motor the server started off
part:getModData().thr.busy.eng = true
v.driver, v.running, v.shut = nil, true, 0
tx = v.transmits
TH.onLoad(v)
check(part:getModData().thr.busy == nil and v.shut == 1 and v.transmits == tx + 1, "loaded with a stale busy flag: cleared, its motor off")
v.driver, v.running = p, true
-- a busy flag with no pending entry (the server restarted mid-action): cleared on the next request too
part:getModData().thr = { gas = 1, at = H.hours(), busy = { act = "fly", by = "x", t = 0 } }
check(ask(p, v, "boost") == "thrustOk", "a stale busy flag (server restart) does not lock the car")
done(p, v, { done = true })

H.section("thrusters: the phone app's show")
local function show(pl, act, n)
    local c = #H.sent
    if n == nil then N = N + 1; n = N end
    local why = TH.appShow(pl, v, act, 7, n or nil)
    return why, #H.sent > c and last() or nil
end
local caller = H.player({ name = "caller", x = v.x + 10, y = v.y })
-- the phone's hold (Remote.lua R.appLink): link.why refuses, link.key the key it was asked about
saved.appLink = T.Remote and T.Remote.appLink
T.Remote = T.Remote or {}
local link = {}
T.Remote.appLink = function(_, _, key) link.key = key return link.why end
online = { caller, helper }
part:getModData().thr = { gas = 1, at = H.hours() }
check(show(caller, "fly") == "THRUST_NONE", "only kickflip and backflip are shows")
check(show(p, "kickflip") == "NOT_OUTSIDE", "the caller in a car: NOT_OUTSIDE")
check(show(caller, "kickflip") == "OCCUPIED", "someone in the driver's seat: OCCUPIED")
v.driver, p.vehicle = nil, nil
s0 = snap(v, part)
check(show(caller, "kickflip", false) == "BAD_VALUE" and snap(v, part) == s0, "D3: a show without n: BAD_VALUE, nothing changed")
local away = H.player({ name = "away", x = v.x + 31, y = v.y })
check(show(away, "kickflip") == "TOO_FAR", "over 30 tiles off: TOO_FAR")
v.npid = 99
check(show(caller, "kickflip") == "THRUST_BUSY", "another machine holds the car: THRUST_BUSY")
v.npid = nil
v.running, v.startsOk, v.dz, v.shut = false, false, 0, 0
local why, s = show(caller, "kickflip")
check(why == nil and s == nil and v.starts == 1 and near(gas(part), 0) and part:getModData().thr.busy.app
    and part:getModData().thr.busy.eng, "motor off: billed, busy (app, eng), the motor asked to start")
wait(2000)
wait(2000)
check(v.starts == 3 and entryOf(v) ~= nil, "not started: tried again every 2 s")
wait(2000)
check(entryOf(v) == nil and near(gas(part), 1) and last().command == "appDone" and last().args.why == "CANT_START"
    and last().args.key == 7 and v:getNetPlayerId() == -1, "3 tries: the air back, CANT_START to the caller's app")
-- B2: the show's checks again before the physics goes (the motor started meanwhile)
local function startedThen(change, undo)
    v.startsOk, v.starts, v.shut, v.running = true, 0, 0, false
    part:getModData().thr = { gas = 1, at = H.hours() }
    local c = #H.sent
    show(caller, "kickflip")
    change()
    wait(2000)
    local got = {}
    for i = c + 1, #H.sent do got[#got + 1] = H.sent[i] end
    undo()
    return got
end
local function noPhysics(got, reason)
    local told = got[#got]
    local flown = false
    for _, x in ipairs(got) do if x.command == "thrustOk" then flown = true end end
    return not flown and entryOf(v) == nil and near(gas(part), 1) and v.shut == 1 and v:getNetPlayerId() == -1
        and part:getModData().thr.busy == nil
        and (reason == nil and (told == nil or told.command ~= "appDone") or told.command == "appDone" and told.args.why == reason)
end
local got = startedThen(function() caller.x = v.x + 31 end, function() caller.x = v.x + 10 end)
check(noPhysics(got, "TOO_FAR"), "B2: the caller walked 31 tiles off while it started: no physics, the air back, motor off, TOO_FAR")
got = startedThen(function() T.vmRefusal = function() return "NOT_OWNER" end end, function() T.vmRefusal = saved.vmRefusal end)
check(noPhysics(got, "NOT_OWNER"), "B2: DRIVE taken away meanwhile: the same, NOT_OWNER")
got = startedThen(function() part:getModData().chg = { power = "grid" } end, function() part:getModData().chg = nil end)
check(noPhysics(got, "CABLE_PLUGGED"), "B2: a cable plugged in meanwhile: the same, CABLE_PLUGGED")
got = startedThen(function() online = { helper } end, function() online = { caller, helper } end)
check(noPhysics(got, nil), "B2: the caller gone offline meanwhile: the same, nobody told")
v.startsOk, v.starts, v.shut, v.running = true, 0, 0, false
part:getModData().thr = { gas = 1, at = H.hours() }
why = show(caller, "kickflip", 77)
wait(2000)
s = last()
check(why == nil and v.running and v.npid == caller:getOnlineID() and s.command == "thrustOk" and s.args.app
    and s.player == caller and s.args.pn == caller:getPlayerNum() and s.args.n == 77,
    "started: the caller's machine gets the physics and flies it (its n, its slot)")
wait(4250)
check(entryOf(v) ~= nil, "A2: the show's looks: not over before the approach's budget (3 s) + 1.5 s")
wait(250)
check(entryOf(v) == nil and near(gas(part), 1) and last().args.why == "THRUST_NO_LIFT" and v.npid == -1
    and v.shut == 1 and part:getModData().thr.busy == nil,
    "A2: never off the ground in the looks' window: the air back, the physics back, the motor the server started off")
show(caller, "backflip")
wait(2000)
v.dz = 1
wait(4500)
check(entryOf(v) ~= nil and entryOf(v).up, "seen up: carries on")
done(caller, v, { done = true })
wait(250)
check(entryOf(v) ~= nil and entryOf(v).helper == nil, "an end said in the air (claimed done): not taken")
wait(250)
check(entryOf(v).helper == helper and last().command == "thrustLand", "still up half a second later: the next one lands it")
v.dz = 0
done(helper, v, { done = false })
check(entryOf(v) == nil and near(gas(part), 0) and v.npid == -1 and not v.running,
    "down: billed (the server saw it up) though the helper says not done; physics and motor back as they were")
v.driver, p.vehicle, v.running, v.dz, v.npid = p, v, true, 0, nil

H.section("thrusters: review round 2")
v.driver, p.vehicle = nil, nil
-- R1: the phone's hold and the show's own busy flag again before the physics goes
got = startedThen(function() link.why = "NO_LINK" end, function() link.why = nil end)
check(noPhysics(got, "NO_LINK") and link.key == 7,
    "R1: past Bluetooth in a power cut while it started (still within 30 tiles): no physics, the air back, motor off, NO_LINK")
got = startedThen(function() link.why = "NO_PHONE_KEY" end, function() link.why = nil end)
check(noPhysics(got, "NO_PHONE_KEY"), "R1: the phone key handed away meanwhile: the same, NO_PHONE_KEY")
got = startedThen(function() part:getModData().thr.busy = nil end, function() end)
check(noPhysics(got, "THRUST_BUSY"), "R1: its busy flag cleared meanwhile: the same, THRUST_BUSY")
-- R2: called off while the motor is still starting: shut down, never runs on
v.startsSlow = true
got = startedThen(function() caller.x = v.x + 31 end, function() caller.x = v.x + 10 end)
v:engineSettles()
check(noPhysics(got, "TOO_FAR") and not v.running, "R2: called off while the motor is starting: shut down, it never runs")
part:getModData().thr = { gas = 1, at = H.hours(), busy = { act = "kickflip", eng = true } }
v.starting, v.running, v.shut = true, false, 0
TH.onLoad(v)
v:engineSettles()
check(v.shut == 1 and not v.running, "R2: a stale show's motor still starting on load: shut down, it never runs")
v.startsSlow = nil
v.driver, p.vehicle, v.running = p, v, true
-- R3: refused for the air the pack can pay only part of: nothing written
part:getModData().thr = { gas = 0, at = H.hours() - 1 } -- a full refill due
part:setContainerContentAmount(cap * 0.06)
s0 = snap(v, part)
check(ask(p, v, "kickflip") == "THRUST_NO_AIR" and snap(v, part) == s0,
    "R3: 6 % pack pays a sliver of the refill: THRUST_NO_AIR, the tank, its clock, the pack and the sends as they were")
part:setContainerContentAmount(cap * 0.8)
-- R4: the looks on the 500 ms grid from approval, the last at 4500 ms, with 60 ms frames
part:getModData().thr = { gas = 1, at = H.hours() }
local looksAt, t60 = {}, 0
local dzOf = v.getDebugZ
function v:getDebugZ() if looksAt[#looksAt] ~= t60 then looksAt[#looksAt + 1] = t60 end return dzOf(self) end
ask(p, v, "kickflip")
while t60 < 6000 do
    H.advanceMs(60)
    t60 = t60 + 60
    if hooked then timer() end
end
local onGrid = #looksAt == 9
for k, t in ipairs(looksAt) do if t < k * 500 or t >= k * 500 + 60 then onGrid = false end end
check(onGrid, "R4: 9 looks, each in the first 60 ms frame at or past 500 ms * k (the last at 4500): " .. table.concat(looksAt, ","))
v.getDebugZ = dzOf
done(p, v, { done = true })
-- R5: a machine whose other split-screen player flies a car of its own is no helper either
part:getModData().thr = { gas = 1, at = H.hours() }
online = {}
ask(p, v, "kickflip")
v.dz = 1
wait(24800)
pe = entryOf(v)
check(pe.orphan, "R5: up at D2, nobody near: an orphan")
local mate = H.player({ name = "mate", x = v.x + 5, y = v.y })
mate.oid = helper:getOnlineID() + 1 -- the helper's machine, its second player
B.part(bv):getModData().thr = { gas = 1, at = H.hours() }
bv.dz = 0
check(ask(helper, bv, "fly") == "thrustOk", "R5: the helper flies its own car")
online = { mate, helper }
TH.adopt()
check(pe.orphan and pe.helper == nil and v.npid == -1, "R5: the helper's split-screen mate is not handed the orphan")
done(helper, bv, { done = true, sec = 1 })
TH.adopt()
check(pe.helper == mate and pe.term ~= nil, "R5: the helper's flight over: the mate lands it")
-- R7: the same player handed it twice; the first hand-over's late end leaves the second's due time
online = { mate }
done(mate, v, { act = "land", done = false, abort = true })
wait(500)
check(pe.orphan, "R7: the mate could not (said at once): an orphan again, tried forgotten")
TH.adopt()
local term2 = pe.term
check(pe.helper == mate and term2 == 2 and last().command == "thrustLand" and last().args.term == 2,
    "R7: the mate again, its thrustLand with the hand-over's term 2")
done(mate, v, { act = "land", done = false, abort = true, term = 1 })
wait(1000)
check(pe.helper == mate and pe.term == 2 and not pe.orphan, "R7: the first hand-over's late end (term 1): ignored, D3 as it was")
v.dz = 0
done(mate, v, { done = true })
check(entryOf(v) == nil, "R7: the second hand-over's end: over")
v.npid = nil
-- S5: a player gone offline (its object kept, still the driver of a pending flight) holds nothing: a new connection
-- given its online id is a helper like any other
part:getModData().thr = { gas = 1, at = H.hours() }
online = {}
ask(p, v, "kickflip")
v.dz = 1
wait(24800)
pe = entryOf(v)
check(pe and pe.orphan, "S5: up at D2, nobody near: an orphan")
local ov, op, opart = car({ x = 500.5, y = 500.5 })
opart:getModData().thr = { gas = 1, at = H.hours() }
check(ask(op, ov, "fly") == "thrustOk", "S5: another car's flight")
left[op] = true
local newP = H.player({ name = "new5", x = v.x + 5, y = v.y })
newP.oid = op:getOnlineID()
online = { newP }
TH.adopt()
check(pe.helper == newP and v.npid == newP:getOnlineID(),
    "S5: its driver disconnected, a new connection given the same online id: handed the orphan (not held by the old object's flight)")
v.dz = 0
done(newP, v, { done = true })
done(op, ov, { done = true })
check(entryOf(v) == nil and entryOf(ov) == nil, "S5: both over")
left[op] = nil
v.npid = nil
-- R11: a boost off a roof's edge: over at its end, the driver keeps the car (no hand-over), busy cleared
rv.x, rv.y, rv.dz, rv.speed = 300.5, 300.5, 1.075, 0
rpart:getModData().thr = { gas = 1, at = H.hours() }
online = { bystander }
local rAuths, rAuthOf = 0, rv.authorizationChanged
function rv:authorizationChanged(q) rAuths = rAuths + 1 return rAuthOf(self, q) end
check(ask(rp, rv, "boost") == "thrustOk", "R11: a boost on a roof")
rv.x, rv.dz, rv.speed = 301.5, 0.9, 30 -- past its edge, falling
done(rp, rv, { done = true })
check(entryOf(rv) == nil and rpart:getModData().thr.busy == nil and rAuths == 0 and near(gas(rpart), 1 - 1 / 3, 1e-6),
    "R11: its end in the air: over now, busy cleared (the soft landing may ask), billed, the physics never moved")
rv.authorizationChanged = rAuthOf
-- a boost ended off an edge by its driver's machine: its thrustEnd and the soft landing (over = the boost's n) go out
-- the same frame and may arrive either way round (RELIABLE, unordered: PacketTypes.java:508)
local function boostOff(pushed)
    rv.x, rv.y, rv.dz, rv.speed = 300.5, 300.5, 1.075, 0
    rpart:getModData().thr = { gas = 1, at = H.hours() }
    local _, a = ask(rp, rv, "boost")
    rv.x, rv.dz, rv.speed = 301.5, 0.9, pushed and 30 or 0 -- past its edge, falling; no witness look yet
    return a and a.n
end
local nb = boostOff(true)
done(rp, rv, { act = "boost", done = true, n = nb })
check(askLand(rp, rv, nb) == "thrustOk" and entryOf(rv).act == "land" and near(gas(rpart), 1 / 3, 1e-6),
    "a boost off an edge, its end first: the boost billed, then the landing (naming it, now over) approved and billed")
rv.dz = 0.075
done(rp, rv, { done = true })
nb = boostOff(true)
local land1 = askLand(rp, rv, nb)
local nl = entryOf(rv) and entryOf(rv).n
check(land1 == "thrustOk" and entryOf(rv).act == "land" and near(gas(rpart), 1 / 3, 1e-6),
    "a boost off an edge, the landing first: the boost ended billed (its speed read now: it went), the landing approved")
done(rp, rv, { act = "boost", done = true, n = nb })
check(entryOf(rv) and entryOf(rv).act == "land" and entryOf(rv).n == nl and rpart:getModData().thr.busy ~= nil
    and near(gas(rpart), 1 / 3, 1e-6), "... the boost's late end: names no action here, the landing untouched")
rv.dz = 0.075
done(rp, rv, { done = true })
check(entryOf(rv) == nil, "... the landing's own end: over")
nb = boostOff(false)
check(askLand(rp, rv, nb) == "thrustOk" and near(gas(rpart), 1 - 1 / 3, 1e-6),
    "a boost that never pushed (fallen off before its answer), the landing first: the boost's air back, the landing billed")
rv.dz = 0.075
done(rp, rv, { done = true })
check(entryOf(rv) == nil, "... over")
-- S1: a boost handed on at D2 (no end from its driver): the helper's "can't" does not end it in the air
rv.x, rv.y, rv.dz, rv.speed = 300.5, 300.5, 1.075, 0
rpart:getModData().thr = { gas = 1, at = H.hours() }
check(ask(rp, rv, "boost") == "thrustOk", "S1: a boost on a roof")
rv.x, rv.dz, rv.speed = 301.5, 0.9, 30 -- past its edge, falling; its driver's machine says nothing
local w1 = 0
while not (entryOf(rv) and entryOf(rv).helper) and w1 < 30000 do wait(250) w1 = w1 + 250 end
check(entryOf(rv) and entryOf(rv).helper == bystander, "S1: up at D2: handed to the bystander after " .. w1 .. " ms")
done(bystander, rv, { act = "boost", done = false, abort = true })
check(entryOf(rv) ~= nil and rpart:getModData().thr.busy ~= nil,
    "S1: the helper could not (its own term): still pending in the air, not over, busy kept")
wait(1000)
check(entryOf(rv) ~= nil and (entryOf(rv).orphan or entryOf(rv).helper ~= bystander), "S1: ... D2 again: an orphan")
rv.dz = 0.075
TH.adopt() -- an orphan waits for someone near (tried cleared): the bystander again
local h1 = entryOf(rv) and entryOf(rv).helper
check(h1 == bystander, "S1: the orphan down near the bystander: handed to them again")
if h1 then done(h1, rv, { act = "boost", done = true }) end
check(entryOf(rv) == nil and rpart:getModData().thr.busy == nil, "S1: its helper's end on the ground: over, busy cleared")
rv.npid = nil
-- R10: the server reads the floors every time (a floor built since its last read counts)
rv.x, rv.y, rv.dz = 302.5, 302.5, 1.075
check(TH.groundZ(rv) == 0, "R10: no floor at level 1 there: the ground")
roof["302,302"] = 1
check(TH.groundZ(rv) == 1, "R10: a floor built there since, the same tile and level: counted")
roof["302,302"] = nil
-- R13: a stunt asked on a roof's edge, the car off it before the answer: the driver's machine lands it at once and
-- asks the soft landing; the server ends the driver's own stunt first, the landing approved, nobody handed the car
online = { bystander }
v.driver, p.vehicle, v.dz, v.speed, v.npid = p, v, 0, 30, nil
part:getModData().thr = { gas = 1, at = H.hours() }
local _, a13 = ask(p, v, "kickflip")
check(a13 and a13.n ~= nil, "R13: a kickflip approved")
local sent13 = #H.sent
v.dz = 1
check(askLand(p, v, a13.n) == "thrustOk" and entryOf(v).act == "land" and near(gas(part), 1 - 1 / 3, 1e-6) and v.npid == nil,
    "R13: its soft landing at the server after it: the stunt ended (no look saw it go: its air back), the landing billed, the physics stays")
wait(1000)
v.dz = 0
done(p, v, { done = true })
local handed13 = false
for i = sent13 + 1, #H.sent do if H.sent[i].command == "thrustLand" then handed13 = true end end
check(entryOf(v) == nil and not handed13 and v.npid == nil, "R13: landed: over, nobody handed it")
part:getModData().thr = { gas = 1, at = H.hours() }
v.dz = 1
check(ask(p, v, "land") == "thrustOk" and ask(p, v, "kickflip") == "THRUST_BUSY" and entryOf(v).act == "land",
    "R13: the soft landing at the server first: the stunt after it THRUST_BUSY, the landing goes on")
v.dz = 0
done(p, v, { done = true })
part:getModData().thr = { gas = 1, at = H.hours() }
local _, a13b = ask(p, v, "kickflip")
check(a13b and a13b.n ~= nil, "R13: a kickflip again")
v.driver, bystander.vehicle = bystander, v
check(askLand(bystander, v, a13b.n) == "THRUST_BUSY" and entryOf(v).act == "kickflip",
    "R13: a soft landing asked by another driver while someone else's action runs: THRUST_BUSY as ever")
v.driver, bystander.vehicle = p, nil
done(p, v, { done = true })
-- S3: a soft landing names the ask it takes over (over = that ask's n): naming none, or another, THRUST_BUSY
part:getModData().thr = { gas = 1, at = H.hours() }
v.dz = 0
local _, a3 = ask(p, v, "kickflip")
v.dz = 1
check(ask(p, v, "land") == "THRUST_BUSY" and askLand(p, v, a3.n + 1000) == "THRUST_BUSY" and entryOf(v).act == "kickflip"
    and entryOf(v).n == a3.n, "S3: a late soft landing naming no ask, or another one: THRUST_BUSY, the stunt goes on")
-- S2: the motor off before the soft landing reaches the server: refused, the stunt and its due checks as they were
v.running = false
check(askLand(p, v, a3.n) == "THRUST_ENGINE" and entryOf(v) and entryOf(v).act == "kickflip" and entryOf(v).n == a3.n
    and part:getModData().thr.busy ~= nil and hooked, "S2: the land refused THRUST_ENGINE: the stunt still pending, busy kept, its timer on")
v.running = true
v.dz = 0
done(p, v, { done = true })
check(entryOf(v) == nil, "S2: the stunt's own end: over")
online = { caller, helper }

H.section("thrusters: SP")
H.side(false, false)
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
check(entryOf(v) ~= nil, "SP: fly approved")
H.paused = true
wait(60000) -- a minute's frames, paused
H.paused = false
wait(100)
check(entryOf(v) ~= nil, "SP: a minute's pause runs no due check (D2 would be 28 s)")
H.advanceMs(60000)
timer()
check(entryOf(v) ~= nil, "SP: a minute's hitch counts as 0.25 s")
wait(3000)
done(p, v, { done = true, sec = 2 })
check(entryOf(v) == nil and near(gas(part), 1 - 2 / 8, 1e-6), "SP: billed the client's 2 s (its flight clock skips the pause)")
part:getModData().thr = { gas = 1, at = H.hours() }
ask(p, v, "fly")
wait(3000)
done(p, v, { done = true, sec = 100 })
check(near(gas(part), 1 - 3 / 8, 1e-6), "SP: a client saying 100 s after 3 s is billed the 3 s since approval")
H.side(false, true)
if hooked then timer() end
check(not hooked and next(TH.pending) == nil, "nothing left pending on the server: its timer gone")
onTick.Add, onTick.Remove = tickAdd, tickRemove -- the client's OnTick is its own

H.section("thrusters: client")
H.side(true, false)
local halo = {}
HaloTextHelper = { addBadText = function(pl, s) halo[#halo + 1] = s end }
local exits = 0
ISVehicleMenu = { onExit = function() exits = exits + 1 end }
H.stub("Vehicles/ISUI/ISVehicleMenu")
H.stub("MinidoracatTesla/Units")
local function vec() return { set = function(s, x, y, z) s[1], s[2], s[3] = x, y, z; return s end,
    x = function(s) return s[1] end, y = function(s) return s[2] end, z = function(s) return s[3] end } end
Vector3f = { new = function() return vec():set(0, 0, 0) end }
local gt = getGameTime()
gt.getPhysicsSecondsSinceLastUpdate = function() return 0.02 end
assert(loadfile(MEDIA .. "/client/MinidoracatTesla/Thruster.lua"))()
local cv, cp, cpart = car({ x = 500.5, y = 500.5 })
local savedGSP = getSpecificPlayer
function getSpecificPlayer(i) return i == 0 and cp or nil end
cpart:getModData().thr = { gas = 1, at = H.hours() }
cv.local_, cv.dz = true, 0.075
function cv:isLocalPhysicSim() return self.local_ end
function cv:getDebugZ() return self.dz end
function cv:getLinearVelocity(o) return o:set(0, self.vy or 0, self.speed / 3.6) end
function cv:getForwardVector(o) return o:set(0, 0, 1) end
function cv:getUpVector(o) return o:set(0, self.uy or 1, 0) end
function cv:isPhysicsActive() return true end
function cv:getMass() return 1500 end
function cv:addImpulse() self.impulses = (self.impulses or 0) + 1 end
function cv:getCurrentSpeedKmHour() return self.speed end
-- the n of this machine's last thrust; thrustOk for it (pn 0, this machine's first player)
local function lastN()
    for i = #H.clientSent, 1, -1 do
        local c = H.clientSent[i]
        if c.command == "thrust" then return c.args.n end
    end
end
local function okFor(act, extra)
    local a = { vid = cv:getId(), act = act, n = lastN(), pn = 0 }
    for k, x in pairs(extra or {}) do a[k] = x end
    T.ClientCommands.thrustOk(a)
end
cv.speed = 70
check(not TH.ask(cp, cv, "boost") and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_FAST", "over boostMaxKmh: refused here")
cv.speed = 30
cv.local_ = false
local ok
ok, why = TH.check(cp, cv, "boost")
check(not ok and why == "THRUST_AUTHORITY", "the car's physics on another machine: THRUST_AUTHORITY")
cv.local_ = true
local sent = #H.clientSent
check(TH.ask(cp, cv, "boost") and H.clientSent[#H.clientSent].command == "thrust" and #H.clientSent == sent + 1
    and type(lastN()) == "number", "boost at 30 km/h: asked the server, with its n")
local n1 = lastN()
sent = #H.clientSent
local said = #halo
check(not TH.ask(cp, cv, "kickflip") and #H.clientSent == sent and #halo == said and select(2, TH.check(cp, cv, "kickflip")) == nil,
    "D3: asked and not answered: another ask refused here, nothing sent, nothing said (the ring: no reason line)")
okFor("boost", { n = n1 + 1 })
local e = H.clientSent[#H.clientSent]
check(TH.active() == nil and e.command == "thrustEnd" and e.args.n == n1 + 1 and e.args.done == false
    and not TH.ask(cp, cv, "kickflip"), "D3: an answer for another n: not flown (its air back), this ask still waits")
H.advanceMs(3001)
sent = #H.clientSent
okFor("boost", { n = n1 })
e = H.clientSent[#H.clientSent]
check(#H.clientSent == sent + 1 and e.command == "thrustEnd" and e.args.done == false and e.args.n == n1 and TH.active() == nil,
    "an approval after 3 s: not flown, the air back (its n)")
TH.ask(cp, cv, "boost")
cpart:getModData().thr = { gas = 0.5, at = H.hours() }
T.ClientCommands.deny({ reason = "THRUST_NO_AIR", vid = cv:getId(), pn = 0, n = lastN() })
said = halo[#halo]
cpart:getModData().thr = { gas = 1, at = H.hours() }
check(said == "IGUI_MinidoracatTesla_Deny_THRUST_NO_AIR IGUI_MinidoracatTesla_Thrust_Refill" and TH.check(cp, cv, "boost"),
    "F2: refused by the server: said with when the tank is full again (H.whyText), the ask answered (the next one may go)")
check(TH.whyText(nil, "THRUST_NO_AIR") == "IGUI_MinidoracatTesla_Deny_THRUST_NO_AIR"
    and TH.whyText(cv, "THRUST_NO_AIR") == "IGUI_MinidoracatTesla_Deny_THRUST_NO_AIR", "no car, or a full tank: no refill time")
local ticks = H.count("OnTick")
TH.ask(cp, cv, "boost")
okFor("boost")
check(TH.active() and TH.active().act == "boost" and TH.active().n == lastN() and H.count("OnTick") == ticks + 1,
    "approved in time: runs on its OnTick, its n kept")
ISVehicleMenu.onExit(cp, 0)
check(exits == 0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_IN_AIR", "no getting out while it runs")
TH.tick()
check((cv.impulses or 0) == 1, "one impulse a frame")
cv.driver = nil
sent = #H.clientSent
local nb = TH.active().n
TH.tick()
e = H.clientSent[#H.clientSent]
check(TH.active() == nil and H.count("OnTick") == ticks and e.command == "thrustEnd" and e.args.done == false
    and e.args.abort == true and e.args.n == nb, "driver gone before it sped up: ended as an abort with its n, its OnTick removed")
ISVehicleMenu.onExit(cp, 0)
check(exits == 1, "getting out works again")
-- the show: waits for the car's physics, then rolls up on its thrusters after a 0.04-floor lift; anyone sitting in ends it
cv.driver, cp.vehicle, cv.speed, cv.local_, cv.dz = nil, nil, 0, false, 0.075
-- the engine's: a fraction within the car's floor, clamped 0-0.99 (BaseVehicle.java:4161-4168)
function cv:setDebugZ(z) self.dz = math.floor(self.dz) + math.max(0, math.min(0.99, z)) end
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "kickflip", app = true, n = 501, pn = 0 })
check(TH.active() and TH.active().phase == "wait" and TH.active().app == "show" and TH.active().n == 501,
    "the show: waits for the car's physics, with the server's n")
H.advanceMs(-60000)
TH.tick()
check(TH.active() and TH.active().phase == "wait", "R14: the wall clock set back while it waits: no time passed, it waits on")
H.advanceMs(2100)
TH.tick()
e = H.clientSent[#H.clientSent]
check(TH.active() == nil and e.command == "thrustEnd" and e.args.n == 501, "A4/R14: 2 s on from there: given up, not stuck")
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "kickflip", app = true, n = 502, pn = 0 })
cv.local_ = true
TH.tick()
check(TH.active().phase == "roll" and near(cv.dz, 0.115, 1e-9), "the physics here: lifted 0.04 floor, rolling up")
cv.driver = cp
sent = #H.clientSent
TH.tick()
e = H.clientSent[#H.clientSent]
check(TH.active() == nil and #H.clientSent == sent + 1 and e.command == "thrustEnd" and e.args.done == false,
    "someone sits in mid-show: ended, the air back")
cv.driver = nil
cv.local_, cv.dz = false, 1.075
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "backflip", app = true, pn = 0, n = 503 })
cv.local_ = true
TH.tick()
check(near(cv.dz, 1.115, 1e-6), "a show on the first floor: lifted 0.04 floor within it, no jump up a floor")
cv.driver = cp
TH.tick()
cv.dz = 0.075
-- the driver's roll-up: the motor's cruise to rollKmh, no thrust, then the action
function cv:isRegulator() return self.reg == true end
function cv:getRegulatorSpeed() return self.regSpd or 0 end
function cv:setRegulator(b) self.reg = b end
function cv:setRegulatorSpeed(sp) self.regSpd = sp end
cp.vehicle, cv.speed, cv.impulses = cv, 0, 0
TH.ask(cp, cv, "boost")
okFor("boost")
TH.tick()
check(TH.active().phase == "drive" and cv.reg == true and cv.regSpd == 8 and cv.impulses == 0,
    "the driver's car under 6 km/h: the motor's cruise at 8 km/h takes it there, no thrust")
cv.speed = 7
TH.tick()
check(TH.active().phase == "boost" and cv.reg == false and cv.regSpd == 0, "at 6 km/h: the cruise back as it was, the action runs")
-- a boost off an edge (r2fix2-mp-r2 boostroof: its F ran on through the fall, H.watch waits on F, no soft landing): over
-- as it falls, the driver's soft landing asked at once, the boost's busy flag in this machine's copy (the server's
-- clear not here yet) no bar to it
local cpart = T.Battery.part(cv)
local thr0 = cpart:getModData().thr
cpart:getModData().thr = { gas = 2 / 3, at = H.hours(), busy = { act = "boost", by = "test", t = H.hours() } }
local nbr = TH.active().n
cv.dz, cv.vy = 0.075 + 2.2 / TH.FLOOR, -3
sent = #H.clientSent
TH.tick()
local eb, lb = H.clientSent[sent + 1], H.clientSent[sent + 2]
check(eb and eb.command == "thrustEnd" and eb.args.act == "boost" and eb.args.n == nbr and lb and lb.command == "thrust"
    and lb.args.act == "land" and lb.args.over == nbr and TH.active() and TH.active().act == "land",
    "a boost falling off an edge: ended, the soft landing (naming the boost: over) asked at once and running")
okFor("land")
cv.driver = nil; TH.tick(); cv.driver = cp -- the landing's end (driver gone: an abort)
cpart:getModData().thr = thr0
cv.dz, cv.vy, cv.speed = 0.075, 0, 7
cv.driver = nil
TH.tick()
cv.driver, cv.speed = cp, 30
-- a car tipping nose-first over a roof's edge (r2int-sp-full roof 1 #1: it slid down the wall below at -1.9 m/s at
-- most and stood on its nose, never past -2 m/s): tilted and coming down over the drop, the soft landing asked;
-- upright at that speed it is not a fall yet
cv.dz, cv.vy, cv.uy, cv.speed = 0.075 + 2.2 / TH.FLOOR, -1.2, 1, 5
sent = #H.clientSent
TH.watch(cp, cv)
check(#H.clientSent == sent and TH.active() == nil, "upright over a drop at -1.2 m/s: no soft landing")
cv.uy = 0.5
TH.watch(cp, cv)
local tl = H.clientSent[sent + 1]
check(tl and tl.command == "thrust" and tl.args.act == "land" and TH.active() and TH.active().act == "land",
    "tipped 60 degrees over a drop at -1.2 m/s: the soft landing asked")
okFor("land")
cv.driver = nil; TH.tick(); cv.driver = cp
cv.dz, cv.vy, cv.uy, cv.speed = 0.075, 0, nil, 30
-- what the client asks VehicleManager is a query; AutoDrive driving this car refuses
local seenQ, vmr = nil, T.vmRefusal
T.vmRefusal = function(_, _, _, qq) seenQ = qq end
TH.check(cp, cv, "boost")
T.vmRefusal = vmr
check(seenQ == true, "the client's look asks VehicleManager as a query")
local mdad = MDAD
MDAD = { Drive = { isActive = function(pn) return pn == 0 end } }
ok, why = TH.check(cp, cv, "boost")
MDAD = mdad
check(not ok and why == "THRUST_BUSY", "the driver's AutoDrive on: THRUST_BUSY")
-- a helper's machine that can't land it says so at once
TH.ask(cp, cv, "boost")
okFor("boost")
sent = #H.clientSent
T.ClientCommands.thrustLand({ vid = cv:getId(), pn = 0, n = 777, term = 3 })
e = H.clientSent[#H.clientSent]
check(#H.clientSent == sent + 1 and e.command == "thrustEnd" and e.args.abort == true and e.args.done == false and e.args.n == 777
    and e.args.term == 3, "handed a car while busy here: can't, said at once with the server's n and the hand-over's term (R7)")
cv.driver = nil
TH.tick()
cv.driver = cp
-- a stunt past its turn coming down faster than the soft landing's curve: the landing takes it, its braking fed
-- forward (r2fe-sp-a: switched at 1.5 m on the PD alone, touchdown -2.7 / -3.2 m/s)
local savedCore, savedSH = getCore, getPlayerScreenHeight
local ground = { isSolid = function() return false end, isSolidTrans = function() return false end,
    getObjects = function() return { size = function() return 0 end } end, isBlockedTo = function() return false end,
    getFloor = function() return true end, TreatAsSolidFloor = function() return true end }
getCell = function() return { getGridSquare = function(_, x, y, z) return z == 0 and ground or nil end } end -- open, no roof
-- the camera: zoom 1, out to 3 (0.25 a step)
local zoom = 1
getCore = function() return { getZoom = function() return zoom end, getMaxZoom = function() return 3 end,
    doZoomScroll = function(_, _, d) zoom = zoom + 0.25 * d end, getKey = function() return 0 end } end
getPlayerScreenHeight = function() return 1080 end
function cv:addImpulse(j) self.impulses, self.jy = (self.impulses or 0) + 1, j:y() end
local function flipAt(vy)
    cv.dz, cv.vy, cv.speed = 0.075, 0, 30
    TH.ask(cp, cv, "kickflip")
    okFor("kickflip")
    cv.dz = 0.075 + 7 / TH.FLOOR -- 7 m: near its profile (8 m apex) through the turn (0.8-1.8 s)
    while TH.active() and TH.active().t <= 1.85 do TH.tick() end
    cv.vy = vy
    TH.tick()
    return TH.active() and TH.active().phase
end
local function abort() cv.driver = nil; TH.tick(); cv.driver = cp end
check(flipAt(-5) == "stunt", "past its turn at 7 m sinking 5 m/s (the landing allows 8): the stunt goes on")
abort()
check(zoom == 1, "the stunt's camera zoomed back")
check(flipAt(-12) == "land", "past its turn at 7 m sinking 12 m/s: the soft landing takes it")
cv.dz, cv.vy = 0.075 + 2 / TH.FLOOR, -math.sqrt(0.49 + 12 * 1.7)
TH.tick()
check(near(cv.jy, (10 + 6) * 1500 * 0.02 * 100, 1), "on the landing's curve at 2 m: g + its 6 m/s^2 braking, fed forward")
abort()
-- D2: the soft landing starts before the server's answer; refused, it stops here, nothing more said
cv.dz, cv.vy, cv.speed = 0.075 + 4 / TH.FLOOR, -5, 0
check(TH.ask(cp, cv, "land") and TH.active() and TH.active().act == "land" and TH.active().ok == false,
    "a fall: the soft landing runs at once, not approved yet")
ticks = H.count("OnTick")
sent = #H.clientSent
T.ClientCommands.deny({ reason = "THRUST_BUSY", vid = cv:getId(), pn = 0, n = lastN() + 1 })
check(TH.active() ~= nil, "D2: a refusal of another n: it goes on")
T.ClientCommands.deny({ reason = "THRUST_BUSY", vid = cv:getId(), pn = 0, n = lastN() })
check(TH.active() == nil and H.count("OnTick") == ticks - 1 and #H.clientSent == sent
    and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_BUSY", "D2: refused: stopped, its OnTick removed, no thrustEnd, the reason shown")
TH.ask(cp, cv, "land")
okFor("land")
T.ClientCommands.deny({ reason = "THRUST_BUSY", vid = cv:getId(), pn = 0, n = lastN() })
check(TH.active() and TH.active().ok, "D2: approved first: a refusal after cannot stop it")
abort()
cv.vy = 0
-- R6: the car gone on the server (unloaded, its id another's): refused with the ask's n as any other refusal; the
-- soft landing not approved yet stops, its ask answered. A refusal of another command about the car (T.deny: its
-- vid, no n) is no answer to it: the landing goes on
cv.dz, cv.vy = 0.075 + 4 / TH.FLOOR, -5
TH.ask(cp, cv, "land")
T.ClientCommands.deny({ reason = "MOVING", vid = cv:getId(), pn = 0 })
check(TH.active() and TH.active().act == "land",
    "R6: another command about the car refused meanwhile (no n): the unapproved landing goes on")
H.side(false, true)
H.removeVehicle(cv)
cmds.thrust(cp, { vid = cv:getId(), act = "land", n = lastN() })
H.addVehicle(cv)
local gone6 = H.sent[#H.sent]
H.side(true, false)
T.ClientCommands.deny(gone6.args)
check(gone6.command == "deny" and gone6.args.reason == "NO_VEHICLE" and gone6.args.n == lastN()
    and gone6.args.vid == cv:getId() and TH.active() == nil and select(2, TH.check(cp, cv, "boost")) ~= "THRUST_BUSY",
    "R6: the car gone on the server: refused with the ask's n, the unapproved landing stopped, its ask answered")
cv.vy = 0
-- R10: the flying machine's floor cache: kept within an action, cleared at the next one's start
local lvl1 = false
local cell6 = getCell
getCell = function() return { getGridSquare = function(_, x, y, z) return (z == 0 or z == 1 and lvl1) and ground or nil end } end
cv.dz = 1.075
check(TH.groundZ(cv, true) == 0, "R10: no floor at level 1: the ground (cached)")
lvl1 = true
TH.ask(cp, cv, "land")
check(TH.active() and TH.groundZ(cv, true) == 1, "R10: a floor built since: the next action's start clears the cache")
T.ClientCommands.deny({ reason = "THRUST_BUSY", vid = cv:getId(), pn = 0, n = lastN() })
-- S6: the pre-flight check reads the floors afresh: a floor built under the car since the cache was filled
lvl1 = false
TH.groundReset()
cv.dz, cv.vy, cv.speed = 1.075, 0, 0
check(TH.groundZ(cv, true) == 0, "S6: no floor at level 1: the ground (cached)")
lvl1 = true
local _, why6 = TH.check(cp, cv, "kickflip")
check(why6 ~= "THRUST_AIRBORNE", "S6: a floor built there since, the car on it: not THRUST_AIRBORNE (" .. tostring(why6) .. ")")
getCell, cv.dz = cell6, 0.075
-- R13: a stunt asked, the car off the edge before the answer: the soft landing it fell into runs on through the stunt's
-- late thrustOk (the server ends the stunt itself), nothing said
cv.dz, cv.vy, cv.speed = 0.075, 0, 30
TH.ask(cp, cv, "kickflip")
local n13 = lastN()
cv.dz, cv.vy = 0.075 + 4 / TH.FLOOR, -5
check(TH.ask(cp, cv, "land") and TH.active() and TH.active().act == "land", "R13: off the edge before the stunt's answer: the soft landing runs")
local land13 = H.clientSent[#H.clientSent]
check(land13.args.act == "land" and land13.args.over == n13, "S3: the soft landing names the unanswered stunt it takes over (over = its n)")
local c13 = #H.clientSent
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "kickflip", n = n13, pn = 0 })
check(#H.clientSent == c13 and TH.active() and TH.active().act == "land" and not TH.active().ok,
    "R13: the stunt's thrustOk while the landing waits for its own: no thrustEnd, the landing goes on")
okFor("land")
check(TH.active() and TH.active().ok, "R13: the landing approved")
abort()
cv.vy = 0
-- flying a parked car whose physics won't switch on (r2fe-sp-g, 3 of 3 such stayed down): the motor creeps it
-- first, then it lifts and flies, the cruise back as it was
cv.dz, cv.vy, cv.speed, cv.impulses, cv.reg, cv.regSpd = 0.075, 0, 0, 0, nil, nil
function cv:isPhysicsActive() return self.awake == true end
function cv:setPhysicsActive() end
TH.ask(cp, cv, "fly")
okFor("fly", { sec = 8 })
check(TH.active().phase == "wake" and cv.reg == true and cv.regSpd == 3 and cv.impulses == 0,
    "a parked car that won't wake: the motor's creep at 3 km/h, no thrust yet")
TH.tick()
check(TH.active().phase == "wake", "not awake yet: still creeping")
cv.awake, cv.speed = true, 2
TH.tick()
check(TH.active().phase == "fly" and cv.reg == false and cv.regSpd == 0 and near(cv.dz, 0.115, 1e-9),
    "awake and moving: the cruise back, lifted 0.04 floor, flying")
abort()
function cv:isPhysicsActive() return true end
cv.setPhysicsActive, cv.awake = nil, nil
-- physics on, yet it stays put (r2fe-sp-i, 2 of 2): half a second up under 0.15 m, the creep once, then flies or gives up
local savedKD = isKeyDown
isKeyDown = function() return false end
cv.dz, cv.speed, cv.reg, cv.regSpd, zoom = 0.075, 0, nil, nil, 0.5 -- zoomed in: flying's 5 m needs one step out
TH.ask(cp, cv, "fly")
okFor("fly", { sec = 8 })
check(TH.active().phase == "fly" and zoom == 0.75, "physics on: straight to flying, the camera zoomed out a step")
local zoomed = zoom
while TH.active() and TH.active().phase == "fly" and TH.active().t < 0.7 do TH.tick() end
check(TH.active() and TH.active().phase == "wake" and cv.reg == true and TH.active().flown == 0,
    "half a second still on the ground: the motor's creep, the flown time not counted")
cv.speed = 2
TH.tick()
check(TH.active().phase == "fly" and TH.active().woke and cv.reg == false and zoom == zoomed,
    "moving: flying again (zoomed out already: no more steps)")
sent = #H.clientSent
while TH.active() and TH.active().t < 1.2 do TH.tick() end
e = H.clientSent[#H.clientSent]
check(TH.active() == nil and e.command == "thrustEnd" and e.args.done == false, "still down after the creep: given up, not crept again")
check(zoom == 0.5, "D4: zoomed out, through the creep and flying again: the camera back as it was")
-- the hover (integration, real body 2026-11-24, r2int-sp-t0: 3.49 m 3 s after a take-off for 3 m; the step to flyH
-- wound the PID's integral up on the climb): a car that only moves up and down (g 10, its frame's impulse) takes
-- off to flyH no more than 0.2 m over and holds it within 0.2 m 2-4 s after the ask; PageUp held 2 s: flyMaxH, no
-- more than 0.2 m over, within 0.2 m from 1.5 s after the key's release
local fc = TH.conf(cv)
local upHeld = false
TH.KEYS.up = { getValue = function() return 201 end }
isKeyDown = function(k) return k == 201 and upHeld end
cv.dz, cv.vy, cv.speed, zoom = 0.075, 0, 0, 1
TH.ask(cp, cv, "fly")
okFor("fly", { sec = 30 })
local function hm() return (cv.dz - 0.075) * TH.FLOOR end
local function step(n, fn)
    for _ = 1, n do
        cv.jy = 0
        TH.tick()
        cv.vy = cv.vy + cv.jy / (1500 * 100) - 10 * 0.02 -- the impulse sent x 100 (see "on the landing's curve" above)
        cv.dz = cv.dz + cv.vy * 0.02 / TH.FLOOR
        if cv.dz < 0.075 then cv.dz, cv.vy = 0.075, math.max(0, cv.vy) end
        if fn then fn(hm()) end
    end
end
local over, worst = 0, 0
step(100, function(h) over = math.max(over, h - fc.flyH) end)
step(100, function(h) over = math.max(over, h - fc.flyH) worst = math.max(worst, math.abs(h - fc.flyH)) end)
check(TH.active() and TH.active().phase == "fly" and over <= 0.2 and worst < 0.2,
    string.format("hover: up to flyH %.1f m, %.2f m over at most, within %.2f m 2-4 s after the ask", fc.flyH, over, worst))
upHeld = true
step(100)
upHeld = false
local overUp, worstUp = 0, 0
step(75, function(h) overUp = math.max(overUp, h - fc.flyMaxH) end)
step(75, function(h) overUp = math.max(overUp, h - fc.flyMaxH) worstUp = math.max(worstUp, math.abs(h - fc.flyMaxH)) end)
check(overUp <= 0.2 and worstUp < 0.2,
    string.format("hover: PageUp 2 s to flyMaxH %.1f m, %.2f m over at most, within %.2f m from 1.5 s after", fc.flyMaxH, overUp, worstUp))
-- a controller's player flies with it as vanilla drives (CarController.java:958-967): RT ahead, LT back, the left
-- stick steers; the right stick sets the height (pushed up: negative, PlayerCamera.java:148). A stick resting a little
-- off (inside the dead zone) does nothing
local pad = { mx = 0, ay = 0 }
isJoypadRTPressed = function(id) return id == 3 and pad.rt == true end
isJoypadLTPressed = function(id) return id == 3 and pad.lt == true end
getJoypadMovementAxisX = function(id) return id == 3 and pad.mx or 0 end
getJoypadAimingAxisY = function(id) return id == 3 and pad.ay or 0 end
isJoypadRBPressed = function(id) return id == 3 and pad.rb == true end
cp.pad = 3
local fa = TH.active()
local psi0, hG0, spd0 = fa.st.psiT, fa.st.hG, fa.spd
pad.mx, pad.ay = 0.15, -0.15
step(10)
check(fa.st.psiT == psi0 and fa.st.hG == hG0 and fa.spd == spd0, "controller: sticks inside the dead zone, no trigger: holds course")
pad.rt = true
step(10)
local spdRT = fa.spd
pad.rt, pad.lt = false, true
step(100)
check(spdRT > spd0 and fa.spd < 0, "controller: RT ahead, LT back")
pad.lt, pad.mx = false, 1
step(10)
local psiR = fa.st.psiT
pad.mx = -1
step(20)
check(psiR > psi0 and fa.st.psiT < psiR, "controller: the left stick right turns right, left turns left")
pad.mx, pad.ay = 0, 1
step(10)
local hDown = fa.st.hG
pad.ay = -1
step(5)
check(hDown < hG0 and fa.st.hG > hDown, "controller: the right stick down lowers the hover, up raises it")
pad.rb = true
local hRB = fa.st.hG
step(5)
check(fa.st.hG == hRB, "controller: RB held, the right stick looks around (vanilla), the height stays")
pad.ay, pad.rb = 0, nil
-- the flying tip: the bound height keys and vanilla's exit key named (the Interact key: OnUseVehicle lands it, below);
-- a controller's player: the controller's
local realGetText, realKeyName = getText, getKeyName
getText = function(k, ...) return table.concat({ k, ... }, "|") end
getKeyName = function(k) return "K" .. tostring(k) end
local padTip, padPill = TH.flyTip(cp), TH.flyTip(cp, "IGUI_MinidoracatTesla_HUD_FlyKeys")
cp.pad = nil
check(padTip == "IGUI_MinidoracatTesla_Tip_ThrustFlyPad" and TH.flyTip(cp) == "IGUI_MinidoracatTesla_Tip_ThrustFly|K201|K0|K0",
    "the flying tip names the keys bound now (an unbound one: its 0); a controller's player: the controller's tip")
check(padPill == "IGUI_MinidoracatTesla_HUD_FlyKeysPad"
    and TH.flyTip(cp, "IGUI_MinidoracatTesla_HUD_FlyKeys") == "IGUI_MinidoracatTesla_HUD_FlyKeys|K201|K0|K0",
    "the dashboard's flying pill: its own short words, the same keys")
getText, getKeyName = realGetText, realKeyName
-- the dashboard's flying pill (HUD.lua): the whole seconds of air left, real time counting them down as the server's
-- D2 does; FreeFlight (no limit): true; "land" once landing is asked; nobody else's (a passenger, another car)
local fl0, flown0 = TH.flight(cp, cv), fa.flown
for _ = 1, 12 do H.advanceMs(100) step(1) end
local fl1 = TH.flight(cp, cv)
check(fl0 == math.ceil(30 - flown0) and fa.flown > flown0 + 1 and fl1 == math.ceil(30 - fa.flown) and fl1 < fl0,
    "flying: the pill's seconds left count real time down (" .. tostring(fl0) .. " -> " .. tostring(fl1) .. ")")
check(TH.flight({}, cv) == nil and TH.flight(cp, {}) == nil, "flying: not another player's, not another car's")
fa.sec = nil
check(TH.flight(cp, cv) == true, "FreeFlight: no seconds")
fa.sec = 30
-- flying: the V ring's thrusters slice is Land (the first press lands it, H.ask), and getting out (vanilla's exit: the
-- A button, ISButtonPrompt.lua:444; the Interact key, OnUseVehicle) lands it too; the landing itself still holds on
local slices, realTex = {}, getTexture
getTexture = function(p) return p end
TH.radialSlice({ addSlice = function(_, text, tex, fn, a, b, c) slices[#slices + 1] = { text = text, fn = fn, a = a, b = b, c = c } end }, cp, cv)
getTexture = realTex
local ls = slices[1]
check(#slices == 1 and ls.text == "IGUI_MinidoracatTesla_Radial_ThrustLand" and ls.fn and not fa.wantLand, "flying: the ring's slice is Land")
ls.fn(ls.a, ls.b, ls.c)
check(fa.wantLand == true, "the Land slice: lands it")
fa.wantLand = nil
local ex0, h0 = exits, #halo
ISVehicleMenu.onExit(cp, 0)
check(exits == ex0 and #halo == h0 and fa.wantLand == true and TH.flight(cp, cv) == "land",
    "flying: getting out lands it, nothing said, still in the seat; the pill says landing")
step(1)
ISVehicleMenu.onExit(cp, 0)
check(fa.phase == "land" and exits == ex0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_IN_AIR", "landing: no getting out yet")
check(TH.flight(cp, cv) == "land", "landing: the pill still says landing")
abort()
check(TH.flight(cp, cv) == nil, "over: no flying pill")
TH.KEYS.up = nil
isKeyDown, isJoypadRTPressed, isJoypadLTPressed, getJoypadMovementAxisX, getJoypadAimingAxisY = savedKD, nil, nil, nil, nil
isJoypadRBPressed = nil
getCore, getPlayerScreenHeight, cv.vy = savedCore, savedSH, nil

-- restore
H.side(false, true)
MS.thruster = nil
addSound, getOnlinePlayers, T.ThrusterFx, T.vmRefusal = saved.addSound, saved.getOnlinePlayers, saved.fx, saved.vmRefusal
getPlayerByOnlineID, H.player = saved.byId, saved.player
T.Remote.appLink = saved.appLink
for _, k in ipairs(OPTS) do SandboxVars.MinidoracatTesla[k] = saved.sandbox[k] end
gt.getPhysicsSecondsSinceLastUpdate = nil
HaloTextHelper, ISVehicleMenu, Vector3f, getCell, getSpecificPlayer = nil, nil, nil, saved.getCell, savedGSP
