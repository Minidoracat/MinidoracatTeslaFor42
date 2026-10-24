--[[
Smoke harness: fake PZ globals, load the real MOD Lua, then dofile scripts/harness/test_*.lua in name order.

    lua scripts/smoke_harness.lua        (run from the repo root; plain Lua 5.x)

Each test file uses the global H (helpers below) and the real MOD tables. It is standard Lua, not Kahlua:
next/xpcall/table.sort misuse is caught by scripts/verify_mod.py, not here. Engine-only behaviour needs E2E.

Writing tests: run the path that would crash (second round, cleanup), add negative assertions for every
safety boundary, and plant a violation once to prove a new check catches it.
]]

local MEDIA = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua"

H = { failures = 0, sent = {}, clientSent = {}, logLines = {} }

-- ---------------------------------------------------------------- side, time, sandbox
local side = { client = false, server = true }
function isClient() return side.client end
function isServer() return side.server end
function H.side(client, server) side.client, side.server = client, server end -- (false,true)=MP server, (false,false)=SP

local worldHours = 1000
local nowMs = 5000000
function H.hours() return worldHours end
function H.setHours(h) worldHours = h end
function getTimestampMs() return nowMs end
function H.advanceMs(ms) nowMs = nowMs + ms end
local gameTime = {
    getWorldAgeHours = function() return worldHours end,
    getMinutesPerDay = function() return 90 end, -- DayLength default: 1 game minute = 3.75 s
}
function getGameTime() return gameTime end

SandboxVars = { MinidoracatTesla = { RangeMultiplier = 1.0, ChargeSpeedMultiplier = 1.0 },
    VehicleEasyUse = false, ZombieAttractionMultiplier = 1.0, GeneratorFuelConsumption = 0.1 }

local rand = 0.5 -- ZombRandFloat returns min + rand*(max-min)
function H.setRand(r) rand = r end
function ZombRandFloat(a, b) return a + (b - a) * rand end
function ZombRand(a, b) if b then return a + math.floor((b - a) * rand) end return math.floor(a * rand) end

function getText(key, ...) return key end
function getTextOrNull(key) return key end
-- MOD log lines (print) are kept, not shown; test output uses io.write
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end H.logLines[#H.logLines + 1] = table.concat(t, " ") end

Capability = { ManipulateVehicle = "ManipulateVehicle" }
function checkPermissions(player, cap) return player and player._admin == true end

function instanceof(o, cls) return type(o) == "table" and o._class == cls end

-- ---------------------------------------------------------------- events
local handlers = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local ev = { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
            Remove = function(fn)
                local list = handlers[name] or {}
                for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
            end }
        rawset(t, name, ev)
        return ev
    end,
})
function H.fire(name, ...)
    local list = handlers[name] or {}
    for i = 1, #list do list[i](...) end
end
function H.count(name) return #(handlers[name] or {}) end

