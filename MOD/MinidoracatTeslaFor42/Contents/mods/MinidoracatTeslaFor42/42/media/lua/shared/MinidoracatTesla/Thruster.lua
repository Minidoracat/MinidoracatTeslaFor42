-- Thrusters (Roadster Rocket, Specs `thruster`): constants, sandbox readers, the air tank, and the preconditions both
-- sides check (T.Thruster.can). The server approves and bills (server Thruster.lua), the machine holding the car's
-- physics flies it (client Thruster.lua). Design and sources: .claude/skills/tesla-dev/references/roadster2.md.
-- Air tank: battery part modData `thr = { gas = 0-1, at = world hours of the last settle, busy = { act, by, t, app =
-- the phone app's show, eng = the server started the motor for it, orphan = left in the air with nobody near } }`,
-- written by the server only. A stunt costs a full tank, boost and the soft landing a third, flying 1/FlightSeconds a
-- second; the tank refills from the pack in ThrusterRefillMinutes game minutes for ThrusterRefillKwh.
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local H = T.Thruster or {}
T.Thruster = H

H.ACTS = { kickflip = true, backflip = true, boost = true, land = true, fly = true }
H.APP = { kickflip = true, backflip = true } -- the phone app's show: the empty car, the caller outside
H.APP_RANGE = 30  -- tiles from the caller: the car must be loaded on his game, which flies it (poc/APP.md)
H.HELP_RANGE = 70 -- tiles: who takes over a car left in the air (server Thruster.lua)
-- metres about the show's car (either axis) within which a safehouse its caller may not enter refuses it
-- (H.showTrespass). A stunt from rest moves the car's middle 8.5 m at most whichever way it faces: 7.3 m ahead, inside
-- the 10 m the caller's game clears (client Thruster.lua clearPath; thrsafe-1126g tappfar), and 4.2 m aside
-- (thrsafe-1126a tkickm); its far corner is 2.4 m more
H.SHOW_REACH = 12
-- and seconds of the car's own speed more: one still rolling keeps its speed through the stunt (client Thruster.lua
-- go: no roll-up from conf.rollKmh up; the kickflip is 3.8 s in the air, PROF) and stops after it. The server reads no
-- speed of an empty car (BaseVehicle.java:4346-4354) and has it where its last update put it: the caller's machine,
-- the car's physics there, asks again as the show starts (go). A car its driver left at 28 km/h 10 m out, the show
-- asked at once: 8.7 m inside without that (thrsafe-1126m), never off the ground with it (thrsafe-1126l tapproll2)
H.SHOW_CARRY_S = 6
H.FLOOR = 2.44949 -- metres per floor: physics y / getDebugZ (flight PoC r1, BaseVehicle.java:4207)
-- seconds a flight's landing glides on at its height at most before it comes down (client Thruster.lua f.brake); the
-- server bills no more than this of it off (server Thruster.lua finish, thrustEnd's glide)
H.GLIDE_S = 4

-- per-car values; a car's Specs `thruster` table overrides any of them (Specs `thruster = {}`: all defaults)
H.DEFAULTS = {
    -- moment of inertia / mass about the body axes (m^2): f = roll (nose axis), r = pitch, u = yaw; Model S measured
    -- (flight PoC r2 IC segment). The Roadster Rocket has its own in Specs (r2int-ic: 0.300 / 1.134 / 1.285)
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
        -- a table field (inertia) given in part: the rest from DEFAULTS, not nil
        for k, d in pairs(H.DEFAULTS) do
            local x = o[k]
            if type(d) == "table" and type(x) == "table" then
                c[k] = setmetatable({}, { __index = function(_, j) local y = x[j]; if y == nil then return d[j] end return y end })
            end
        end
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
-- kWh the pack can give the tank: what it holds over its 12V floor (T.DCDC_MIN_PCT), as the server's refill pays it
-- (server Thruster.lua H.refill)
function H.packSpare(part)
    local B = T.Battery
    return math.max(0, B.kwh(part) - B.capacity(part) * T.DCDC_MIN_PCT / 100)
end
-- the pack can't pay to fill v's tank: the kWh from the settled air (thr.gas: the pack in the same part modData has
-- paid up to it) to full is more than packSpare. False on a full tank or a free refill (ThrusterRefillKwh 0)
function H.refillShort(v)
    local part = T.Battery.part(v)
    local thr = part and part:getModData().thr
    if type(thr) ~= "table" or type(thr.gas) ~= "number" then return false end
    local kwh = (1 - clamp(thr.gas, 0, 1)) * H.refillKwh()
    return kwh > 1e-9 and kwh > H.packSpare(part) + 1e-9
end

-- Where the ground is under the car, the same on both sides (the server's "off the ground", the flying machine's
-- height): the highest level at or under the car's physics origin with a floor there (a flat roof counts: flight PoC
-- r4), else 0. Optional `cached` (`...`, family pitfalls.md): the last tile and level's answer reused (the flying
-- machine, every frame; client Thruster.lua clears it at each action's start, H.groundReset: a floor built or torn
-- down since must not count). The server reads the floors every time (a dozen looks an action)
local gx, gy, gtop, gz
function H.groundReset() gx = nil end
function H.groundZ(v, ...)
    local cached = ...
    local x, y, top = math.floor(v:getX()), math.floor(v:getY()), math.floor(v:getDebugZ() + 0.01)
    if cached and x == gx and y == gy and top == gtop then return gz end
    local cell, z = getCell(), 0
    for lv = math.max(0, top), 1, -1 do
        local sq = cell:getGridSquare(x, y, lv)
        if sq and (sq:getFloor() or sq:TreatAsSolidFloor()) then z = lv break end
    end
    if cached then gx, gy, gtop, gz = x, y, top, z end
    return z
