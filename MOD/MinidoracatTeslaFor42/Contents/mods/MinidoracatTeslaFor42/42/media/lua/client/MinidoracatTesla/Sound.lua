-- Tesla's acceleration whine (pitch and volume follow speed and throttle) and the forward pedestrian warning sound
-- (<= 32 km/h); design and sources: .claude/skills/tesla-dev/references/sound.md. The vehicle script already plays,
-- for everyone nearby: the low hum (engine), contactors, park brake, chimes, reverse PWS.
-- Driver: two 2D layers inside the Tesla dashboard's 10 Hz update (HUD.lua; UIManager.java:513-521), stopped when the
-- dashboard goes away or the motor stops. In MP the driver also sends "motor on" when they start and every BEAT_MS,
-- "motor off" when they stop; the server relays it to players nearby (server/MinidoracatTesla/SoundRelay.lua).
-- Everyone else (passengers too): one OnTick, added while at least one car is registered and removed when the list
-- empties; it moves the emitters with the car every frame and sets volume and pitch at 10 Hz.
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local HUD = T.HUD
local Sound = {}
T.Sound = Sound

local PWS_KMH, PWS_OFF_KMH = 32, 40 -- owner's manual: PWS sounds below 19 mph (32 km/h); here it fades out by 40
local STEP = 0.08                   -- most a volume moves per update: throttle is on/off on a keyboard
local PITCH_STEP = 0.03             -- relative; setPitch writes a log line per call (pitfalls.md:257-261)
Sound.BEAT_MS = 5000                -- driver: "motor on" again this often while the layers play
Sound.HEARD_MS = 12000              -- listener: a car without a beat for this long goes quiet (two beats missed)
Sound.EXT_MAX = 30                  -- = distanceMax of the *Ext sounds; FMOD's inverse rolloff stops falling there
Sound.stats = { sent = 0, beats = 0, tickAdds = 0, tickRemoves = 0, playing = 0 }

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
-- Position (0,0) makes FMOD play the file 2D (FMODSoundEmitter.java:978-979; tick :1237); anywhere else a 3D sound
-- gets the listener's distance, occlusion and the clip's distanceMin/Max (:1249-1292, :1356).
-- When the sound stops the world takes the empty emitter back (IsoWorld.java:3011-3017): drop the reference then.
local function start(name, x, y, z)
    local e = getWorld():getFreeEmitter(x, y, z) -- IsoWorld.java:472-476
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

local function pitchTo(L, pitch)
    if math.abs(pitch / L.pitch - 1) > PITCH_STEP then
        L.pitch = pitch
        L.e:setPitch(L.h, pitch)
    end
end

-- file sounds skip the volume sliders (e2e.md "靜音"), so follow the vehicle engine slider here
local function gain() return getCore():getOptionVehicleEngineVolume() / 10 end

-- ---------------------------------------------------------------- the driver
local function beat(s, on)
    Sound.stats.sent = Sound.stats.sent + 1
    T.request(s.p, "motor", { vid = s.vid, on = on })
end

function Sound.stop(hud)
    local s = hud.mtSound
    if not s then return end
    s.motor.e:stopSound(s.motor.h)
    s.pws.e:stopSound(s.pws.h)
    hud.mtSound = nil
    if s.beatAt then beat(s, false) end
end

-- reads only what HUD:readFast already put in hud.st (gear 1 = P = motor off, 4 = D; use = throttle x10)
function Sound.update(hud)
    local st = hud.st
    if st.gear == 1 then return Sound.stop(hud) end
    local s = hud.mtSound
    if not s then
        s = { motor = start("MinidoracatTesla_Motor", 0, 0, 0), pws = start("MinidoracatTesla_PWSForward", 0, 0, 0),
            vid = hud.vehicle:getId(), p = hud.character }
        hud.mtSound = s
    end
    if isClient() then -- MP only: SP has no one else to tell
        local now = getTimestampMs()
        if not s.beatAt or now - s.beatAt >= Sound.BEAT_MS then
            s.beatAt = now
            beat(s, true)
        end
    end
    local g = gain()
    local pitch, motor, pws = Sound.curve(st.kmh, st.use / 10, st.gear == 4)
    toward(s.motor, motor * g)
    toward(s.pws, pws * g)
    pitchTo(s.motor, pitch)
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

