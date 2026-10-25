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
H.side(false, false)
v.driver = driver
n = #H.sent
check(cmd(driver, { vid = v:getId(), on = true }) == 0 and #H.sent == n, "SP: accepted but nobody to tell")
getOnlinePlayers = saved.getOnlinePlayers

-- ---------------------------------------------------------------- listener: registry, emitters, the one OnTick
H.section("remote sound: listener")
H.side(true, false)
local me = H.player({ name = "me", x = 300, y = 300 })
function getSpecificPlayer(i) return i == 0 and me or nil end
local other = H.player({ name = "other" })
local a = tesla({ x = 304.5, y = 300.5, running = true })
a.driver = other
local motor = T.ClientCommands.motor
local base, st = H.count("OnTick"), S.stats
local adds0, removes0 = st.tickAdds, st.tickRemoves
local function frame(ms) H.advanceMs(ms or 20); H.fire("OnTick") end
local function hz(n) for _ = 1, n do frame(100) end end

check(H.count("OnTick") == base and st.tickAdds == adds0, "nobody driving: no OnTick of ours")
motor({ vid = a:getId(), on = true })
local e = S.heard[a:getId()]
check(e ~= nil and H.count("OnTick") == base + 1 and st.tickAdds == adds0 + 1, "first beat: registered, OnTick added")
motor({ vid = a:getId(), on = true })
check(H.count("OnTick") == base + 1 and st.tickAdds == adds0 + 1, "second beat: no second OnTick")
local ne = #emitters
frame(100)
check(#emitters == ne + 2 and e.motor and e.pws and e.motor.e ~= e.pws.e, "car in earshot: two emitters, one per layer")
check(e.motor.e.x == 304.5 and e.motor.e.y == 300.5 and e.pws.e.x == 304.5, "emitters on the car (3D, not (0,0))")
check(e.motor.e:playing().name == "MinidoracatTesla_MotorExt" and e.pws.e:playing().name == "MinidoracatTesla_PWSForwardExt",
    "outside: the *Ext sounds")
a.x = 310.5
frame(10)
check(e.motor.e.x == 310.5 and e.pws.e.x == 310.5, "every frame between 10 Hz updates: emitters follow the car")
a.speed = 20
hz(20)
local p20, pws20 = e.motor.pitch, e.pws.vol
check(pws20 > 0.3 and e.motor.vol > 0.2, "20 km/h forward: PWS and motor audible")
a.speed = 45
hz(20)
check(e.motor.pitch > p20 and e.pws.vol == 0, "45 km/h: pitch up, PWS silent above 40")
a.speed = -8
hz(20)
check(e.pws.vol == 0 and e.motor.vol > 0, "reversing (negative speed on remote clients): no forward PWS, motor on")
a.speed = 20
hz(20)
a.x = 400.5 -- 100 tiles: past distanceMax, where FMOD's rolloff goes flat
hz(20)
check(e.motor == nil and S.heard[a:getId()] ~= nil and H.count("OnTick") == base + 1, "out of earshot: faded out and stopped, still registered")
a.x = 310.5
hz(2)
check(e.motor ~= nil, "back in earshot: playing again")
a.running = false
frame(100)
check(e.motor == nil and S.heard[a:getId()] ~= nil, "motor off on the remote car: silent at once, entry waits for 'off'")
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
    and e.pws.e:playing().name == "MinidoracatTesla_PWSForward", "passenger: the cabin layers in 2D")
local pf = e.motor.e
a.x = 320.5
frame(10)
check(pf.x == 0, "passenger: the 2D emitters stay at (0,0)")
me.vehicle = nil
hz(1)
check(e.motor.e ~= pf and e.motor.e.x == 320.5, "passenger steps out: restarted outside in 3D")
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

getWorld, getSpecificPlayer = saved.getWorld, saved.getSpecificPlayer
H.side(false, true)
