-- Thrusters (Roadster Rocket, Specs `thruster`): constants, sandbox readers, the air tank, and the preconditions both
-- sides check (T.Thruster.can). The server approves and bills (server Thruster.lua), the driver's machine flies the car
-- (client Thruster.lua). Design and sources: .claude/skills/tesla-dev/references/roadster2.md.
-- Air tank: battery part modData `thr = { gas = 0-1, at = world hours of the last settle, busy = { act, by, t } }`,
-- written by the server only. A stunt costs a full tank, boost and the soft landing a third, flying 1/FlightSeconds a
-- second; the tank refills from the pack in ThrusterRefillMinutes game minutes for ThrusterRefillKwh.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local H = T.Thruster or {}
T.Thruster = H

H.ACTS = { kickflip = true, backflip = true, boost = true, land = true, fly = true }
H.FLOOR = 2.44949 -- metres per floor: physics y / getDebugZ (flight PoC r1, BaseVehicle.java:4207)

-- per-car values; a car's Specs `thruster` table overrides any of them (Specs `thruster = {}`: all defaults)
H.DEFAULTS = {
    -- moment of inertia / mass about the body axes (m^2): f = roll (nose axis), r = pitch, u = yaw; Model S measured
    -- (flight PoC r2 IC segment)
    inertia = { f = 0.387, r = 1.816, u = 1.897 },
    apex = 8,            -- kickflip / backflip top, metres above the ground (their timing: client Thruster.lua PROF)
    kickMaxKmh = 40,     -- the fastest each may start at: the landing spot stays near (path scan) and on screen
    flipMaxKmh = 15,
    boostMaxKmh = 60,
    rollKmh = 6,         -- below this the car first rolls forward (a parked car may ignore addImpulse, PoC r18)
    boostA = 46,         -- boost: m/s^2 along the nose until boostV m/s (0-60 mph in about 0.6 s)
    boostV = 26.8,
    flyH = 3,            -- manual flight: hover height at take-off, metres; the climb keys move it within flyMinH-flyMaxH
    flyMinH = 1,
    flyMaxH = 5,
    flyVmax = 15,        -- flight: top speed along the nose, m/s; flyAcc m/s^2 to reach it; flyYaw degrees a second
    flyAcc = 4,
    flyYaw = 60,
    flyClimb = 1.5,      -- m/s the climb keys move the hover height
    rest = 0.075,        -- floors between the ground and a parked car's physics origin when nothing better is known
}
H.COST = { kickflip = 1, backflip = 1, boost = 1 / 3, land = 1 / 3 }

-- ---- sandbox (any side; the server's copy decides) ----
local function opt(name, default)
    local s = SandboxVars and SandboxVars.MinidoracatTesla
    local v = s and s[name]
    if type(v) ~= type(default) then return default end
    return v
end
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
function H.enabled() return opt("Thrusters", true) == true end
function H.flightSeconds() return clamp(opt("FlightSeconds", 8), 2, 120) end
function H.freeFlight() return opt("FreeFlight", false) == true end
function H.refillMinutes() return clamp(opt("ThrusterRefillMinutes", 30), 1, 1440) end
function H.refillKwh() return clamp(opt("ThrusterRefillKwh", 40), 0, 150) end

-- the car's thruster values (DEFAULTS under its Specs `thruster`), or nil: no thrusters
local confs = {}
function H.conf(vehicle)
    local s = T.spec(vehicle)
    local o = s and s.thruster
    if type(o) ~= "table" then return nil end
    local c = confs[o]
    if not c then
        c = setmetatable({}, { __index = function(_, k) local x = o[k]; if x == nil then return H.DEFAULTS[k] end return x end })
        confs[o] = c
    end
    return c
end

-- air an action needs before it is approved: flying needs one second's worth (none in FreeFlight); the soft landing
-- is never refused for air (it takes what is left)
function H.need(act)
    if act == "fly" then return H.freeFlight() and 0 or 1 / H.flightSeconds() end
    if act == "land" then return 0 end
    return H.COST[act] or 1
end

-- the tank now, with the refill since `at` (a pure estimate: the server also caps it by the pack, server Thruster.lua)
function H.gasNow(thr, now)
    if type(thr) ~= "table" or type(thr.gas) ~= "number" then return 1 end -- never billed: a full tank
    local at = type(thr.at) == "number" and thr.at or now
    return clamp(thr.gas + math.max(0, now - at) * 60 / H.refillMinutes(), 0, 1)
end
-- game minutes until the tank is full again
function H.minutesToFull(gas) return math.ceil((1 - clamp(gas, 0, 1)) * H.refillMinutes()) end

-- What refuses `act` for `player` in `vehicle`, both sides: true, or false and a deny reason
-- (IGUI_MinidoracatTesla_Deny_<reason>). The client adds what only it can see (speed, room around, physics
-- authority: client Thruster.lua); the server bills (server Thruster.lua).
function H.can(player, vehicle, act)
    if not H.ACTS[act] or not H.conf(vehicle) then return false, "THRUST_NONE" end
    if not H.enabled() then return false, "THRUST_OFF" end
    if not vehicle:isDriver(player) then return false, "NOT_DRIVER" end
    if not vehicle:isEngineRunning() then return false, "THRUST_ENGINE" end
    if vehicle:getVehicleTowedBy() or vehicle:getVehicleTowing() then return false, "TOWED" end
    local part = T.Battery.part(vehicle)
    if not part or not part:getInventoryItem() then return false, "NO_PACK" end
    local md = part:getModData()
    if md.chg ~= nil then return false, "CABLE_PLUGGED" end
    local why = T.vmRefusal(player, vehicle, { "DRIVE" }, isClient())
    if why then return false, why end
    local thr = md.thr
    if type(thr) == "table" and thr.busy then return false, "THRUST_BUSY" end
    if H.gasNow(thr, T.hours()) + 1e-9 < H.need(act) then return false, "THRUST_NO_AIR" end
    return true
end

return H
