-- Tesla Collection core: names, specs, battery readers, authorization, net helpers.
-- Every other file does require "MinidoracatTesla/Core". Battery writers live in server/MinidoracatTesla/Battery.lua.
MinidoracatTesla = MinidoracatTesla or {}
local T = MinidoracatTesla

T.MOD_ID = "MinidoracatTeslaFor42"
T.MODULE = "MinidoracatTesla"
T.BATTERY_PART = "GasTank"   -- Java requires a part with this id and content > 0 to start (VehiclePartOwner.java:84-95)
T.CONTENT_TYPE = "Electricity"

T.ServerCommands = T.ServerCommands or {}
T.ClientCommands = T.ClientCommands or {}
T.Update = T.Update or {}
T.Create = T.Create or {}
T.CheckEngine = T.CheckEngine or {}
T.CheckOperate = T.CheckOperate or {}
T.Battery = T.Battery or {}
T.ContainerAccess = T.ContainerAccess or {}

-- Energy is in kWh of game time: a kW drawn for one game hour is one kWh.
-- kwPerKmh, idleKw: a full pack (78.4 kWh) drives as far as a full vanilla CarNormal tank at 50 km/h (measured in MP:
-- about 756 km per 49 L, references/vehicle-battery.md "續航校正"). massKg (Performance curb mass) and regenEff size the regen.
T.Specs = {
    ["Base.MinidoracatTesla_ModelY"] = {
        model = "ModelY",
        idleKw = 0.0376,
        kwPerKmh = 0.00572,
        massKg = 2033,
        regenEff = 0.6,
        -- official Model Y paints (TeslaModelY, references/models.md): entry i = vehicle script skin i-1, and saved
        -- games keep the skin index (BaseVehicle.java:2635/2741), so only append. h/s/v (setColorHSV) tint the
        -- damage overlays to the paint (vehicle_common.frag.glsl:6-15), written by scripts/blender/skf/convert.py build
        -- from each skin's median paint colour; the skins themselves are full colour.
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.764, s = 0.566, v = 0.238 },
            { name = "PearlWhite", code = "PPSW", h = 0.582, s = 0.491, v = 0.865 },
            { name = "DiamondBlack", code = "PX02", h = 0.923, s = 0.549, v = 0.182 },
            { name = "Quicksilver", code = "PN00", h = 0.8, s = 0.522, v = 0.366 },
            { name = "UltraRed", code = "PR01", h = 0.996, s = 1.0, v = 0.416 },
            { name = "GlacierBlue", code = "PB01", h = 0.608, s = 0.787, v = 0.383 },
            { name = "MarineBlue", code = "PB02", h = 0.604, s = 0.832, v = 0.225 },
            { name = "FrostBlue", code = "PB00", h = 0.609, s = 0.839, v = 0.494 },
        },
    },
}

-- Pack items: exact kWh. Item MaxCapacity is an int (Item.java:2502-2503), so it is rounded up and the exact value
-- lives here. Model Y Performance: 78.4 kWh (China MIIT filing; Tesla publishes no kWh, references/vehicle-battery.md).
T.Packs = {
    ["Base.MinidoracatTesla_ModelYBattery"] = 78.4,
}

local PREFIX = "[" .. T.MOD_ID .. "] "
function T.log(msg)
    print(PREFIX .. tostring(msg))
end

function T.hours()
    return getGameTime():getWorldAgeHours() -- GameTime.java:901
end

local function sandbox(name, default)
    local s = SandboxVars and SandboxVars.MinidoracatTesla
    local v = s and s[name]
    if type(v) ~= "number" then return default end
    return v
