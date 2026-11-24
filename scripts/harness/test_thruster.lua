-- Thrusters (Roadster Rocket; shared/server/client Thruster.lua): the server approves and bills the air tank, refills
-- it from the pack (never under the 12V floor off a charger), and judges every end itself (MP): the air back only if
-- its own look each frame never saw the car leave the ground (a boost: speed up), a flight billed by the seconds the
-- client says but never under the server's clock less the roll-up and landing caps; an end said in the air hands
-- the car on. No watchdog: due checks on a one-shot timer (gone after), only for the very car approved (ids are
-- reused) - D2 hands a car left in the air to the nearest player who has not had it (thrustLand), or leaves it to
-- the first who comes near; D3 still up: the next one; a helper who can't says so at once. A stale busy flag clears
-- on load. SP: the client's word, and a pause runs no due check. The phone app's show: its checks, the motor started
-- (3 tries), the caller's machine given the physics, D1 after the approach's budget. The client: the driver's
-- roll-up on the motor's cruise, the show's on the thrusters after a lift within the floor (setDebugZ clamps like
-- the engine), a flight's limit in real time (a pause not counted), aborts said as such, a helper who can't says
-- so. The flying itself: real-game E2E (thruster-sp / thruster-mp). Tested on the Model S with `thruster = {}` put
-- in its Specs here only.
local check, near = H.check, H.near
local T = MinidoracatTesla
local B = T.Battery
local MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"
local cmds = T.ServerCommands

H.section("thrusters: server")
H.side(false, true)
H.require("MinidoracatTesla/Thruster") -- shared
assert(loadfile(MEDIA .. "/server/MinidoracatTesla/Thruster.lua"))()
local TH = T.Thruster