end

-- AutoDrive drives it: a summon (both sides), or the driver's own AutoDrive (its machine only, MDAD_Driver.lua:1792
-- Drive.isActive; while on it blocks other mods' addImpulse, :4119-4165)
local function autoDriven(player, vehicle)
    local api = MinidoracatAutoDriveAPI
    if type(api) == "table" and type(api.summonInfo) == "function" and api.summonInfo(vehicle) then return true end
    local D = type(MDAD) == "table" and MDAD.Drive
    return type(D) == "table" and type(D.isActive) == "function" and vehicle:isDriver(player)
        and D.isActive(player:getPlayerNum()) == true
end

-- The show's car within H.SHOW_REACH of a safehouse its caller may not walk into (SafeHouse.isSafehouseAllowTrepass,
-- SafeHouse.java:224-243; it asks by a square: the house's one nearest the car, loaded where the car is, and one not
-- loaded refuses). Nobody rides the show's car, and what keeps a car out of a safehouse (the Safehouse mod's vehicle
-- block) stops it through its driver: the empty car came down 2.29 m inside (thrsafe-1126a tapp).
function H.showTrespass(player, vehicle)
    if not SafeHouse then return false end -- the game always has it (LuaManager exposes the class); a test may not
    local x, y = vehicle:getX(), vehicle:getY()
    local r = H.SHOW_REACH + math.abs(vehicle:getCurrentSpeedKmHour()) / 3.6 * H.SHOW_CARRY_S
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local s = list:get(i)
        if x + r > s:getX() and x - r < s:getX2() and y + r > s:getY() and y - r < s:getY2() then
            local sq = getCell():getGridSquare(clamp(math.floor(x), s:getX(), s:getX2() - 1),
                clamp(math.floor(y), s:getY(), s:getY2() - 1), 0)
            if not sq or not SafeHouse.isSafehouseAllowTrepass(sq, player) then return true end
        end
    end
    return false
end

-- What refuses `act` for `player` in `vehicle`, both sides: true, or false and a deny reason
-- (IGUI_MinidoracatTesla_Deny_<reason>). The client adds what only it can see (speed, room around, physics
-- authority: client Thruster.lua); the server bills (server Thruster.lua). Optional (`...`: callers leave them out,
-- and Kahlua does not fill left-out fixed parameters with nil, family pitfalls.md): app = the phone app's show
-- (H.APP), the caller outside and the car empty; the server starts the motor itself. query = a client's look before
-- asking (VehicleManager's check, T.vmRefusal). mine = the busy flag of the action asking again (server Thruster.lua
-- stillOk): that one is no refusal, nor the air it already took.
function H.can(player, vehicle, act, ...)
    local app, query, mine = ...
    if not H.ACTS[act] or not H.conf(vehicle) or (app and not H.APP[act]) then return false, "THRUST_NONE" end
    if not H.enabled() then return false, "THRUST_OFF" end
    if app then
        if player:getVehicle() then return false, "NOT_OUTSIDE" end
        if vehicle:getDriver() then return false, "OCCUPIED" end -- the Roadster has one seat
        if player:DistTo(vehicle) > H.APP_RANGE then return false, "TOO_FAR" end
        if H.showTrespass(player, vehicle) then return false, "THRUST_SAFEHOUSE" end
    else
        if not vehicle:isDriver(player) then return false, "NOT_DRIVER" end
        -- a soft landing needs no motor: a car off in the air (its driver's own key, or a flight off since a reload)
        -- would else fall with none
        if act ~= "land" and not vehicle:isEngineRunning() then return false, "THRUST_ENGINE" end
    end
    if vehicle:getVehicleTowedBy() or vehicle:getVehicleTowing() then return false, "TOWED" end
    local part = T.Battery.part(vehicle)
    if not part or not part:getInventoryItem() then return false, "NO_PACK" end
    local md = part:getModData()
    if md.chg ~= nil then return false, "CABLE_PLUGGED" end
    local why = T.vmRefusal(player, vehicle, { "DRIVE" }, query)
    if why then return false, why end
    local thr = md.thr
    if type(thr) == "table" and thr.busy and thr.busy ~= mine then return false, "THRUST_BUSY" end
    if autoDriven(player, vehicle) then return false, "THRUST_BUSY" end
    -- someone else's game holds the car (a summon, another show, a driver): poc/APP.md step 1
    if app and vehicle:getNetPlayerId() ~= -1 then return false, "THRUST_BUSY" end
    if not mine and H.gasNow(thr, T.hours()) + 1e-9 < H.need(act) then return false, "THRUST_NO_AIR" end
    return true
end

return H