end
function T.rangeMul() return math.max(0.25, math.min(4, sandbox("RangeMultiplier", 1))) end
function T.chargeMul() return math.max(0.1, math.min(10, sandbox("ChargeSpeedMultiplier", 1))) end
T.Camp = T.Camp or {}
-- Camp Mode low-battery limit (sandbox CampMinBattery, 10-20 %; Tesla's Low Power Mode setting has the same range)
function T.Camp.minPct() return math.max(10, math.min(20, sandbox("CampMinBattery", 20))) end

function T.spec(vehicle)
    return vehicle and T.Specs[vehicle:getScriptName()] or nil -- BaseVehicle.java:1621 (full name, :1540)
end
function T.isTesla(vehicle) return T.spec(vehicle) ~= nil end

-- ---- battery readers (any side) ----
local B = T.Battery
function B.part(vehicle)
    if not T.isTesla(vehicle) then return nil end
    local part = vehicle:getPartById(T.BATTERY_PART)
    if part and part:getContainerContentType() == T.CONTENT_TYPE then return part end
    return nil
end
-- capped at the exact pack size: vanilla repair() (admin / debug "repair", E2E probe spawns) fills the tank to the
-- item's whole-number MaxCapacity (VehiclePart.java:989-992), 79 for a 78.1 kWh pack, and nothing writes it back
-- until the next Battery.set; uncapped, that first write looked like 0.9 kWh spent on whatever it was for
function B.kwh(part) return part and math.min(part:getContainerContentAmount(), B.capacity(part)) or 0 end -- VehiclePart.java:375
function B.capacity(part)
    local item = part and part:getInventoryItem()
    if not item then return 0 end
    return T.Packs[item:getFullType()] or part:getContainerCapacity() -- VehiclePart.java:349-361
end
function B.pct(part)
    local cap = B.capacity(part)
    if cap <= 0 then return 0 end
    return math.max(0, math.min(100, B.kwh(part) * 100 / cap))
end
-- Plugged in and the charger has power (grid or a running generator, chg.power from the last settle, also while full
-- or stopped): the car's own loads (motor standby, climate, camp, 12V, sentry) run on the charger, not the pack. Model Y
-- owner's manual, Charging Instructions: "when Model Y is parked and plugged in ... it uses energy from the charging
-- equipment instead of the battery". Writers: server Battery.lua B.draw.
function B.onCharger(part)
    local chg = part and part:getModData().chg
    return chg ~= nil and chg.power ~= nil
end

-- km per kWh at the reference speed. Consumption is per game minute (like vanilla Vehicles.Update.GasTank),
-- so distance per game minute depends on DayLength: real seconds per game minute = minutesPerDay*60/1440
-- (GameTime.java:946). 1 km = 1000 tiles (getCurrentSpeedKmHour is tiles per real second * 3.6).
T.REF_KMH = 50 -- the calibration speed
function T.secPerGameMin() return getGameTime():getMinutesPerDay() * 60 / 1440 end
function T.kmPerKwh(vehicle)
    local s = T.spec(vehicle)
    if not s then return 0 end
    local kmPerMin = T.REF_KMH / 3600 * T.secPerGameMin()
    local kwhPerMin = (s.idleKw + s.kwPerKmh * T.REF_KMH) / 60
    return kmPerMin / kwhPerMin * T.rangeMul()
end
-- Charge projection between server settlements: kw * (now - last), capped at the target (architecture §4). The HUD,
-- the charge card and the phone app's record (Remote.lua) all show this, so they agree.
function B.chargeEstimate(part, chg, now)
    local cap = B.capacity(part)
    local kwh = B.kwh(part)
    local target = (chg.target or 100) * cap / 100
    local added = chg.added or 0
    if not chg.paused and chg.kw and chg.last and now > chg.last then
        local gain = math.min(chg.kw * (now - chg.last), math.max(0, target - kwh))
        kwh = kwh + gain
        added = added + gain
    end
    local hoursLeft = (chg.kw and chg.kw > 0) and math.max(0, target - kwh) / chg.kw or 0
    return kwh, added, hoursLeft, cap
end

function T.rangeKm(vehicle)
    local part = B.part(vehicle)
    if not part then return 0 end
    return B.kwh(part) * T.kmPerKwh(vehicle)
end

-- "Stopped" for Park-only actions (plug in, power off, liftgate, camp): |speed| <= 1 km/h; the HUD shows N below
-- 1 km/h too. A remote driver's speed on the server is the client-reported jniSpeed (BaseVehicle.java:4312-4316).
T.STOP_KMH = 1
function T.stopped(vehicle)
    return math.abs(vehicle:getCurrentSpeedKmHour()) <= T.STOP_KMH
end

-- GasTank checkEngine (shared: isEngineWorking runs on clients too, VehicleParts.java:167-177, e.g. the radial
-- menu's start-engine slice ISVehicleMenu.lua:88-106). Empty pack = cannot start. A plugged-in car may start (powers
-- on in Park, owner's manual "Shifting"); CheckOperate keeps it from driving off.
function T.CheckEngine.Battery(vehicle, part)
    return part:getInventoryItem() ~= nil and vehicle:hasEnoughGasToRun()
end

-- GasTank checkOperate: the local driver's input reaches the car only while this is true (BaseVehicle.java:4616-4625
-- isOperational -> CarController.updateControls, called each frame for the local driver from IsoPlayer.java:4386-4387;
-- vanilla tires have the same per-frame hook, Vehicles.CheckOperate.Tire). Plugged in = no driving: "Model Y does not
-- shift out of Park while a charge cable is plugged in" (owner's manual, Shifting). MP driving physics run on the
-- driver's client, so this is where it is stopped; the server still unplugs a car that got away (Charging checkCable).
-- Plugged in, T.onPluggedDrive (client ChargerMenu.lua) brakes the car while a pedal is down and says why; it holds
-- the input back only on the frames it renews the brake, so the controls stay live (a pedal held since before the
-- plug is braked too) and the brake key works. Cruise control presses the accelerator by itself
-- (CarController.java:242-246): switched off.
function T.CheckOperate.Battery(vehicle, part)
    if part:getModData().chg == nil then return true end
    if vehicle:isRegulator() then vehicle:setRegulator(false) end
    local f = T.onPluggedDrive
    return not (f and f(vehicle))
end

-- Frunk container test (both sides: inventory page on the client, transfers on the server). Same rule as
-- vanilla Vehicles.ContainerAccess.TruckBed (Vehicles.lua:24-34) with the frunk lid (EngineDoor) as the door.
function T.ContainerAccess.Frunk(vehicle, part, chr)
    if chr:getVehicle() then return false end
    if not vehicle:isInArea(part:getArea(), chr) then return false end
    local lid = vehicle:getPartById("EngineDoor")
    if lid and lid:getDoor() and lid:getInventoryItem() then return lid:getDoor():isOpen() end
    return true
end

-- ---- authorization ----
-- VehicleManager present: its canUse (server authoritative, client projection; MinidoracatVehicleManager_API.lua:141).
-- Otherwise: holds this car's key or the key is in the ignition (ISVehicleMenu.lua:96); the key card / phone key also
-- counts from a wallet or bag (Keys.lua; vanilla haveThisKeyId only sees loose keys and keyrings).
function T.authorized(player, vehicle, perm)
    if not player or not vehicle then return false, "NO_TARGET" end
    local api = MinidoracatVehicleManagerAPI
    if api and api.canUse then return api.canUse(player, vehicle, perm or "DRIVE", { mod = T.MODULE }) end
    if SandboxVars and SandboxVars.VehicleEasyUse then return true, "EASY_USE" end
    if vehicle:isKeysInIgnition() or player:getInventory():haveThisKeyId(vehicle:getKeyId()) then return true, "KEY" end
    if T.Keys and T.Keys.card and (T.Keys.card(player, vehicle) or T.Keys.phoneKey(player, vehicle)) then return true, "KEY" end
    return false, "NO_KEY"
end

-- Admin: same capability VehicleManager uses (MinidoracatVehicleManager_OwnershipSystem.lua:192-195).
function T.isAdmin(player)
    if not isServer() or not player or not Capability then return false end
    return checkPermissions(player, Capability.ManipulateVehicle) == true
end

-- The account a player speaks for (sentry owner, notifications, the offline inbox), or nil. On a dedicated server a
-- split-screen guest's name comes from its client unchecked (ConnectCoopPacket.java parse: only names connected right
-- now are refused) and could be any offline owner's, so only a connection's first player has one (family
-- VehicleManager OwnershipSystem.lua O.principal). SP and the client: the username.
function T.account(player)
    if not player or (isServer() and player:getPlayerNum() ~= 0) then return nil end
    return player:getUsername()