local OPTS = { "Thrusters", "FlightSeconds", "FreeFlight", "ThrusterRefillMinutes", "ThrusterRefillKwh" }
local saved = { addSound = addSound, getOnlinePlayers = getOnlinePlayers, fx = T.ThrusterFx, sandbox = {} }
for _, k in ipairs(OPTS) do saved.sandbox[k] = SandboxVars.MinidoracatTesla[k] end
local sounds, fxs, online = {}, {}, {}
function addSound(src, x, y, z, r, vol) sounds[#sounds + 1] = { src = src, r = r, vol = vol } end
T.ThrusterFx = { set = function(v, mode) fxs[#fxs + 1] = mode or "off" end }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
-- the timer the server adds: captured to run it without firing every module's OnTick
local onTick, tickAdd = Events.OnTick, Events.OnTick.Add
local timer
onTick.Add = function(fn) timer = fn; tickAdd(fn) end

local published = 0
for name, s in pairs(T.Specs) do if s.thruster ~= nil and name:find("_Roadster2", 1, true) == nil then published = published + 1 end end
local MS = T.Specs["Base.MinidoracatTesla_ModelS"]
check(published == 0, "no published car has thrusters (only the new Roadster's Specs may)")

local function car(o)
    o = o or {}
    local v = H.vehicle({ script = "Base.MinidoracatTesla_ModelS", running = o.running ~= false, noPack = o.noPack })
    local part = v:getPartById("GasTank")
    if part:getInventoryItem() then part:setContainerContentAmount(B.capacity(part) * (o.pct or 80) / 100) end
    function v:getVehicleTowing() return self.towing end
    function v:getDebugZ() return self.dz or 0 end
    function v:authorizationChanged(q) self.npid = q and q:getOnlineID() or -1 end
    function v:tryStartEngine() self.starts = (self.starts or 0) + 1; if self.startsOk then self.running = true end end
    function v:engineDoShuttingDown() self.running, self.shut = false, (self.shut or 0) + 1 end
    local p = H.player({ name = "pilot" .. v.id, x = v.x, y = v.y })
    v.driver, p.vehicle = p, v
    return v, p, part
end
local function last() return H.sent[#H.sent] end
local function ask(p, v, act)
    local n = #H.sent
    cmds.thrust(p, { vid = v:getId(), act = act })
    local s = H.sent[#H.sent]
    if #H.sent == n then return nil end
    return s.command == "deny" and s.args.reason or s.command, s.args
end
local function gas(part) return part:getModData().thr.gas end

local v, p, part = car()
check(ask(p, v, "kickflip") == "THRUST_NONE", "a car without Specs `thruster`: THRUST_NONE")
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
local q = H.player({ name = "passenger", x = v.x, y = v.y })
q.vehicle = v
check(ask(q, v, "kickflip") == "NOT_DRIVER", "a passenger: NOT_DRIVER")
v.towing = H.vehicle()
check(ask(p, v, "boost") == "TOWED", "towing: TOWED")
v.towing = nil
part:getModData().chg = { power = "grid" }
check(ask(p, v, "boost") == "CABLE_PLUGGED", "a charge cable in: CABLE_PLUGGED")
part:getModData().chg = nil
local nv, np = car({ noPack = true })
check(ask(np, nv, "boost") == "NO_PACK", "no pack: NO_PACK")

local tx, ns, nf = v.transmits, #sounds, #fxs
local what, args = ask(p, v, "kickflip")
local thr = part:getModData().thr
check(what == "thrustOk" and args.vid == v:getId() and args.act == "kickflip" and args.sec == nil,
    "kickflip approved: thrustOk to the driver")
check(near(thr.gas, 0) and thr.busy and thr.busy.act == "kickflip" and thr.busy.by == p.name and v.transmits == tx + 1,
    "a full tank spent, busy with who asked, sent to the clients")
check(#sounds == ns + 1 and sounds[#sounds].r == 150 and sounds[#sounds].vol == 150 and fxs[#fxs] == "flip",
    "heard like the horn (150/150); the flip flames on")
check(TH.pending[v:getId()] and H.count("OnTick") >= 1 and timer ~= nil, "pending, with its expiry timer")
check(ask(p, v, "boost") == "THRUST_BUSY", "a second action meanwhile: THRUST_BUSY")
cmds.thrustEnd(q, { vid = v:getId(), done = true })
check(thr.busy ~= nil and TH.pending[v:getId()], "thrustEnd from anyone but the approved driver: ignored")
v.dz = 1 timer() v.dz = 0 -- the server sees it up
local ticks = H.count("OnTick")
cmds.thrustEnd(p, { vid = v:getId(), done = false })
check(TH.pending[v:getId()] ~= nil, "MP: the end is the server's to judge, on its next frame")
timer()
check(thr.busy == nil and TH.pending[v:getId()] == nil and near(thr.gas, 0) and fxs[#fxs] == "land"
    and H.count("OnTick") == ticks - 1,
    "the server saw it up: billed though the client says not done; the touchdown mist; the timer gone")
check(ask(p, v, "kickflip") == "THRUST_NO_AIR", "an empty tank: THRUST_NO_AIR")

H.section("thrusters: refill from the pack")
local kwh0 = B.kwh(part)
H.setHours(H.hours() + 15 / 60) -- half of 30 refill minutes
local _, cut = TH.settle(v, part)
check(near(gas(part), 0.5, 1e-6) and near(kwh0 - B.kwh(part), 20, 1e-6) and cut == false,
    "half the refill time: half a tank for half of 40 kWh; the clients' estimate agrees (no send of its own)")
check(near(TH.gasNow(part:getModData().thr, H.hours() + 1), 1) and TH.minutesToFull(0.5) == 15, "estimate and minutes to full")
what = ask(p, v, "boost")
check(what == "thrustOk" and near(gas(part), 0.5 - 1 / 3, 1e-6), "boost takes a third")
cmds.thrustEnd(p, { vid = v:getId(), done = true })
timer()
check(near(gas(part), 0.5, 1e-6) and fxs[#fxs] == "off", "a boost the server never saw speed up: the air back though the client says done")
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

H.section("thrusters: flying")
part:getModData().thr.gas = 1
SandboxVars.MinidoracatTesla.FlightSeconds = 8
what, args = ask(p, v, "fly")
check(what == "thrustOk" and near(args.sec, 8) and near(gas(part), 1) and fxs[#fxs] == "lift",
    "fly approved with 8 s of air, billed at the end")
v.dz = 1 timer() v.dz = 0
H.advanceMs(3000)
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 100 })
timer()
check(near(gas(part), 1 - 3 / 8, 1e-6), "a client claiming 100 s after 3 s is billed 3 s")
part:getModData().thr.gas = 1
ask(p, v, "fly")
v.dz = 1 timer() v.dz = 0
H.advanceMs(20000)
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 0 })
timer()
check(near(gas(part), 1 - 5 / 8, 1e-6), "a client claiming 0 s after 20 s: billed 5 s (20 less roll-up 3 and landing 12)")
part:getModData().thr.gas = 0.1
check(ask(p, v, "fly") == "THRUST_NO_AIR", "under one second of air: THRUST_NO_AIR")
SandboxVars.MinidoracatTesla.FreeFlight = true
ticks = H.count("OnTick")
what, args = ask(p, v, "fly")
check(what == "thrustOk" and args.sec == nil and H.count("OnTick") == ticks, "FreeFlight: no limit, no expiry timer")
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 50 })
timer()
check(near(gas(part), 0.1), "FreeFlight: flying costs nothing")
what = ask(p, v, "fly")
v.driver = nil
TH.onUpdate(v, part)
timer()
check(TH.pending[v:getId()] == nil and part:getModData().thr.busy == nil, "FreeFlight: driver gone, ended at the next parts update")
v.driver = p
SandboxVars.MinidoracatTesla.FreeFlight = false
what = ask(p, v, "land")
check(what == "thrustOk" and near(gas(part), 0), "the soft landing is never refused for air; it takes what is left")
cmds.thrustEnd(p, { vid = v:getId(), done = true })
timer()

H.section("thrusters: due checks (D2, D3)")
part:getModData().thr.gas = 1
ask(p, v, "kickflip")
local helper = H.player({ name = "near", x = v.x + 5, y = v.y })
local helper2 = H.player({ name = "near2", x = v.x + 8, y = v.y })
local far = H.player({ name = "far", x = v.x + 100, y = v.y })
online = { far, p, helper, helper2 }
H.advanceMs(24799)
timer()
check(TH.pending[v:getId()] ~= nil,
    "before D2 (roll-up 3 s + profile 3.8 s + off it 4 s + landing 12 s + 2 s): still pending")
v.dz = 1 -- still up
H.advanceMs(1)
timer()
local pe = TH.pending[v:getId()]
check(pe and pe.helper == helper and v.npid == helper:getOnlineID() and last().command == "thrustLand"
    and last().player == helper and last().args.pn == helper:getPlayerNum(),
    "D2, still up: the nearest other player (not the driver, not 100 tiles off) lands it, told its split-screen slot")
cmds.thrustEnd(p, { vid = v:getId(), done = true })
check(TH.pending[v:getId()] ~= nil and pe.helper == helper, "the driver's late thrustEnd: ignored, the helper has it")
H.advanceMs(14000) timer()
check(pe.helper == helper, "D3 not before the helper's 2 s wait + 12 s landing + 1 s")
H.advanceMs(1000) timer()
check(pe.helper == helper2 and pe.tried[helper] and last().command == "thrustLand" and last().player == helper2,
    "D3 still up: that helper could not; the next nearest who has not had it")
cmds.thrustEnd(helper2, { vid = v:getId(), act = "land", done = false, abort = true })
H.advanceMs(500) timer()
check(pe.orphan and part:getModData().thr.busy.orphan and v.npid == -1 and pe.helper == nil,
    "the next one can't either (said at once): nobody near who has not had it, the server holds it")
local newcomer = H.player({ name = "newcomer", x = v.x + 3, y = v.y })
online = { far, p, helper, helper2, newcomer }
TH.onUpdate(v, part)
check(pe.helper == newcomer and v.npid == newcomer:getOnlineID(), "someone new comes near: theirs to land")
v.dz = 0
cmds.thrustEnd(newcomer, { vid = v:getId(), done = true })
timer()
check(TH.pending[v:getId()] == nil and part:getModData().thr.busy == nil and near(gas(part), 0) and v.npid == p:getOnlineID(),
    "down: over, billed; the physics back to the server, then to the driver still seated")
v.npid = nil
-- never seen up by D2: the air back
part:getModData().thr.gas = 1
ask(p, v, "backflip")
H.advanceMs(23800)
timer()
check(TH.pending[v:getId()] == nil and near(gas(part), 1), "D2 on the ground, never seen up: over, the air back")
-- the id reused by another car before a due check: that car is never touched
ask(p, v, "kickflip")
H.removeVehicle(v)
local v2 = H.vehicle({ id = v:getId(), script = "Base.MinidoracatTesla_ModelS" })
function v2:authorizationChanged() self.touched = true end
H.advanceMs(30000)
timer()
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
cmds.thrustEnd(p, { vid = v:getId(), done = true })
timer()

H.section("thrusters: the phone app's show")
local function show(pl, act)
    local n = #H.sent
    local why = TH.appShow(pl, v, act, 7)
    return why, #H.sent > n and last() or nil
end
local caller = H.player({ name = "caller", x = v.x + 10, y = v.y })
online = { caller, helper }
part:getModData().thr = { gas = 1, at = H.hours() }
check(show(caller, "fly") == "THRUST_NONE", "only kickflip and backflip are shows")
check(show(p, "kickflip") == "NOT_OUTSIDE", "the caller in a car: NOT_OUTSIDE")
check(show(caller, "kickflip") == "OCCUPIED", "someone in the driver's seat: OCCUPIED")
v.driver, p.vehicle = nil, nil
local away = H.player({ name = "away", x = v.x + 31, y = v.y })
check(show(away, "kickflip") == "TOO_FAR", "over 30 tiles off: TOO_FAR")
v.npid = 99
check(show(caller, "kickflip") == "THRUST_BUSY", "another machine holds the car: THRUST_BUSY")
v.npid = nil
v.running, v.startsOk, v.dz, v.shut = false, false, 0, 0
local why, s = show(caller, "kickflip")
check(why == nil and s == nil and v.starts == 1 and near(gas(part), 0) and part:getModData().thr.busy.app
    and part:getModData().thr.busy.eng, "motor off: billed, busy (app, eng), the motor asked to start")
H.advanceMs(2000) timer()
H.advanceMs(2000) timer()
check(v.starts == 3 and TH.pending[v:getId()] ~= nil, "not started: tried again every 2 s")
H.advanceMs(2000) timer()
check(TH.pending[v:getId()] == nil and near(gas(part), 1) and last().command == "appDone" and last().args.why == "CANT_START"
    and last().args.key == 7 and v:getNetPlayerId() == -1, "3 tries: the air back, CANT_START to the caller's app")
v.startsOk, v.starts = true, 0
why = show(caller, "kickflip")
H.advanceMs(2000) timer()
s = last()
check(why == nil and v.running and v.npid == caller:getOnlineID() and s.command == "thrustOk" and s.args.app
    and s.player == caller and s.args.pn == caller:getPlayerNum(), "started: the caller's machine gets the physics and flies it")
H.advanceMs(4499) timer()
check(TH.pending[v:getId()] ~= nil, "D1 not before the approach's budget (3 s) + 1.5 s")
H.advanceMs(1) timer()
check(TH.pending[v:getId()] == nil and near(gas(part), 1) and last().args.why == "THRUST_NO_LIFT" and v.npid == -1
    and v.shut == 1 and part:getModData().thr.busy == nil,
    "D1, never off the ground: the air back, the physics back, the motor the server started off")
show(caller, "backflip")
H.advanceMs(2000) timer()
v.dz = 1
H.advanceMs(4500) timer()
check(TH.pending[v:getId()] ~= nil, "D1 up in the air: carries on")
cmds.thrustEnd(caller, { vid = v:getId(), done = true })
H.advanceMs(499) timer()
check(TH.pending[v:getId()] ~= nil and TH.pending[v:getId()].helper == nil, "an end said in the air (claimed done): not taken")
H.advanceMs(1) timer()
check(TH.pending[v:getId()].helper == helper and last().command == "thrustLand", "still up half a second later: the next one lands it")
v.dz = 0
cmds.thrustEnd(helper, { vid = v:getId(), done = false })
timer()
check(TH.pending[v:getId()] == nil and near(gas(part), 0) and v.npid == -1 and not v.running,
    "down: billed (the server saw it up) though the helper says not done; physics and motor back as they were")
v.driver, p.vehicle, v.running, v.dz, v.npid = p, v, true, 0, nil

H.section("thrusters: SP")
H.side(false, false)
part:getModData().thr = { gas = 1, at = H.hours() }
cmds.thrust(p, { vid = v:getId(), act = "fly" })
check(TH.pending[v:getId()] ~= nil, "SP: fly approved")
timer()
H.paused = true
for _ = 1, 600 do H.advanceMs(100) timer() end -- a minute's frames
H.paused = false
H.advanceMs(100) timer()
check(TH.pending[v:getId()] ~= nil, "SP: a minute's pause runs no due check (D2 would be 25 s)")
H.advanceMs(60000) timer()
check(TH.pending[v:getId()] ~= nil, "SP: a minute's hitch counts as 0.25 s")
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 2 })
check(TH.pending[v:getId()] == nil and near(gas(part), 1 - 2 / 8, 1e-6), "SP: billed the client's 2 s (its flight clock skips the pause)")
timer()
H.side(false, true)

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
getCell = function() return { getGridSquare = function() return nil end } end
local gt = getGameTime()
gt.getPhysicsSecondsSinceLastUpdate = function() return 0.02 end
assert(loadfile(MEDIA .. "/client/MinidoracatTesla/Thruster.lua"))()
local cv, cp, cpart = car()
cpart:getModData().thr = { gas = 1, at = H.hours() }
cv.local_, cv.dz = true, 0.075
function cv:isLocalPhysicSim() return self.local_ end
function cv:getDebugZ() return self.dz end
function cv:getLinearVelocity(o) return o:set(0, self.vy or 0, self.speed / 3.6) end
function cv:getForwardVector(o) return o:set(0, 0, 1) end
function cv:getUpVector(o) return o:set(0, 1, 0) end
function cv:isPhysicsActive() return true end
function cv:getMass() return 1500 end
function cv:addImpulse() self.impulses = (self.impulses or 0) + 1 end
cv.speed = 30
local sent = #H.clientSent
check(TH.ask(cp, cv, "boost") and H.clientSent[#H.clientSent].command == "thrust" and #H.clientSent == sent + 1,
    "boost at 30 km/h: asked the server")
cv.speed = 70
check(not TH.ask(cp, cv, "boost") and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_FAST", "over boostMaxKmh: refused here")
cv.speed = 30
cv.local_ = false
local ok, why = TH.check(cp, cv, "boost")
check(not ok and why == "THRUST_AUTHORITY", "the car's physics on another machine: THRUST_AUTHORITY")
cv.local_ = true
H.advanceMs(3001)
sent = #H.clientSent
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "boost" })
local e = H.clientSent[#H.clientSent]
check(#H.clientSent == sent + 1 and e.command == "thrustEnd" and e.args.done == false and TH.active() == nil,
    "an approval after 3 s: not flown, the air back")
TH.ask(cp, cv, "boost")
ticks = H.count("OnTick")
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "boost" })
check(TH.active() and TH.active().act == "boost" and H.count("OnTick") == ticks + 1, "approved in time: runs on its OnTick")
ISVehicleMenu.onExit(cp, 0)
check(exits == 0 and halo[#halo] == "IGUI_MinidoracatTesla_Deny_THRUST_IN_AIR", "no getting out while it runs")
TH.tick()
check((cv.impulses or 0) == 1, "one impulse a frame")
cv.driver = nil
sent = #H.clientSent
TH.tick()
e = H.clientSent[#H.clientSent]
check(TH.active() == nil and H.count("OnTick") == ticks and e.command == "thrustEnd" and e.args.done == false
    and e.args.abort == true, "driver gone before it sped up: ended as an abort, not done, its OnTick removed")
ISVehicleMenu.onExit(cp, 0)
check(exits == 1, "getting out works again")
-- the show: waits for the car's physics, then rolls up on its thrusters after a 0.04-floor lift; anyone sitting in ends it
cv.driver, cp.vehicle, cv.speed, cv.local_, cv.dz = nil, nil, 0, false, 0.075
-- the engine's: a fraction within the car's floor, clamped 0-0.99 (BaseVehicle.java:4161-4168)
function cv:setDebugZ(z) self.dz = math.floor(self.dz) + math.max(0, math.min(0.99, z)) end
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "kickflip", app = true })
check(TH.active() and TH.active().phase == "wait" and TH.active().app == "show", "the show: waits for the car's physics")
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
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "backflip", app = true, pn = 0 })
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
function cv:setRegulatorSpeed(s) self.regSpd = s end
cp.vehicle, cv.speed, cv.impulses = cv, 0, 0
TH.ask(cp, cv, "boost")
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "boost" })
TH.tick()
check(TH.active().phase == "drive" and cv.reg == true and cv.regSpd == 8 and cv.impulses == 0,
    "the driver's car under 6 km/h: the motor's cruise at 8 km/h takes it there, no thrust")
