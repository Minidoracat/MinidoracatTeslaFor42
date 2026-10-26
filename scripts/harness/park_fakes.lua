-- Fakes for test_sentry.lua / test_camp.lua (not a test file itself: no test_ prefix).
-- Only the engine surface Sentry/Camp/Inbox/ParkModes and TeslaLogic's Battery writers touch.
-- Globals are installed only when the harness did not provide them.
local F = {}

F.ms = 0
F.hours = 100
F.logs = {}
F.sent = {}

local function ensure(name, value) if _G[name] == nil then _G[name] = value end end
-- Globals replaced outright are restored by F.done() so later harness tests see the originals.
local saved = {}
local function set(name, value)
    if saved[name] == nil then saved[name] = { v = _G[name] } end
    _G[name] = value
end
function F.done()
    for name, s in pairs(saved) do _G[name] = s.v end
end

-- Events: the smoke harness provides Events/H.fire/H.count; standalone runs get a minimal copy.
if not (H and H.fire) then
    local handlers = {}
    Events = setmetatable({}, { __index = function(t, name)
        local ev = { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
            Remove = function(fn)
                local list = handlers[name] or {}
                for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
            end }
        rawset(t, name, ev)
        return ev
    end })
    H = H or {}
    function H.fire(name, ...) local list = handlers[name] or {} for i = #list, 1, -1 do if list[i] then list[i](...) end end end
    function H.count(name) return #(handlers[name] or {}) end
end
F.fire, F.handlers = H.fire, H.count

if getTimestampMs == nil then getTimestampMs = function() return F.ms end end
function F.advance(ms) if H.advanceMs then H.advanceMs(ms) else F.ms = F.ms + ms end end
set("isClient", function() return false end) -- dedicated-server path: T.send uses sendServerCommand
set("isServer", function() return true end)
ensure("SandboxVars", {})
local gt = {
    getWorldAgeHours = function() return F.hours end,
    getHour = function() return 18 end,
    getMinutes = function() return 42 end,
}
set("getGameTime", function() return gt end) -- tests drive the clock

local moddata = {}
ModData = ModData or {}
ModData.getOrCreate = ModData.getOrCreate or function(k) moddata[k] = moddata[k] or {}; return moddata[k] end

-- Java ArrayList stand-in
function F.list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end
F.online = {}
set("getOnlinePlayers", function() return F.list(F.online) end)