end

-- ---- server -> client ----
-- SP: sendServerCommand is a no-op off the server (LuaManager.java:8956-8960), so call the handler directly.
function T.send(player, cmd, args)
    if isServer() then
        sendServerCommand(player, T.MODULE, cmd, args or {})
    elseif not isClient() then
        local fn = T.ClientCommands[cmd]
        if fn then fn(args or {}) end
    end
end
function T.deny(player, reason, vid)
    T.send(player, "deny", { reason = reason, vid = vid })
end
-- Text of IGUI_MinidoracatTesla_Deny_<reason>; CAMP_LOW_BATTERY carries the sandbox limit as %1. A summon refused by
-- AutoDrive (Remote.lua ACT.summon) carries a whole translation key instead: AutoDrive's "UI_MinidoracatAutoDrive_...",
-- or VehicleManager's "IGUI_MVM_..." from its wrapper around startSummon. Tesla's own reasons are bare CODES.
function T.denyText(reason)
    if type(reason) == "string" and (reason:find("UI_", 1, true) == 1 or reason:find("IGUI_", 1, true) == 1) then
        return getText(reason)
    end
    local key = "IGUI_MinidoracatTesla_Deny_" .. tostring(reason)
    if reason == "CAMP_LOW_BATTERY" then return getText(key, tostring(T.Camp.minPct())) end
    return getText(key)
end

-- ---- client -> server ----
function T.request(player, cmd, args)
    sendClientCommand(player, T.MODULE, cmd, args or {}) -- SP routes to OnClientCommand too (LuaManager.java:8936-8950)
end

return T