cv.speed = 7
TH.tick()
check(TH.active().phase == "boost" and cv.reg == false and cv.regSpd == 0, "at 6 km/h: the cruise back as it was, the action runs")
cv.driver = nil
TH.tick()
cv.driver, cv.speed = cp, 30
-- what the client asks VehicleManager is a query; AutoDrive driving this car refuses
local seenQ, vmr = nil, T.vmRefusal
T.vmRefusal = function(_, _, _, q) seenQ = q end
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
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "boost" })
sent = #H.clientSent
T.ClientCommands.thrustLand({ vid = cv:getId(), pn = 0 })
e = H.clientSent[#H.clientSent]
check(#H.clientSent == sent + 1 and e.command == "thrustEnd" and e.args.abort == true and e.args.done == false,
    "handed a car while busy here: can't, said at once")
cv.driver = nil
TH.tick()
cv.driver = cp
-- a stunt past its turn coming down faster than the soft landing's curve: the landing takes it, its braking fed
-- forward (r2fe-sp-a: switched at 1.5 m on the PD alone, touchdown -2.7 / -3.2 m/s)
local savedCore, savedSH, savedCell = getCore, getPlayerScreenHeight, getCell
local ground = { isSolid = function() return false end, isSolidTrans = function() return false end,
    getObjects = function() return { size = function() return 0 end } end, isBlockedTo = function() return false end }
getCell = function() return { getGridSquare = function(_, x, y, z) return z == 0 and ground or nil end } end -- open, no roof
getCore = function() return { getZoom = function() return 1 end, getMaxZoom = function() return 1 end,
    doZoomScroll = function() end } end
getPlayerScreenHeight = function() return 1080 end
function cv:addImpulse(j) self.impulses, self.jy = (self.impulses or 0) + 1, j:y() end
local function flipAt(vy)
    cv.dz, cv.vy, cv.speed = 0.075, 0, 30
    TH.ask(cp, cv, "kickflip")
    T.ClientCommands.thrustOk({ vid = cv:getId(), act = "kickflip" })
    cv.dz = 0.075 + 7 / TH.FLOOR -- 7 m: near its profile (8 m apex) through the turn (0.8-1.8 s)
    while TH.active() and TH.active().t <= 1.85 do TH.tick() end
    cv.vy = vy
    TH.tick()
    return TH.active() and TH.active().phase
end
local function abort() cv.driver = nil; TH.tick(); cv.driver = cp end
check(flipAt(-5) == "stunt", "past its turn at 7 m sinking 5 m/s (the landing allows 8): the stunt goes on")
abort()
check(flipAt(-12) == "land", "past its turn at 7 m sinking 12 m/s: the soft landing takes it")
cv.dz, cv.vy = 0.075 + 2 / TH.FLOOR, -math.sqrt(0.49 + 12 * 1.7)
TH.tick()
check(near(cv.jy, (10 + 6) * 1500 * 0.02 * 100, 1), "on the landing's curve at 2 m: g + its 6 m/s^2 braking, fed forward")
abort()
-- flying a parked car whose physics won't switch on (r2fe-sp-g, 3 of 3 such stayed down): the motor creeps it
-- first, then it lifts and flies, the cruise back as it was
cv.dz, cv.vy, cv.speed, cv.impulses, cv.reg, cv.regSpd = 0.075, 0, 0, 0, nil, nil
function cv:isPhysicsActive() return self.awake == true end
function cv:setPhysicsActive() end
TH.ask(cp, cv, "fly")
T.ClientCommands.thrustOk({ vid = cv:getId(), act = "fly", sec = 8 })
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
getCore, getPlayerScreenHeight, getCell, cv.vy = savedCore, savedSH, savedCell, nil

-- restore
H.side(false, true)
MS.thruster = nil
onTick.Add = tickAdd
addSound, getOnlinePlayers, T.ThrusterFx = saved.addSound, saved.getOnlinePlayers, saved.fx
for _, k in ipairs(OPTS) do SandboxVars.MinidoracatTesla[k] = saved.sandbox[k] end
gt.getPhysicsSecondsSinceLastUpdate = nil
HaloTextHelper, ISVehicleMenu, Vector3f, getCell = nil, nil, nil, nil
