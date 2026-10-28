-- Motor sound for other players (client/MinidoracatTesla/Sound.lua + server/MinidoracatTesla/SoundRelay.lua):
-- the driver's beats, the server's driver check and radius, the listener's registry, expiry and its one OnTick.
-- Runs after test_sound.lua (name order): Sound and the HUD fakes are loaded. Real FMOD and the network are E2E
-- remote-sound-mp.
local check = H.check
local T = MinidoracatTesla
local S = T.Sound
local saved = { getWorld = getWorld, getSpecificPlayer = getSpecificPlayer, getOnlinePlayers = getOnlinePlayers }

local emitters = {}
function getWorld()
    return { getFreeEmitter = function(_, x, y, z)
        local e = { x = x, y = y, z = z, sounds = {}, nextRef = 1, pitchCalls = 0 }
        function e:playSoundLoopedImpl(name) local r = self.nextRef; self.nextRef = r + 1; self.sounds[r] = { name = name, vol = 1 }; return r end
        function e:setVolume(r, v) if self.sounds[r] then self.sounds[r].vol = v end end
        function e:setPitch(r, p) self.pitchCalls = self.pitchCalls + 1; self.pitch = p end
        function e:stopSound(r) self.sounds[r] = nil end
        function e:setPos(nx, ny, nz) self.x, self.y, self.z = nx, ny, nz end
        function e:playing() for _, s in pairs(self.sounds) do return s end return nil end
        emitters[#emitters + 1] = e
        return e
    end }
end

local function tesla(o)
    local v = H.vehicle(o)
    v.gear, v.throttle = 1, 0
    function v:getTransmissionNumber() return self.gear end
    function v:getThrottle() return self.throttle end
    function v:getHeadlightsOn() return false end
    function v:areAllDoorsLocked() return false end
    function v:isStarting() return false end
    function v:isHotwired() return false end
    return v
end

-- ---------------------------------------------------------------- driver: when the beats go out
H.section("remote sound: driver beats (MP client)")
H.side(true, false)
local dash = ISVehicleDashboard:new(0, 0, 552, 121)
dash.playerNum = 3
local car = tesla({})
dash:setVehicle(car)
local h = T.HUD.get(3)
local function beats()
    local out = {}
    for _, c in ipairs(H.clientSent) do
        if c.command == "motor" then out[#out + 1] = c.args end
    end
    return out
end
H.clientSent = {}
h:update()
check(#beats() == 0, "motor off: nothing sent")
car.running = true
h:update()
local b = beats()
check(#b == 1 and b[1].on == true and b[1].vid == car:getId(), "layers start: one 'motor on' with the vid")
for _ = 1, 40 do H.advanceMs(100); h:update() end
check(#beats() == 1, "4 s later: still one (" .. #beats() .. ")")
for _ = 1, 10 do H.advanceMs(100); h:update() end
b = beats()
check(#b == 2 and b[2].on == true, "5 s: the heartbeat goes again")
for _ = 1, 100 do H.advanceMs(100); h:update() end
check(#beats() == 4, "every 5 s while driving (" .. #beats() .. " after 15 s)")
car.running = false
h:update()
b = beats()
check(#b == 5 and b[5].on == false and b[5].vid == car:getId(), "motor off: one 'motor off'")
h:update()
check(#beats() == 5, "stays quiet while off")
car.running = true
h:update()
dash:setVehicle(nil)
b = beats()
check(#b == 7 and b[6].on == true and b[7].on == false, "motor on again, then leaving the seat: 'on' then 'off'")
H.side(false, false)
car.running = true
dash:setVehicle(car)
H.clientSent = {}
for _ = 1, 60 do H.advanceMs(100); h:update() end
dash:setVehicle(nil)
check(#beats() == 0, "SP: never sends (no one else to tell)")

-- ---------------------------------------------------------------- server: who may send, who hears it
H.section("remote sound: server relay")
H.side(false, true)
dofile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/SoundRelay.lua")
local R = T.SoundRelay
local cmd = T.ServerCommands.motor
local v = tesla({ x = 500.5, y = 500.5 })
local driver = H.player({ name = "drv", x = 500, y = 500 })
local passenger = H.player({ name = "pax", x = 501, y = 500 })
local near = H.player({ name = "near", x = 600, y = 560 })    -- ~117 tiles
local far = H.player({ name = "far", x = 640, y = 500 })      -- 140 tiles
driver.vehicle, passenger.vehicle, v.driver = v, v, driver
local online = { driver, passenger, near, far }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
local function relayed(from)
    local out = {}
    for i = from + 1, #H.sent do
        if H.sent[i].command == "motor" then out[H.sent[i].player.name] = H.sent[i].args end
    end
    return out
end
local n = #H.sent
check(cmd(driver, { vid = v:getId(), on = true }) == 2, "driver's 'on': told 2 players")
local got = relayed(n)
check(got.pax and got.near and not got.drv and not got.far and got.pax.on == true and got.pax.vid == v:getId(),
    "to the passenger and the player 117 tiles away; not back to the driver, not to the one 140 away")
n = #H.sent
local refused = R.stats.refused
check(cmd(passenger, { vid = v:getId(), on = true }) == 0 and cmd(near, { vid = v:getId(), on = false }) == 0
    and #H.sent == n and R.stats.refused == refused + 2, "forged 'on' by a passenger, forged 'off' by a bystander: dropped, no reply")
check(cmd(driver, { vid = v:getId() + 0.5, on = true }) == 0 and cmd(driver, { vid = "x", on = true }) == 0
    and cmd(driver, { vid = 987654, on = true }) == 0 and #H.sent == n, "bad or unknown vid: dropped")
local gas = tesla({ script = "Base.CarNormal", x = 500.5, y = 500.5 })
gas.driver = driver
check(cmd(driver, { vid = gas:getId(), on = true }) == 0 and #H.sent == n, "not a Tesla: dropped")
check(cmd(driver, { vid = v:getId(), on = false }) == 2 and relayed(n).pax.on == false, "driver's 'off': relayed")
v.driver, driver.vehicle = nil, nil
n = #H.sent
check(cmd(driver, { vid = v:getId(), on = false }) == 2 and relayed(n).near.on == false,
    "'off' after the exit already emptied the seat: still relayed")
check(cmd(driver, { vid = v:getId(), on = true }) == 0, "'on' with nobody in the seat: dropped")
local realRemote = T.Remote
T.Remote = { summonApi = function() return { summonInfo = function(car) return car == v and { by = "x" } or nil end } end }
n, refused = #H.sent, R.stats.refused
check(cmd(near, { vid = v:getId(), on = false }) == 0 and #H.sent == n and R.stats.refused == refused + 1,
    "a summoned car (nobody in the seat): anyone's 'off' dropped, the server's summon sound stays")
T.Remote = realRemote
H.side(false, false)
v.driver = driver
n = #H.sent
check(cmd(driver, { vid = v:getId(), on = true }) == 0 and #H.sent == n, "SP: accepted but nobody to tell")

H.section("remote sound: server rate limit (the dispatcher's motor budget, Commands.lua CommandRate)")
H.side(false, true)
v.driver, driver.vehicle = driver, v
local M = T.CommandRate.LIMITS.motor
local function dropped() return T.CommandRate.dropped.motor or 0 end
local function burst(p, count, on) -- through the server's dispatch; returns how many players were told
    n = #H.sent
    for _ = 1, count do H.fire("OnClientCommand", T.MODULE, "motor", p, { vid = v:getId(), on = on }) end
    return #H.sent - n
end
H.advanceMs(M.ms) -- a fresh window for the driver
local limited = dropped()
check(burst(driver, 50, true) == 2 * M.max and dropped() == limited + 50 - M.max,
    "50 'on' at once: only the first " .. M.max .. " relayed (to 2 players each), the rest dropped")
check(burst(driver, 1, false) == 0, "over the limit even an 'off' is dropped (the listener's HEARD_MS ends it)")
v.driver, driver.vehicle, near.vehicle = near, nil, v
check(burst(near, 1, true) == 2, "another player's budget is their own")
v.driver, driver.vehicle, near.vehicle = driver, v, nil
H.advanceMs(M.ms)
check(burst(driver, 1, true) == 2, "next window: relayed again")
burst(driver, M.max, true)
H.advanceMs(-60000) -- the server's wall clock jumps back (getTimestampMs is System.currentTimeMillis)
check(burst(driver, 1, true) == 2, "clock set back a minute: a fresh window, not one stretched by the jump")
H.advanceMs(60000)
-- the real driver (Sound.update in the dashboard's 10 Hz update) for a minute, each "motor" it sends fed to the
-- server: beats every 5 s; from 10 s to 20 s the motor stopped and started every 0.5 s (faster than the power key
-- can: a start takes 1.5 s, VehicleEngine.java:210-211), then running again with its beats
H.advanceMs(M.ms)
limited = dropped()
H.side(true, false)
car.running = true
dash:setVehicle(car)
H.clientSent = {}
local told, done, times = 0, 0, {}
for i = 1, 600 do
    if i >= 100 and i < 200 and i % 5 == 0 then car.running = not car.running end
    H.side(true, false)
    h:update()
    H.side(false, true)
    local b = beats()
    for j = done + 1, #b do
        told = told + burst(driver, 1, b[j].on)
        times[#times + 1] = i
    end
    done = #b
    H.advanceMs(100)
end
local busiest = H.busiest(times, M.ms / 100) -- times are 100 ms ticks
check(busiest == M.max and told == 2 * done and dropped() == limited,
    "the driver's real rhythm (" .. done .. " in a minute, " .. busiest .. " in the busiest 5 s): every one relayed")
H.side(true, false)
dash:setVehicle(nil)
H.side(false, false)
getOnlinePlayers = saved.getOnlinePlayers

-- ---------------------------------------------------------------- listener: registry, emitters, the one OnTick
H.section("remote sound: listener")
H.side(true, false)
local savedCell = getCell
local hidden, unloaded = {}, {} -- "x,y" -> true: the listener cannot see that square / it is not loaded
local squares = {}
local function square(x, y)
    local k = math.floor(x) .. "," .. math.floor(y)
    if unloaded[k] then return nil end
    squares[k] = squares[k] or { k = k, isCouldSee = function(self, i) return i == 0 and not hidden[self.k] end }
    return squares[k]
end
function getCell() return { getGridSquare = function(_, x, y) return square(x, y) end } end
local me = H.player({ name = "me", x = 320, y = 320 }) -- the cars start north-west of me: in front of the listener
function me:getCurrentSquare() return square(self.x, self.y) end
function me:getPlayerNum() return 0 end
function getSpecificPlayer(i) return i == 0 and me or nil end
local other = H.player({ name = "other" })
local a = tesla({ x = 304.5, y = 300.5, running = true })
a.driver = other
local motor = T.ClientCommands.motor
local base, st = H.count("OnTick"), S.stats
local adds0, removes0 = st.tickAdds, st.tickRemoves
local function frame(ms) H.advanceMs(ms or 20); H.fire("OnTick") end
local function hz(n) for _ = 1, n do frame(100) end end
local function dist(v) return math.sqrt((v.x - me.x) ^ 2 + (v.y - me.y) ^ 2) end
-- what reaches the listener: the 3D copy through FMOD's inverse rolloff, plus the 2D copy as set
local function heardPws(e, v)
    local att = S.EXT_MIN / math.max(S.EXT_MIN, math.min(S.EXT_MAX, dist(v)))
    return e.pws.vol * att + e.pws2.vol / S.FLAT_GAIN, e.lp * att -- the 2D copy in 3D-copy units
end

check(H.count("OnTick") == base and st.tickAdds == adds0, "nobody driving: no OnTick of ours")
motor({ vid = a:getId(), on = true })
local e = S.heard[a:getId()]
check(e ~= nil and H.count("OnTick") == base + 1 and st.tickAdds == adds0 + 1, "first beat: registered, OnTick added")
motor({ vid = a:getId(), on = true })
check(H.count("OnTick") == base + 1 and st.tickAdds == adds0 + 1, "second beat: no second OnTick")
local ne = #emitters
frame(100)
check(#emitters == ne + 4 and e.motor.e ~= e.pws.e and e.motor2.e ~= e.pws2.e and e.motor.e ~= e.motor2.e,
    "car in earshot: four emitters, a 3D and a 2D copy of each layer")
check(e.motor.e.x == 304.5 and e.motor.e.y == 300.5 and e.pws.e.x == 304.5, "3D copies on the car")
check(e.motor2.e.x == 0 and e.motor2.e.y == 0 and e.pws2.e.x == 0, "2D copies at (0,0)")
check(e.motor.e:playing().name == "MinidoracatTesla_MotorExt" and e.pws.e:playing().name == "MinidoracatTesla_PWSForwardExt"
    and e.motor2.e:playing().name == "MinidoracatTesla_MotorExt" and e.pws2.e:playing().name == "MinidoracatTesla_PWSForwardExt",
    "outside: the *Ext sounds on all four")
a.x = 310.5
frame(10)
check(e.motor.e.x == 310.5 and e.pws.e.x == 310.5 and e.motor2.e.x == 0, "every frame: the 3D copies follow the car, the 2D ones stay")
a.speed = 20
hz(20)
local p20, pws20 = e.motor.pitch, e.pws.vol
check(pws20 > 0.3 and e.motor.vol > 0.2 and e.pws2.vol == 0 and e.motor2.vol == 0,
    "in sight, 20 km/h: the 3D copies play PWS and motor, the 2D copies are silent")

H.section("remote sound: out of sight")
motor({ vid = a:getId(), on = true }) -- a beat keeps the entry from expiring (HEARD_MS) in these long stretches
local k = math.floor(a.x) .. "," .. math.floor(a.y)
hidden[k] = true
local maxRatio, minRatio = 0, 9
for _ = 1, 6 do
    hz(1)
    local got, want = heardPws(e, a)
    maxRatio, minRatio = math.max(maxRatio, got / want), math.min(minRatio, got / want)
end
local att = S.FLAT_GAIN * S.EXT_MIN / dist(a)
check(e.seen == 0 and e.pws.vol == 0 and e.motor.vol == 0, "car out of sight: the 3D copies down to 0")
check(math.abs(e.pws2.vol - e.lp * att) < 1e-9 and math.abs(e.motor2.vol - e.lm * att) < 1e-9,
    "the 2D copies take over at level x min/d (" .. string.format("%.3f", e.pws2.vol) .. ")")
check(maxRatio <= 1 + 1e-9 and minRatio >= 1 - 1e-9, "crossfade: the two copies add up to one, never double ("
    .. string.format("%.3f..%.3f", minRatio, maxRatio) .. ")")
check(e.motor2.pitch == e.motor.pitch and e.motor2.pitch == p20, "the 2D motor copy gets the same pitch")
a.speed = 45
hz(20)
check(e.motor.pitch > p20 and e.motor2.pitch == e.motor.pitch and e.pws2.vol == 0, "45 km/h out of sight: pitch up on both, PWS silent")
a.speed = 20
hz(20)
a.x = 316.5
hidden[math.floor(a.x) .. "," .. math.floor(a.y)] = true
hz(1)
check(math.abs(e.pws2.vol - e.lp * S.FLAT_GAIN * S.EXT_MIN / dist(a)) < 1e-9, "the 2D copies follow the distance (" .. string.format("%.1f", dist(a)) .. " tiles)")
a.x = 310.5
hz(1)
hidden[k] = nil
maxRatio, minRatio = 0, 9
for _ = 1, 6 do
    hz(1)
    local got, want = heardPws(e, a)
    maxRatio, minRatio = math.max(maxRatio, got / want), math.min(minRatio, got / want)
end
check(e.seen == 1 and e.pws2.vol == 0 and e.pws.vol == e.lp and maxRatio <= 1 + 1e-9 and minRatio >= 1 - 1e-9,
    "back in sight: the 3D copies take over again, no doubling")
-- the listener faces world (-1,-1): a car south-east of me is behind it, even in plain sight
a.x, a.y = 330.5, 330.5
maxRatio, minRatio = 0, 9
for _ = 1, 6 do
    hz(1)
    local got, want = heardPws(e, a)
    maxRatio, minRatio = math.max(maxRatio, got / want), math.min(minRatio, got / want)
end
check(e.seen == 0 and e.pws.vol == 0 and math.abs(e.pws2.vol - e.lp * S.FLAT_GAIN * S.EXT_MIN / dist(a)) < 1e-9
    and maxRatio <= 1 + 1e-9 and minRatio >= 1 - 1e-9, "in sight but behind the listener (south-east): the 2D copies, no doubling")
a.x, a.y = 330.5, 309.5
hz(6)
check(e.seen == 0, "90 degrees off the listener's forward (north-east): 2D")
a.x, a.y = 310.5, 300.5
hz(6)
check(e.seen == 1, "back north-west: 3D again")
me.x, me.y = 310.2, 300.7
hidden[math.floor(me.x) .. "," .. math.floor(me.y)] = true
hz(6)
check(e.seen == 1, "car on the listener's own square: counts as seen (the engine does not occlude it)")
me.x, me.y = 320, 320
hidden[k] = nil
unloaded[k] = true
hz(6)
check(e.seen == 0 and e.pws2.vol > 0, "car's square not loaded: the 2D copies (the engine occludes it even more)")
unloaded[k] = nil
hz(6)
motor({ vid = a:getId(), on = true })
a.speed = -8
hz(20)
check(e.pws.vol == 0 and e.pws2.vol == 0 and e.motor.vol > 0, "reversing (negative speed on remote clients): no forward PWS, motor on")
a.speed = 20
hz(20)
a.x = 400.5 -- 100 tiles: past distanceMax, where FMOD's rolloff goes flat
hidden[math.floor(a.x) .. "," .. math.floor(a.y)] = true
check(e.motor ~= nil, "playing before the car leaves")
local four = { e.motor.e, e.pws.e, e.motor2.e, e.pws2.e }
hz(20)
check(e.motor == nil and four[1]:playing() == nil and four[2]:playing() == nil and four[3]:playing() == nil
    and four[4]:playing() == nil and S.heard[a:getId()] ~= nil and H.count("OnTick") == base + 1,
    "past 30 tiles (out of sight too): all four faded out and stopped, still registered")
a.x = 310.5
hz(2)
check(e.motor ~= nil and e.motor2 ~= nil, "back in earshot: playing again")
a.running = false
frame(100)
check(e.motor == nil and e.motor2 == nil and S.heard[a:getId()] ~= nil, "motor off on the remote car: silent at once, entry waits for 'off'")
a.running = true
hz(2)
motor({ vid = a:getId(), on = false })
check(S.heard[a:getId()] == nil and e.motor == nil and H.count("OnTick") == base and st.tickRemoves == removes0 + 1,
    "'off': layers stopped, entry gone, OnTick removed")

-- expiry: the driver vanished without an 'off'
motor({ vid = a:getId(), on = true })
hz(2)
local e2 = S.heard[a:getId()]
check(e2.motor ~= nil, "registered again and playing")
hz(117)
check(S.heard[a:getId()] ~= nil, "11.9 s without a beat: still registered")
hz(2)
check(S.heard[a:getId()] == nil and e2.motor == nil and H.count("OnTick") == base and st.tickRemoves == removes0 + 2,
    "12 s without a beat: expired, silent, OnTick removed")

-- passenger, own car, unloaded car, two cars
me.vehicle = a
motor({ vid = a:getId(), on = true })
hz(1)
e = S.heard[a:getId()]
check(e.motor.e.x == 0 and e.motor.e.y == 0 and e.motor.e:playing().name == "MinidoracatTesla_Motor"
    and e.pws.e:playing().name == "MinidoracatTesla_PWSForward" and e.motor2 == nil, "passenger: the cabin layers in 2D, no copies")
local pf = e.motor.e
a.x = 320.5
frame(10)
check(pf.x == 0, "passenger: the 2D emitters stay at (0,0)")
me.vehicle = nil
hz(1)
check(e.motor.e ~= pf and e.motor.e.x == 320.5 and e.motor2 ~= nil, "passenger steps out: restarted outside, 3D and 2D copies")
a.driver = me
hz(1)
check(e.motor == nil, "I am the driver now: my own dashboard plays the cabin layers, nothing here")
a.driver = other
local b2 = tesla({ x = 305.5, y = 305.5, running = true })
b2.driver = H.player({ name = "third" })
motor({ vid = b2:getId(), on = true })
check(H.count("OnTick") == base + 1, "a second car: still one OnTick")
H.removeVehicle(a)
hz(1)
check(e.motor == nil and S.heard[a:getId()] ~= nil and S.heard[b2:getId()].motor ~= nil, "first car unloaded: silent, kept until expiry; second plays")
motor({ vid = b2:getId(), on = false })
check(H.count("OnTick") == base + 1, "one car still registered: OnTick stays")
hz(121)
check(H.count("OnTick") == base and st.playing == 0 and st.tickAdds - adds0 == st.tickRemoves - removes0,
    "all gone: OnTick removed, nothing playing, adds == removes")
motor({ vid = "x", on = true })
check(H.count("OnTick") == base, "malformed beat: ignored")

H.section("remote sound: a summoned car (nobody drives)")
local sc = tesla({ x = 306.5, y = 306.5, running = true, speed = 10 }) -- no driver: AutoDrive's summon pushes it
motor({ vid = sc:getId(), on = true }) -- a driver's beat would not do: nobody in the seat
local se = S.heard[sc:getId()]
hz(3)
check(se.motor == nil, "an ordinary beat for a car without a driver: silent (the old rule)")
motor({ vid = sc:getId(), on = true, sum = true }) -- the server at the summon's start (SoundRelay R.summon)
hz(10)
check(se.motor ~= nil and se.motor.vol > 0.1 and se.pws.vol > 0.2 and se.motor.e:playing().name == "MinidoracatTesla_MotorExt",
    "summon 'on': the whine and the forward PWS play with nobody in the seat")
H.advanceMs(S.HEARD_MS + 1000)
hz(1)
check(S.heard[sc:getId()] ~= nil and se.motor ~= nil, "no beats during a summon: still playing past HEARD_MS")
sc.running = false
hz(1)
check(se.motor == nil and S.heard[sc:getId()] ~= nil, "motor off (summon ended, engine shut off): silent")
motor({ vid = sc:getId(), on = false, sum = true })
check(S.heard[sc:getId()] == nil and H.count("OnTick") == base, "summon 'off': forgotten, OnTick removed")
-- another player's game reads 0 km/h for a car nobody drives (BaseVehicle.java:4312-4316): the speed from its moves
sc.running, sc.speed = true, 0
motor({ vid = sc:getId(), on = true, sum = true })
se = S.heard[sc:getId()]
for _ = 1, 15 do sc.x = sc.x + 1; hz(1) end -- 1 tile per 100 ms: 36 km/h
check(se.motor ~= nil and se.motor.vol > 0.1 and se.pws.vol > 0.2,
    "this game reads 0 km/h, the car moves: the whine and the forward PWS from its moves")
motor({ vid = sc:getId(), on = false, sum = true })
motor({ vid = sc:getId(), on = true, sum = true, back = true })
se = S.heard[sc:getId()]
for _ = 1, 15 do sc.x = sc.x - 1; hz(1) end
check(se.motor ~= nil and se.motor.vol > 0.1 and se.pws.vol < 0.05, "a reverse summon (back): the whine, no forward PWS")
motor({ vid = sc:getId(), on = false, sum = true })
motor({ vid = sc:getId(), on = true, sum = true }) -- come / target backing out of a dead end: no back flag
se = S.heard[sc:getId()]
sc.speed = -3 -- this game runs the physics (the summoner's): a reverse reading, slower than the 100 ms moves
for _ = 1, 15 do sc.x = sc.x - 1; hz(1) end
check(se.motor ~= nil and se.motor.vol > 0.1 and se.pws.vol < 0.05, "the game's own reverse reading keeps its sign: no forward PWS")
motor({ vid = sc:getId(), on = false, sum = true })
sc.x, sc.speed = 306.5, 10
motor({ vid = sc:getId(), on = true, sum = true })
H.removeVehicle(sc)
hz(1)
check(S.heard[sc:getId()] ~= nil and S.heard[sc:getId()].motor == nil, "summoned car unloaded: silent, no error")
H.advanceMs(S.SUMMON_MS + 1)
hz(1)
check(S.heard[sc:getId()] == nil and H.count("OnTick") == base, "a summon 'off' never came: dropped after SUMMON_MS")

getWorld, getSpecificPlayer, getCell = saved.getWorld, saved.getSpecificPlayer, savedCell
H.side(false, true)

-- server: the summon's start and end go to everyone near the car, the summoner included (no driver to send beats)
H.section("remote sound: server tells a summon")
online = { driver, passenger, near, far }
function getOnlinePlayers() return { size = function() return #online end, get = function(_, i) return online[i + 1] end } end
v.driver, driver.vehicle, passenger.vehicle = nil, nil, nil
n = #H.sent
check(R.summon(v, true) == 3, "summon start: told the 3 players within 120 tiles (the summoner too)")
got = relayed(n)
check(got.drv and got.drv.sum == true and got.drv.on == true and got.near and not got.far, "{ vid, on, sum = true }")
n = #H.sent
check(R.summon(v, false) == 3 and relayed(n).pax.on == false, "summon end: 'off' to the same players")
getOnlinePlayers = saved.getOnlinePlayers