-- server -> client capture (MP path of MinidoracatTesla.send)
set("sendServerCommand", function(player, module, cmd, args)
    F.sent[#F.sent + 1] = { to = player and player:getUsername(), module = module, cmd = cmd, args = args }
end)

VehicleUtils = VehicleUtils or {}
VehicleUtils.compareFloats = VehicleUtils.compareFloats or function(a, b, p)
    local m = 10 ^ p
    return math.floor(a * m + 0.5) ~= math.floor(b * m + 0.5)
end
Vehicles = Vehicles or {}
Vehicles.Update = Vehicles.Update or {}
Vehicles.Update.Battery = Vehicles.Update.Battery or function() end

-- Vanilla timed action classes (Sentry.lua wraps complete() at load time).
local function action(name)
    local cls = _G[name] or {}
    cls.complete = cls.complete or function() return true end
    _G[name] = cls
end
for _, n in ipairs({ "ISOpenVehicleDoor", "ISUnlockVehicleDoor", "ISSmashVehicleWindow", "ISHotwireVehicle",
    "ISUninstallVehiclePart" }) do action(n) end

-- ------------------------------------------------------------------ parts, vehicle, player
local function part(id, opts)
    local p = { id = id, md = {}, amount = opts.amount or 0, cap = opts.cap or 0, ctype = opts.ctype,
        item = opts.item, lightActive = false, hasLight = opts.light }
    function p:getId() return self.id end
    function p:getModData() return self.md end
    function p:getContainerContentType() return self.ctype end
    function p:getContainerContentAmount() return self.amount end
    function p:setContainerContentAmount(v) self.amount = v end
    function p:getContainerCapacity() return self.cap end
    function p:getInventoryItem() return self.item end
    function p:setLightActive(on) self.lightActive = on end
    return p
end

local function drainable(full, uses)
    local it = { full = full, uses = uses or 1 }
    function it:getFullType() return self.full end
    function it:getCurrentUsesFloat() return self.uses end
    function it:setUsedDelta(v) self.uses = v end
    return it
end

local nextId = 1
-- o: { pct=, cap=, running=, passengers=, locked=, keyId= }
function F.vehicle(o)
    o = o or {}
    local cap = o.cap or 75
    local v = { id = nextId, keyId = o.keyId or (500 + nextId), running = o.running or false,
        passengers = o.passengers or 0, locked = o.locked ~= false, headlights = false, alarmed = true,
        alarmTriggered = 0, needParts = false, transmits = 0, x = 1000, y = 2000 }
    nextId = nextId + 1
    v.parts = {
        GasTank = part("GasTank", { ctype = "Electricity", cap = cap, amount = cap * (o.pct or 80) / 100,
            item = drainable("Base.MinidoracatTesla_TestPack") }),
        Battery = part("Battery", { item = drainable("Base.CarBattery1", o.v12 or 1) }),
        Heater = part("Heater", {}), -- vanilla template_heater.txt has no itemType: no inventory item
        PassengerCompartment = part("PassengerCompartment", {}),
        HeadlightLeft = part("HeadlightLeft", { light = true }),
        HeadlightRight = part("HeadlightRight", { light = true }),
    }
    v.lights = { v.parts.HeadlightLeft, v.parts.HeadlightRight }
    function v:getId() return self.id end
    function v:getScriptName() return "Base.MinidoracatTesla_ModelY" end
    function v:getScript() return { getCarModelName = function() return nil end, getName = function() return "MinidoracatTesla_ModelY" end } end
    function v:getPartById(id) return self.parts[id] end
    function v:getBattery() return self.parts.Battery end
    function v:isEngineRunning() return self.running end
    function v:getCurrentSpeedKmHour() return self.kmh or 0 end
    function v:shutOff() -- vanilla: ShuttingDown switches the heater off on the spot (BaseVehicle.java:7469-7473)
        self.running, self.shutOffs = false, (self.shutOffs or 0) + 1
        self.parts.Heater:getModData().active = false
    end
    function v:hasPassenger() return self.passengers > 0 end
    function v:areAllDoorsLocked() return self.locked end
    function v:getKeyId() return self.keyId end
    function v:isKeysInIgnition() return self.ignition == true end
    function v:getX() return self.x end
    function v:getY() return self.y end
    function v:setAlarmed(b) self.alarmed = b end
    function v:triggerAlarm()
        if self.alarmed then self.alarmTriggered = self.alarmTriggered + 1 end
        self.alarmed = false
    end
    function v:transmitAlarmed() end
    function v:getHeadlightsOn() return self.headlights end
    function v:setHeadlightsOn(b)
        if b ~= self.headlights then self.toggles = (self.toggles or 0) + 1 end
        self.headlights = b
    end
    function v:getLightCount() return #self.lights end
    function v:getLightByIndex(i) return self.lights[i + 1] end
    function v:setNeedPartsUpdate(b) self.needParts = b end
    function v:transmitPartModData() self.transmits = self.transmits + 1 end
    function v:transmitPartUsedDelta() end
    return v
end

function F.player(name, o)
    o = o or {}
    local p = { name = name, vehicle = o.vehicle, keys = o.keys or {}, dist = o.dist or 2 }
    function p:getUsername() return self.name end
    function p:getVehicle() return self.vehicle end
    function p:DistTo() return self.dist end
    function p:getInventory()
        local keys = self.keys
        return { haveThisKeyId = function(_, id) return keys[id] and {} or nil end }
    end
    return p
end

F.vehicles = {}
set("getVehicleById", function(id) return F.vehicles[id] end)
function F.track(v) F.vehicles[v:getId()] = v; return v end

function F.lastSent(cmd)
    for i = #F.sent, 1, -1 do if F.sent[i].cmd == cmd then return F.sent[i] end end
end

-- Run the flash OnTick until it removes itself (or give up).
function F.runTicks(maxTicks, stepMs)
    local n = 0
    while F.handlers("OnTick") > 0 and n < maxTicks do
        F.advance(stepMs or 100)
        F.fire("OnTick")
        n = n + 1
    end
    return n
end

return F
