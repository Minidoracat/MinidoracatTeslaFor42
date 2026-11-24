-- Thrusters (Roadster Rocket; shared/server/client Thruster.lua): the server approves and bills the air tank, refills
-- it from the pack (never under the 12V floor off a charger), refunds what never took off, caps a flight's bill by the
-- time that passed, ends what the driver's machine never ended (its one-shot timer gone after), and only the approved
-- driver ends an action. The client: a late or unasked approval gives the air back, an approved action runs on its
-- OnTick and ends with thrustEnd when the driver is gone, and no getting out while it runs. The flying itself: real-game
-- E2E (thruster-sp / thruster-mp). Tested on the Model S with `thruster = {}` put in its Specs here only.
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
    function v:authorizationServerCollide(id, localCollide) self.collide = { id, localCollide } end
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
cmds.thrustEnd(p, { vid = v:getId(), done = true })
check(thr.busy == nil and TH.pending[v:getId()] == nil and near(thr.gas, 0) and fxs[#fxs] == "land",
    "ended by the driver: not busy, still spent, the touchdown mist")
local ticks = H.count("OnTick")
timer()
check(H.count("OnTick") == ticks - 1, "nothing pending: the timer removes itself")
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
cmds.thrustEnd(p, { vid = v:getId(), done = false })
check(near(gas(part), 0.5, 1e-6) and fxs[#fxs] == "off", "never took off: the air back, flames off")
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
H.advanceMs(3000)
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 100 })
check(near(gas(part), 1 - 3 / 8, 1e-6), "a client claiming 100 s after 3 s is billed 3 s")
timer() -- nothing pending: gone
part:getModData().thr.gas = 0.1
check(ask(p, v, "fly") == "THRUST_NO_AIR", "under one second of air: THRUST_NO_AIR")
SandboxVars.MinidoracatTesla.FreeFlight = true
ticks = H.count("OnTick")
what, args = ask(p, v, "fly")
check(what == "thrustOk" and args.sec == nil and H.count("OnTick") == ticks, "FreeFlight: no limit, no expiry timer")
cmds.thrustEnd(p, { vid = v:getId(), done = true, sec = 50 })
check(near(gas(part), 0.1), "FreeFlight: flying costs nothing")
what = ask(p, v, "fly")
v.driver = nil
TH.onUpdate(v, part)
check(TH.pending[v:getId()] == nil and part:getModData().thr.busy == nil, "FreeFlight: driver gone, ended at the next parts update")
v.driver = p
SandboxVars.MinidoracatTesla.FreeFlight = false
what = ask(p, v, "land")
check(what == "thrustOk" and near(gas(part), 0), "the soft landing is never refused for air; it takes what is left")
cmds.thrustEnd(p, { vid = v:getId(), done = true })

H.section("thrusters: expiry")
part:getModData().thr.gas = 1
ask(p, v, "kickflip")
v.driver = nil
local helper = H.player({ name = "near", x = v.x + 5, y = v.y })
local far = H.player({ name = "far", x = v.x + 100, y = v.y })
online = { far, helper }
H.advanceMs(14999)
timer()
check(TH.pending[v:getId()] ~= nil, "before the deadline: still pending")
ticks = H.count("OnTick")
H.advanceMs(1)
timer()
check(TH.pending[v:getId()] == nil and part:getModData().thr.busy == nil and near(gas(part), 0),
    "never ended: the server ends it at its deadline (billed: it may have flown)")
check(v.collide and v.collide[1] == helper:getOnlineID() and v.collide[2] == true,
    "driverless: the nearest player's machine takes the car's physics (LocalCollide) so it falls")
check(H.count("OnTick") == ticks - 1, "and the timer is gone")
v.driver = p
-- a busy flag with no pending entry (the server restarted mid-action): cleared on the next request
part:getModData().thr = { gas = 1, at = H.hours(), busy = { act = "fly", by = "x", t = 0 } }
check(ask(p, v, "boost") == "thrustOk", "a stale busy flag (server restart) does not lock the car")
cmds.thrustEnd(p, { vid = v:getId(), done = true })
timer()

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
function cv:getLinearVelocity(o) return o:set(0, 0, self.speed / 3.6) end
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
check(TH.active() == nil and H.count("OnTick") == ticks and e.command == "thrustEnd" and e.args.done == false,
    "driver gone before it sped up: ended, not done, its OnTick removed")
ISVehicleMenu.onExit(cp, 0)
check(exits == 1, "getting out works again")

-- restore
H.side(false, true)
MS.thruster = nil
onTick.Add = tickAdd
addSound, getOnlinePlayers, T.ThrusterFx = saved.addSound, saved.getOnlinePlayers, saved.fx
for _, k in ipairs(OPTS) do SandboxVars.MinidoracatTesla[k] = saved.sandbox[k] end
gt.getPhysicsSecondsSinceLastUpdate = nil
HaloTextHelper, ISVehicleMenu, Vector3f, getCell = nil, nil, nil, nil
