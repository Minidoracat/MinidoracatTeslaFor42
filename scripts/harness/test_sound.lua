-- Tesla cabin sound layers (client/MinidoracatTesla/Sound.lua): curve, emitter life cycle, call budget.
-- Runs after test_hud.lua (name order) and reuses its client fakes (ISUIElement, ISVehicleDashboard, screen).
-- Real FMOD playback, loop seams and loudness are E2E sound-sp.
local check = H.check
H.side(true, false)

local emitters = {}
local function newEmitter(x, y, z)
    local e = { x = x, y = y, z = z, sounds = {}, pitchCalls = 0, volCalls = 0, nextRef = 1 }
    function e:playSoundLoopedImpl(name) local r = self.nextRef; self.nextRef = r + 1; self.sounds[r] = { name = name, vol = 1 }; return r end
    function e:setVolume(r, v) self.volCalls = self.volCalls + 1; if self.sounds[r] then self.sounds[r].vol = v end end
    function e:setPitch(r, p) self.pitchCalls = self.pitchCalls + 1; self.pitch = p end
    function e:stopSound(r) self.sounds[r] = nil end
    function e:isEmpty() return next(self.sounds) == nil end
    emitters[#emitters + 1] = e
    return e
end
function getWorld() return { getFreeEmitter = function(_, x, y, z) return newEmitter(x, y, z) end } end
local slider = 10
function getCore() return { getOptionVehicleEngineVolume = function() return slider end } end

require "MinidoracatTesla/Sound"
local T = MinidoracatTesla
local S, HUD = T.Sound, T.HUD

-- ---------------------------------------------------------------- curve
H.section("sound curve")
local p0, m0, w0 = S.curve(0, 0, true)
check(m0 == 0 and w0 == 0, "standing: motor and PWS silent")
local p10, m10, w10 = S.curve(10, 0, true)
local p30, m30, w30 = S.curve(30, 0, true)
local _, m30t = S.curve(30, 1, true)
check(w10 > 0 and w30 > w10, "forward PWS gets louder with speed below 32 km/h")
check(select(3, S.curve(36, 0, true)) < w30 and select(3, S.curve(40, 0, true)) == 0, "forward PWS fades out above 32, silent by 40")
check(select(3, S.curve(10, 0, false)) == 0, "reverse: no forward PWS (backSignal plays the reverse one)")
check(m30 > m10 and m30t > m30, "motor louder with speed and with throttle")
check(p0 >= 0.5 and p10 < p30 and select(1, S.curve(300, 1, true)) == 2.0, "pitch rises with speed inside 0.5..2.0")

-- ---------------------------------------------------------------- life cycle on the dashboard update
H.section("sound life cycle")
local function tesla()
    local v = H.vehicle({ kwh = 40 })
    v.gear, v.throttle = 1, 0
    function v:getTransmissionNumber() return self.gear end
    function v:getThrottle() return self.throttle end
    function v:getHeadlightsOn() return false end
    function v:areAllDoorsLocked() return false end
    function v:isStarting() return false end
    function v:isHotwired() return false end
    return v
end
local dash = ISVehicleDashboard:new(0, 0, 552, 121)
dash.playerNum = 2
local car = tesla()
dash:setVehicle(car)
local h = HUD.get(2)
h:update()
check(#emitters == 0 and h.mtSound == nil, "motor off: no emitter taken")
car.running = true
h:update()
local s = h.mtSound
check(#emitters == 2 and s ~= nil and s.motor.e ~= s.pws.e, "motor on: two emitters, one per layer (setPitch hits every sound on an emitter)")
check(s.motor.e.x == 0 and s.motor.e.y == 0 and s.pws.e.x == 0, "emitters at (0,0): FMOD plays them 2D")
check(s.motor.e.sounds[s.motor.h].name == "MinidoracatTesla_Motor" and s.pws.e.sounds[s.pws.h].name == "MinidoracatTesla_PWSForward",
    "each emitter plays its own loop")
local maxStep = 0
for kmh = 1, 90 do
    car.speed, car.throttle = kmh, 1
    local before = s.motor.vol
    h:update()
    maxStep = math.max(maxStep, math.abs(s.motor.vol - before))
end
check(s.motor.e.pitchCalls > 0 and s.motor.e.pitchCalls <= 40, "0->90 km/h: setPitch only on >3% change (" .. s.motor.e.pitchCalls .. " calls)")
check(s.pws.e.pitchCalls == 0, "PWS emitter never gets setPitch")
check(maxStep <= 0.08 + 1e-9, "volume moves at most 0.08 per update (" .. maxStep .. ")")
for _ = 1, 20 do h:update() end
check(s.pws.vol == 0 and s.motor.vol > 0.9, "90 km/h full throttle: PWS out, motor near full")
local pc, vc = s.motor.e.pitchCalls, s.motor.e.volCalls + s.pws.e.volCalls
for _ = 1, 50 do h:update() end
check(s.motor.e.pitchCalls == pc and s.motor.e.volCalls + s.pws.e.volCalls == vc, "steady cruise: no FMOD calls at all")
slider = 0
for _ = 1, 20 do h:update() end
check(s.motor.vol == 0 and s.pws.vol == 0, "vehicle engine slider 0: both layers silent")
slider = 10
car.running = false
h:update()
check(h.mtSound == nil and s.motor.e:isEmpty() and s.pws.e:isEmpty(), "motor off: both loops stopped, emitters empty (world reclaims them)")
car.running = true
h:update()
check(#emitters == 4 and h.mtSound ~= nil, "motor on again: fresh emitters, the reclaimed ones are not reused")
local s2 = h.mtSound
dash:setVehicle(nil)
check(h.mtSound == nil and s2.motor.e:isEmpty() and s2.pws.e:isEmpty(), "leaving the seat: dashboard hide stops the layers")
h:update()
check(#emitters == 4, "on foot: dashboard update takes no emitter")
local gas = tesla()
gas.script, gas.running = "Base.CarNormal", true
dash:setVehicle(gas)
h:update()
check(#emitters == 4 and h.mtSound == nil, "running non-Tesla: no cabin layers")
dash:setVehicle(nil)
H.side(false, true)
