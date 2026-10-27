-- VehicleManager link: the server's R.mayTrack for a car the server doesn't have loaded (canTrackKeyId, or UNVERIFIED on
-- an older VehicleManager), and the client's VMLink (client/MinidoracatTesla/VMLink.lua): cars() keeps only Teslas,
-- the "Open Tesla App" row only on a Tesla the player carries a phone key for. Runs after test_phone_app (name order).
local F = dofile("scripts/harness/park_fakes.lua")
local check = H.check
local savedWorld = getWorld
getWorld = function() return { isHydroPowerOn = function() return true end } end
-- test_phone_app drops T.Remote when it ends: load a fresh copy, unhooked again at the end
assert(loadfile("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/Remote.lua"))()
local T = MinidoracatTesla
local K, R, cmds = T.Keys, T.Remote, T.ServerCommands

local KEY = 9301 -- never loaded here: R.loadedCar(KEY) is nil
T.Store.get("seen")[tostring(KEY)] = { car = "MinidoracatTesla_ModelY", x = 120, y = 340, z = 0, pct = 61, h = 1 }
local function phoneKey(keyId) return { ft = K.PHONE_KEY, keyId = keyId, getKeyId = function(self) return self.keyId end } end
local function inv(...)
    local items = { ... }
    return { getFirstTypeEvalArgRecurse = function(_, t, fn, arg)
        for _, it in ipairs(items) do if it.ft == t and fn(it, arg) then return it end end
    end, haveThisKeyId = function() return nil end }
end
local function player(name, ...)
    local p = { name = name, inv = inv(...) }
    function p:getUsername() return self.name end
    function p:getPlayerNum() return 0 end
    function p:getInventory() return self.inv end
    function p:getX() return 0 end
    function p:getY() return 0 end
    return p
end
local function last(cmd) local m = F.lastSent(cmd); return m and m.args end
local holder = player("holder", phoneKey(KEY))

H.section("VehicleManager link: unloaded car (R.mayTrack)")
check(R.loadedCar(KEY) == nil, "fixture: the car isn't loaded")
MinidoracatVehicleManagerAPI = nil
local st = R.state(holder, KEY)
check(st.deny == nil and st.x == 120, "no VehicleManager: the phone key is enough, last record shown")

local canUses, asked = 0, {}
local answer = { ok = false, why = "NOT_AUTHORIZED" }
MinidoracatVehicleManagerAPI = { canUse = function() canUses = canUses + 1; return true, "OWNER" end }
st = R.state(holder, KEY)
check(st.deny == "UNVERIFIED" and st.x == nil and st.pct == nil and canUses == 0,
    "older VehicleManager without canTrackKeyId: UNVERIFIED, no record (as v1)")