-- ---------------------------------------------------------------- everyone else (MP)
-- vid -> { vid, exp, v, inside, motor, pws }. A car stays registered while it is unloaded, out of earshot, parked
-- with the motor off or without a driver (a fast car crosses the relay radius between two beats; the "on" can
-- arrive before the engine state): only "off" or the expiry drop it.
local heard, nHeard = {}, 0
Sound.heard = heard
local tick
local drop = {}
local nextAt = 0
local EXT_MAX2 = Sound.EXT_MAX * Sound.EXT_MAX

local function silence(e)
    if not e.motor then return end
    e.motor.e:stopSound(e.motor.h)
    e.pws.e:stopSound(e.pws.h)
    e.motor, e.pws = nil, nil
    Sound.stats.playing = Sound.stats.playing - 1
end

local function forget(vid)
    local e = heard[vid]
    if not e then return end
    silence(e)
    heard[vid] = nil
    nHeard = nHeard - 1
    if nHeard == 0 then
        Events.OnTick.Remove(tick)
        Sound.stats.tickRemoves = Sound.stats.tickRemoves + 1
    end
end

-- 10 Hz per car. Remote clients get the signed speed from the position updates (VehicleManager.java:233) and the
-- engine state (network/fields/vehicle/VehicleEngine.java:42-43); the throttle is applied on the server only
-- (VehiclePhysicsPacket.java:146-171), so the curve gets 0 for it.
local function refresh(e, me)
    local v = getVehicleById(e.vid)
    local drv = v and v:getDriver()
    if not drv or drv == me or not v:isEngineRunning() then return silence(e) end
    local inside = me:getVehicle() == v
    local dx, dy = v:getX() - me:getX(), v:getY() - me:getY()
    local far = not inside and dx * dx + dy * dy > EXT_MAX2
    if e.motor and e.inside ~= inside then silence(e) end
    if not e.motor then
        if far then return end
        -- passengers hear the cabin layers in 2D like the driver; outside, the *Ext sounds sit on the car in 3D
        if inside then
            e.motor, e.pws = start("MinidoracatTesla_Motor", 0, 0, 0), start("MinidoracatTesla_PWSForward", 0, 0, 0)
        else
            local x, y, z = v:getX(), v:getY(), v:getZ()
            e.motor, e.pws = start("MinidoracatTesla_MotorExt", x, y, z), start("MinidoracatTesla_PWSForwardExt", x, y, z)
        end
        e.inside = inside
        Sound.stats.playing = Sound.stats.playing + 1
    end
    e.v = v
    local speed = v:getCurrentSpeedKmHour()
    local g = far and 0 or gain()
    local pitch, motor, pws = Sound.curve(math.abs(speed) * BaseVehicle.getFakeSpeedModifier(), 0, speed > 0)
    toward(e.motor, motor * g)
    toward(e.pws, pws * g)
    if far and e.motor.vol == 0 and e.pws.vol == 0 then return silence(e) end
    pitchTo(e.motor, pitch)
end

tick = function()
    local now = getTimestampMs()
    if now >= nextAt then
        nextAt = now + 100
        local me = getSpecificPlayer(0)
        for vid, e in pairs(heard) do
            if now > e.exp then drop[#drop + 1] = vid
            elseif me then refresh(e, me) end
        end
        for i = #drop, 1, -1 do
            forget(drop[i])
            drop[i] = nil
        end
    end
    for _, e in pairs(heard) do
        if e.motor and not e.inside then
            local v = e.v
            local x, y, z = v:getX(), v:getY(), v:getZ()
            e.motor.e:setPos(x, y, z) -- FMODSoundEmitter.java:74-78, read by the emitter tick every 30 ms
            e.pws.e:setPos(x, y, z)
        end
    end
end

T.ClientCommands = T.ClientCommands or {}
T.ClientCommands.motor = function(args)
    local vid = args.vid
    if type(vid) ~= "number" then return end
    if not args.on then return forget(vid) end
    Sound.stats.beats = Sound.stats.beats + 1
    local e = heard[vid]
    if not e then
        e = { vid = vid }
        heard[vid] = e
        nHeard = nHeard + 1
        if nHeard == 1 then
            Events.OnTick.Add(tick)
            Sound.stats.tickAdds = Sound.stats.tickAdds + 1
        end
    end
    e.exp = getTimestampMs() + Sound.HEARD_MS
end

return Sound
