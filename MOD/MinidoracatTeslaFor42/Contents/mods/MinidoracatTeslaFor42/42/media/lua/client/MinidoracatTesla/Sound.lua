-- Cabin sound layers for the local driver of a running Tesla (design and sources: .claude/skills/tesla-dev/references/sound.md).
-- The vehicle script already plays, for everyone nearby: the low hum (engine), contactors, park brake, chimes, reverse PWS.
-- Here, only for the driver: Tesla's acceleration whine (pitch and volume follow speed and throttle) and the forward
-- pedestrian warning sound (<= 32 km/h). No polling of our own: this runs inside the Tesla dashboard's 10 Hz update
-- (HUD.lua; UIManager.java:513-521) and stops when the dashboard goes away or the motor stops.
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local HUD = T.HUD
local Sound = {}
T.Sound = Sound

local PWS_KMH, PWS_OFF_KMH = 32, 40 -- owner's manual: PWS sounds below 19 mph (32 km/h); here it fades out by 40
local STEP = 0.08                   -- most a volume moves per update: throttle is on/off on a keyboard
local PITCH_STEP = 0.03             -- relative; setPitch writes a log line per call (pitfalls.md:257-261)

-- Targets 0..1 for speed (km/h), throttle (0..1) and gear D. The clip volumes in MinidoracatTesla_sounds.txt
-- calibrate them against ModernCar (references/sound.md "音量").
function Sound.curve(kmh, throttle, forward)
    if kmh < 0.5 then return 0.5, 0, 0 end
    local pitch = math.min(2.0, 0.5 + kmh / 60)
    local motor = math.min(1, 0.25 + 0.5 * kmh / 90 + 0.25 * throttle)
    local pws = 0
    if forward then
        if kmh <= PWS_KMH then
            pws = 0.4 + 0.6 * kmh / PWS_KMH
        elseif kmh < PWS_OFF_KMH then
            pws = (PWS_OFF_KMH - kmh) / (PWS_OFF_KMH - PWS_KMH)
        end
    end
    return pitch, motor, pws
end

-- One free emitter per layer: setPitch changes every sound on its emitter (FMODSoundEmitter.java:301-319).
-- Position (0,0) makes FMOD play the file 2D (FMODSoundEmitter.java:978-979; tick :1237), so it never lags the car.
-- When the sound stops the world takes the empty emitter back (IsoWorld.java:3011-3017): drop the reference then.
local function start(name)
    local e = getWorld():getFreeEmitter(0, 0, 0)
    local h = e:playSoundLoopedImpl(name)
    e:setVolume(h, 0)
    return { e = e, h = h, vol = 0, pitch = 1 }
end

local function toward(L, target)
    local v = L.vol + math.max(-STEP, math.min(STEP, target - L.vol))
    if v ~= L.vol then
        L.vol = v
        L.e:setVolume(L.h, v)
    end
end

function Sound.stop(hud)
    local s = hud.mtSound
    if not s then return end
    s.motor.e:stopSound(s.motor.h)
    s.pws.e:stopSound(s.pws.h)
    hud.mtSound = nil
end

-- reads only what HUD:readFast already put in hud.st (gear 1 = P = motor off, 4 = D; use = throttle x10)
function Sound.update(hud)
    local st = hud.st
    if st.gear == 1 then return Sound.stop(hud) end
    local s = hud.mtSound
    if not s then
        s = { motor = start("MinidoracatTesla_Motor"), pws = start("MinidoracatTesla_PWSForward") }
        hud.mtSound = s
    end
    -- file sounds skip the volume sliders (e2e.md "靜音"), so follow the vehicle engine slider here
    local gain = getCore():getOptionVehicleEngineVolume() / 10
    local pitch, motor, pws = Sound.curve(st.kmh, st.use / 10, st.gear == 4)
    toward(s.motor, motor * gain)
    toward(s.pws, pws * gain)
    local m = s.motor
    if math.abs(pitch / m.pitch - 1) > PITCH_STEP then
        m.pitch = pitch
        m.e:setPitch(m.h, pitch)
    end
end

local origUpdate, origHide = HUD.update, HUD.hide
function HUD:update()
    origUpdate(self)
    if self.vehicle then Sound.update(self) end
end
function HUD:hide()
    Sound.stop(self)
    origHide(self)
end

return Sound