MinidoracatVehicleManagerAPI.canTrackKeyId = function(p, keyId)
    asked[#asked + 1] = { p = p, keyId = keyId }
    return answer.ok, answer.why
end
answer.ok, answer.why = true, "OWNER"
st = R.state(holder, KEY)
check(st.deny == nil and st.x == 120 and st.pct == 61 and asked[#asked].keyId == KEY and asked[#asked].p == holder and canUses == 0,
    "own car (VehicleManager OWNER by keyId): last record shown; asked by keyId, not canUse")
answer.ok, answer.why = true, "MEMBER"
check(R.state(holder, KEY).x == 120, "shared with TRACK (MEMBER): last record shown")
answer.ok, answer.why = false, "NOT_AUTHORIZED"
st = R.state(holder, KEY)
check(st.deny == "NOT_OWNER" and st.x == nil and st.pct == nil, "share taken back / someone else's car: NOT_OWNER, no record")
F.sent = {}
cmds.appAlerts(holder, { key = KEY })
check(last("appAlerts") and last("appAlerts").deny == "NOT_OWNER" and last("appAlerts").list == nil, "...and no alerts, told why")
answer.why = "RENT_LOCKED"
check(R.state(holder, KEY).deny == "RENT_LOCKED", "rental lock passes through (RENT_LOCKED)")
answer.ok, answer.why = true, "UNCLAIMED"
check(R.state(holder, KEY).x == 120, "unclaimed car (UNCLAIMED): the phone key is enough")
local n = #asked
F.sent = {}
cmds.appStatus(player("stranger"), { key = KEY })
check(last("appState") == nil and #asked == n, "no phone key: no answer, VehicleManager not even asked")
answer.ok, answer.why = false, "NOT_AUTHORIZED"
F.sent = {}
cmds.appStatus(holder, { key = KEY })
check(last("appState") and last("appState").deny == "NOT_OWNER", "appStatus (the 2 s poll) goes the same way")

H.section("VehicleManager link: client (VMLink)")
local V = require "MinidoracatTesla/VMLink" and T.VMLink
local owned = nil
MinidoracatVehicleManagerAPI.listOwned = function() return owned end
check(#V.cars(0) == 0, "listOwned not ready (nil): no cars")
owned = {
    { oid = "a", script = "Base.MinidoracatTesla_ModelY", keyId = KEY, name = "Blue", x = 1, y = 2, z = 0, ageMs = 5, mine = true },
    { oid = "b", script = "Base.CarNormal", keyId = 77, mine = true },
    { oid = "c", script = "Base.MinidoracatTesla_ModelY", keyId = 88, mine = false },
}
local cars = V.cars(0)
check(#cars == 2 and cars[1].oid == "a" and cars[1].keyId == KEY and cars[1].x == 1 and cars[2].oid == "c" and not cars[2].mine,
    "only Teslas, fields as VehicleManager gave them (own and shared)")
MinidoracatVehicleManagerAPI = nil
check(#V.cars(0) == 0, "no VehicleManager: {}")

local function car(script, keyId) return { getScriptName = function() return script end, getKeyId = function() return keyId end } end
local function menu() local m = { rows = {} }; function m:addOption(name, t, fn, a) self.rows[#self.rows + 1] = { name = name, t = t, fn = fn, a = a } end; return m end
local sub = menu()
V.menuHook(holder, sub, car("Base.MinidoracatTesla_ModelY", KEY))
check(#sub.rows == 1 and sub.rows[1].name == "ContextMenu_MinidoracatTesla_OpenApp" and sub.rows[1].a == KEY,
    "paired Tesla: \"Open Tesla App\" on this car's keyId")
sub = menu()
V.menuHook(holder, sub, car("Base.MinidoracatTesla_ModelY", 4444))
V.menuHook(holder, sub, car("Base.CarNormal", KEY))
V.menuHook(player("nokey"), sub, car("Base.MinidoracatTesla_ModelY", KEY))
check(#sub.rows == 0, "not shown: a Tesla this phone isn't paired with, not a Tesla, no phone key")

local savedApp, opened = T.PhoneApp, {}
T.PhoneApp = { open = function(pn, arg) opened[#opened + 1] = arg; if type(arg) == "table" then return nil end return {} end }
V.openApp(0, KEY)
check(#opened == 2 and opened[1].keyId == KEY and opened[2] == KEY, "v1 App.open (nil for the opts form): falls back to open(pn, keyId)")
opened = {}
T.PhoneApp.open = function(pn, arg) opened[#opened + 1] = arg; return {} end
V.openApp(0, KEY)
check(#opened == 1 and opened[1].keyId == KEY, "v2 App.open(pn, { keyId }): opened once")
T.PhoneApp = savedApp

MinidoracatVehicleManager = nil
V.install()
check(not V.installed, "no VehicleManager: no menu hook")
MinidoracatVehicleManager = { clientMenuHooks = { function() end } }
V.install(); V.install()
check(#MinidoracatVehicleManager.clientMenuHooks == 2 and MinidoracatVehicleManager.clientMenuHooks[2] == V.menuHook,
    "VehicleManager present: hooked once, after its own rows")
MinidoracatVehicleManager, V.installed = nil, nil
T.Store.get("seen")[tostring(KEY)] = nil
Events.OnSpawnVehicleEnd.Remove(R.onLoad)
T.Remote, getWorld = nil, savedWorld
F.done()