function sendServerCommand(player, module, command, args)
    H.sent[#H.sent + 1] = { player = player, module = module, command = command, args = args }
end
function sendClientCommand(player, module, command, args)
    H.clientSent[#H.clientSent + 1] = { player = player, module = module, command = command, args = args }
end

-- ---------------------------------------------------------------- vehicles
local vehicles = {}
function getVehicleById(id) return vehicles[id and math.floor(id)] end

local function newItem(fullType, maxCap)
    local it = { fullType = fullType, maxCap = maxCap, uses = 1 }
    function it:getFullType() return self.fullType end
    function it:getMaxCapacity() return self.maxCap end
    function it:getCurrentUsesFloat() return self.uses end
    function it:setUsedDelta(v) self.uses = v end
    return it
end
H.newItem = newItem

local function newPart(id, opts)
    local p = { id = id, md = {}, item = opts.item, contentType = opts.contentType }
    function p:getId() return self.id end
    function p:getModData() return self.md end
    function p:getInventoryItem() return self.item end
    function p:getContainerContentType() return self.contentType end
    function p:getContainerCapacity() return self.item and self.item:getMaxCapacity() or 0 end
    function p:getContainerContentAmount() return self.md.contentAmount or 0 end
    function p:setContainerContentAmount(v)
        local cap = self:getContainerCapacity()
        self.md.contentAmount = math.max(0, math.min(v, cap))
    end
    function p:setRandomCondition() end
    return p
end

-- H.vehicle{ script=, kwh=, pack=(full type), running=, speed=, id=, x=, y=, z= }
local nextId = 1
function H.vehicle(o)
    o = o or {}
    local v = { id = o.id or nextId, script = o.script or "Base.MinidoracatTesla_ModelY", parts = {},
        running = o.running or false, speed = o.speed or 0, brakeSpeed = 0, transmits = 0, usedDeltaTx = 0,
        x = o.x or 100.5, y = o.y or 100.5, z = o.z or 0, good = o.good or false, keyId = 77, driver = nil, feature = nil }
    nextId = math.max(nextId, v.id) + 1
    local pack = o.pack or "Base.MinidoracatTesla_ModelYBatterySR"
    local packCap = (pack == "Base.MinidoracatTesla_ModelYBatteryLR") and 79 or 63
    v.parts.GasTank = newPart("GasTank", { contentType = "Electricity", item = (o.noPack and nil) or newItem(pack, packCap) })
    v.parts.Battery = newPart("Battery", { item = newItem("Base.CarBattery3", 0) })
    v.parts.Engine = newPart("Engine", {})
    v.parts.Heater = newPart("Heater", {})
    if o.kwh then v.parts.GasTank:setContainerContentAmount(o.kwh) end
    function v:getId() return self.id end
    function v:getScriptName() return self.script end
    function v:getPartById(id) return self.parts[id] end
    function v:getBattery() return self.parts.Battery end
    function v:isEngineRunning() return self.running end
    function v:getCurrentSpeedKmHour() return self.speed end
    function v:getBrakeSpeedBetweenUpdate() return self.brakeSpeed end
    function v:transmitPartModData() self.transmits = self.transmits + 1 end
    function v:transmitPartUsedDelta() self.usedDeltaTx = self.usedDeltaTx + 1 end
    function v:hasEnoughGasToRun() return self.parts.GasTank:getContainerContentAmount() > 0.0005 end
    function v:isGoodCar() return self.good end
    function v:isDriver(p) return self.driver == p end
    function v:getDriver() return self.driver end
    function v:getX() return self.x end
    function v:getY() return self.y end
    function v:getZ() return self.z end
    function v:getKeyId() return self.keyId end
    function v:isKeysInIgnition() return false end
    function v:setEngineFeature(q, l, f) self.feature = { q, l, f } end
    function v:setColorHSV(h, s, val) self.hsv = { h, s, val } end
    function v:transmitColorHSV() self.colorTx = (self.colorTx or 0) + 1 end
    function v:setSkinIndex(i) self.skin = i end
    function v:transmitSkinIndex() self.skinTx = (self.skinTx or 0) + 1 end
    function v:getScript() return { getEngineLoudness = function() return 20 end, getEngineForce = function() return 5000 end } end
    vehicles[v.id] = v
    return v
end
function H.removeVehicle(v) vehicles[v.id] = nil end

-- H.player{ name=, admin=, x=, y=, z=, keys={id=true} }
function H.player(o)
    o = o or {}
    local p = { name = o.name or "alice", _admin = o.admin or false, x = o.x or 100, y = o.y or 100, z = o.z or 0,
        keys = o.keys or {}, vehicle = nil, _class = "IsoPlayer" }
    function p:getUsername() return self.name end
    function p:getVehicle() return self.vehicle end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:DistTo(o2) local dx, dy = self.x - o2:getX(), self.y - o2:getY(); return math.sqrt(dx * dx + dy * dy) end
    function p:getInventory()
        local keys = self.keys
        return { haveThisKeyId = function(_, id) return keys[id] and {} or nil end }
    end
    return p
end

-- vanilla tables the MOD calls into
Vehicles = { Update = { Engine = function(v) v.vanillaEngine = (v.vanillaEngine or 0) + 1 end } }
VehicleUtils = { createPartInventoryItem = function(part) return part:getInventoryItem() end }
VehicleZoneDistribution = { parkingstall = { vehicles = {} }, good = { vehicles = {} } }

-- ---------------------------------------------------------------- loader
local loaded = {}
function require(name)
    if loaded[name] then return true end
    loaded[name] = true
    for _, dir in ipairs({ "shared", "server", "client" }) do
        local chunk = loadfile(MEDIA .. "/" .. dir .. "/" .. name .. ".lua")
        if chunk then chunk(); return true end
    end
    error("require: not found " .. name)
end
H.require = require
-- vanilla modules a test fakes itself (e.g. "Map/SGlobalObjectSystem"): mark as loaded so require skips them
function H.stub(name) loaded[name] = true end

-- ---------------------------------------------------------------- checks
function H.check(ok, label)
    if ok then io.write("  PASS  ", label, "\n")
    else H.failures = H.failures + 1; io.write("  FAIL  ", label, "\n") end
end
function H.near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
function H.section(title) io.write(title, "\n") end

-- ---------------------------------------------------------------- MOD under test (shared, then server)
for _, name in ipairs({ "MinidoracatTesla/Core", "MinidoracatTesla/API", "MinidoracatTesla/Guard", "MinidoracatTesla/Spawns",
    "MinidoracatTesla/Battery", "MinidoracatTesla/Regen", "MinidoracatTesla/Commands" }) do
    require(name)
end

-- ---------------------------------------------------------------- tests
local tests = {} -- both listers print in name order
local lister = io.popen('ls scripts/harness/test_*.lua 2>/dev/null || dir /b /on scripts\\harness\\test_*.lua 2>nul')
if lister then
    for line in lister:lines() do
        line = line:gsub("\r", "")
        if not line:find("/") and not line:find("\\") then line = "scripts/harness/" .. line end
        tests[#tests + 1] = line
    end
    lister:close()
end

for _, path in ipairs(tests) do
    io.write("== ", path, "\n")
    local ok, err = pcall(dofile, path)
    if not ok then H.failures = H.failures + 1; io.write("  FAIL  ", path, " crashed: ", tostring(err), "\n") end
end

io.write("\n")
if #tests == 0 then io.write("no tests found under scripts/harness/\n"); os.exit(1) end
if H.failures > 0 then io.write(H.failures, " failed\n"); os.exit(1) end
io.write("all passed (", #tests, " files)\n")
