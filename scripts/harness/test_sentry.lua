-- 哨兵：開啟條件、兩級觸發、閃燈 OnTick 會移除、事件時結算、離線收件匣。
local F = dofile("scripts/harness/park_fakes.lua")
local check = (H and H.check) or function(ok, label) print((ok and "  PASS  " or "  FAIL  ") .. label); if not ok then error(label) end end

require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/Battery"
require "MinidoracatTesla/Inbox"
require "MinidoracatTesla/Sentry"
local T = MinidoracatTesla
local S = T.Sentry
T.Packs["Base.MinidoracatTesla_TestPack"] = 75

local cmds = T.ServerCommands
local function md(v) return v:getPartById("GasTank"):getModData() end

-- ---- arm: rules ----
local v = F.track(F.vehicle({ pct = 80 }))
local owner = F.player("owner", { keys = { [v.keyId] = true } })
local thief = F.player("thief")
F.online = { owner, thief }

cmds.sentryArm(thief, { vid = v:getId() })
check(md(v).sentry == nil and F.lastSent("deny").args.reason == "NOT_OWNER", "sentry: stranger cannot arm (NOT_OWNER)")
v.locked = false
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry == nil and F.lastSent("deny").args.reason == "UNLOCKED", "sentry: doors must be locked")
v.locked, v.passengers = true, 1
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry == nil and F.lastSent("deny").args.reason == "OCCUPIED", "sentry: car must be empty")
v.passengers, v.running = 0, true
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry == nil and F.lastSent("deny").args.reason == "ENGINE_ON", "sentry: engine must be off")
v.running = false
local low = F.track(F.vehicle({ pct = 19 }))
cmds.sentryArm(F.player("owner", { keys = { [low.keyId] = true } }), { vid = low:getId() })
check(md(low).sentry == nil and F.lastSent("deny").args.reason == "LOW_BATTERY", "sentry: needs >= 20%")
cmds.sentryArm(owner, { vid = v:getId() })
local s = md(v).sentry
check(s ~= nil and s.by == "owner" and s.since == F.hours and v.alarmed == false, "sentry: owner arms; vanilla alarmed cleared")
-- armed again (another key holder, the app, a double click): stays as it is, the standby since `at` still gets paid
local friend = F.player("friend", { keys = { [v.keyId] = true } })
local k0 = T.Battery.kwh(v.parts.GasTank)
F.hours = F.hours + 2
cmds.sentryArm(friend, { vid = v:getId() })
check(md(v).sentry == s and s.by == "owner" and s.at == F.hours - 2 and T.Battery.kwh(v.parts.GasTank) == k0,
    "sentry armed again by another key holder: same record, owner and clock kept, nothing settled")
T.Sentry.settle(v)
check(H.near(k0 - T.Battery.kwh(v.parts.GasTank), 2 * T.Sentry.KW, 1e-9) and s.at == F.hours,
    "the next settle charges the whole 2 h standby")

-- VehicleManager says UNCLAIMED / easy use: still not legit
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
check(T.legit(thief, v) == false, "legit: UNCLAIMED does not count")
MinidoracatVehicleManagerAPI = { canUse = function() return true, "OWNER" end }
check(T.legit(thief, v) == true, "legit: VehicleManager claimed PASSENGER counts")
MinidoracatVehicleManagerAPI = nil
-- VehicleManager decides a claimed car: this car's key, card or phone key is anyone's who picked it up (the found card
-- must not disarm sentry from the right-click menu either, like the card tap: KeyActions keyTap)
local finder = F.player("finder", { keys = { [v.keyId] = true } })
MinidoracatVehicleManagerAPI = { canUse = function() return false, "NOT_SHARED" end }
check(T.legit(finder, v) == false, "legit: this car's key on a car claimed by someone else (VehicleManager says no) does not count")
F.sent = {}
cmds.sentryDisarm(finder, { vid = v:getId() })
check(md(v).sentry ~= nil and F.lastSent("deny") and F.lastSent("deny").args.reason == "NOT_OWNER",
    "sentryDisarm with a found key on a claimed car: NOT_OWNER, sentry stays armed")
MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
check(T.legit(finder, v) == true, "legit: on an unclaimed car the key counts")
MinidoracatVehicleManagerAPI = nil

-- the owner's key left in the ignition (vanilla moves it there on start): say so, not NOT_OWNER
local parked = F.track(F.vehicle({ pct = 80 }))
parked.ignition = true
cmds.sentryArm(F.player("parker"), { vid = parked:getId() })
check(md(parked).sentry == nil and F.lastSent("deny").args.reason == "KEY_IN_IGNITION",
    "sentry: key left in the ignition -> KEY_IN_IGNITION")

-- ---- touch: stranger -> flash once + alert, OnTick removed afterwards ----
local ticksBefore = F.handlers("OnTick")
F.sent = {}
ISUnlockVehicleDoor.complete({ vehicle = v, character = thief, part = v.parts.GasTank })
ISOpenVehicleDoor.complete({ vehicle = v, character = thief, part = v.parts.GasTank })
check(S.stats.flashes == 1, "touch: unlock+open within one flash = 1 flash")
local alerts = 0
for _, m in ipairs(F.sent) do if m.cmd == "alert" then alerts = alerts + 1 end end
check(alerts == 1 and F.lastSent("alert").to == "owner" and F.lastSent("alert").args.kind == "touch",
    "touch: owner gets exactly one alert")
check(F.handlers("OnTick") == ticksBefore + 1, "flash: OnTick added while flashing")
local n = F.runTicks(100, 100)
check(F.handlers("OnTick") == ticksBefore and S.stats.tickAdds == S.stats.tickRemoves, "flash: OnTick removed after " .. n .. " ticks")
check(v.toggles >= 6 and v.headlights == false and v.parts.HeadlightLeft.lightActive == false,
    "flash: headlights toggled 3x on/off and restored off")
check(md(v).sentry ~= nil, "touch: sentry stays armed")

-- ---- break: stranger -> vanilla alarm, stays armed; owner working on the car -> nothing ----
ISSmashVehicleWindow.complete({ vehicle = v, character = thief, part = v.parts.GasTank })
check(v.alarmTriggered == 1 and md(v).sentry ~= nil, "break: alarm triggered, sentry re-armed")
check(F.lastSent("alert").args.kind == "break" and F.lastSent("alert").args.what == "window", "break: owner alerted (window)")
ISUninstallVehiclePart.complete({ vehicle = v, character = owner, part = v.parts.GasTank })
check(v.alarmTriggered == 1, "break: legit user does not trigger alarm")

-- ---- settle: drain by hours, 12V top-up, auto-off below 20% ----
local k0 = T.Battery.kwh(v.parts.GasTank)
v.parts.Battery.item.uses = 0.5
F.hours = F.hours + 10
S.settle(v)
check(math.abs(T.Battery.kwh(v.parts.GasTank) - (k0 - 10 * S.KW) + 0.5 * T.Specs["Base.MinidoracatTesla_ModelY"].v12Kwh) < 1e-6, "settle: 0.25 kW x 10 h + 12V refill charged")
check(v.parts.Battery.item.uses >= 0.99 and md(v).sentry.at == F.hours, "settle: 12V topped up, at advanced")
-- plugged into a powered charger: standby runs on the charger (Battery.onCharger), no low-battery cut-off either.
-- Sentry asks the real Charge.powerUntil when the power ended; the grid shut-off hour is pinned here.
local Charge = T.Charge
assert(Charge and Charge.powerUntil, "server Charging loaded (test_charging runs first)")
local realOff, gridOff = Charge.gridOffHour, math.huge
Charge.gridOffHour = function() return gridOff end
md(v).chg = { x = 1, y = 1, z = 0, power = "grid" }
local kc = T.Battery.kwh(v.parts.GasTank)
F.hours = F.hours + 10
S.settle(v)
check(T.Battery.kwh(v.parts.GasTank) == kc and md(v).sentry.at == F.hours, "settle on a powered charger: 10 h of standby take nothing")
T.Battery.set(v, v.parts.GasTank, 75 * 0.1)
F.hours = F.hours + 1
S.settle(v)
check(md(v).sentry ~= nil, "settle on a powered charger: a pack below 20% keeps sentry on")
-- the grid ended inside the stretch (an unloaded car past the shut-off hour; or the link cleared on load, clearChg):
-- free only up to it
local at1 = md(v).sentry.at
T.Battery.set(v, v.parts.GasTank, 60)
local k1 = T.Battery.kwh(v.parts.GasTank)
gridOff = at1 + 4
F.hours = at1 + 10
S.settle(v)
check(math.abs(T.Battery.kwh(v.parts.GasTank) - (k1 - 6 * S.KW)) < 1e-6, "grid ended 4 h into 10 h: the last 6 h come from the pack")
md(v).chg.power = "generator"
F.hours = F.hours + 5
local k2 = T.Battery.kwh(v.parts.GasTank)
S.settle(v)
check(T.Battery.kwh(v.parts.GasTank) == k2, "on a generator: free up to now (past the grid shut-off)")
-- a sentry event after the shut-off but before the charging settle updates chg.power (still "grid"), a generator
-- powering the charger square, pack below 20%: standby stays free and sentry stays on
md(v).chg.power = "grid"
T.Battery.set(v, v.parts.GasTank, 75 * 0.1)
local realGetCell = getCell
getCell = function() return { getGridSquare = function(_, x, y, z)
    return x == 1 and y == 1 and z == 0 and { haveElectricity = function() return true end } or nil end } end
local k3 = T.Battery.kwh(v.parts.GasTank)
F.hours = F.hours + 2
S.settle(v)
getCell = realGetCell
check(md(v).sentry ~= nil and T.Battery.kwh(v.parts.GasTank) == k3,
    "grid off, chg not yet updated, generator powering the charger: sentry at 10% stays on, nothing taken")
Charge.gridOffHour = realOff
T.Battery.set(v, v.parts.GasTank, 75 * 0.1)
md(v).chg.power = nil
F.hours = F.hours + 1
S.settle(v)
check(md(v).sentry == nil, "charger without power: the pack pays again and the 20% cut-off applies")
-- arming below 20% on a powered charger: allowed (the pack does not drain); without power: LOW_BATTERY
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry == nil and F.lastSent("deny").args.reason == "LOW_BATTERY", "arm at 10% on an unpowered charger: LOW_BATTERY")
md(v).chg.power = "grid"
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry ~= nil, "arm at 10% on a powered charger: armed")
md(v).chg = nil
T.Battery.set(v, v.parts.GasTank, kc)
cmds.sentryArm(owner, { vid = v:getId() })
check(md(v).sentry ~= nil, "re-armed for the next cases")

-- owner offline -> stored, pulled on login, 20 cap
F.online = { thief }
F.hours = F.hours + 1000
ISOpenVehicleDoor.complete({ vehicle = v, character = thief, part = v.parts.GasTank })
check(md(v).sentry == nil and math.abs(T.Battery.pct(v.parts.GasTank) - 20) < 1e-6, "settle: below 20% turns sentry off at the floor")
local inbox = T.Store.get("inbox")
local box = inbox.owner
check(box ~= nil and box[#box].kind == "lowBattery", "inbox: offline owner gets lowBattery stored")
check(H.moddata.MinidoracatTesla_Inbox == nil and H.gos[T.Store.SYSTEM].md.inbox == inbox,
    "inbox: in the server-only store, no Global ModData table a client could request")
for i = 1, 30 do T.Inbox.notify("owner", { kind = "touch", what = "door", i = i }) end
check(#inbox.owner == 20 and inbox.owner[20].i == 30, "inbox: keeps newest 20")
-- a split-screen guest picks its name on its own client (ConnectCoopPacket.java): it is nobody's account
local guest = F.player("owner", { num = 1 })
F.online = { thief, guest }
F.sent = {}
T.Inbox.notify("owner", { kind = "touch", what = "door", i = 31 })
check(F.lastSent("alert") == nil and #inbox.owner == 20 and inbox.owner[20].i == 31,
    "split-screen guest named like the offline owner: no live alert, the event is stored for the owner")
cmds.inboxPull(guest, {})
check(F.lastSent("inbox") == nil and #inbox.owner == 20, "split-screen guest: inboxPull gets nothing, the inbox stays")
check(T.legit(guest, v, "owner") == false, "split-screen guest: the sentry owner's name does not make it legit")
-- a guest with the key arms sentry: nobody's account to tell, but the car's alert list (the app's) still gets events
local logged, savedRemote = {}, T.Remote
T.Remote = { logAlert = function(e) logged[#logged + 1] = e end }
local gcar = F.track(F.vehicle({ pct = 80 }))
gcar.locked = true
local keyGuest = F.player("guest2", { num = 1, keys = { [gcar.keyId] = true } })
cmds.sentryArm(keyGuest, { vid = gcar:getId() })
check(md(gcar).sentry ~= nil and md(gcar).sentry.by == nil, "split-screen guest with the key arms sentry: armed, no owner account")
local boxes0 = 0
for _ in pairs(inbox) do boxes0 = boxes0 + 1 end
F.sent = {}
ISOpenVehicleDoor.complete({ vehicle = gcar, character = thief, part = gcar.parts.GasTank })
local boxes1 = 0
for _ in pairs(inbox) do boxes1 = boxes1 + 1 end
check(#logged == 1 and logged[1].kind == "touch" and F.lastSent("alert") == nil and boxes1 == boxes0,
    "...a stranger's touch: in the car's alert list, nobody notified, no inbox")
check(logged[1].by == "thief", "...naming the stranger by its account (Sentry onTouch -> Inbox.entry)")
F.runTicks(50, 450)
ISOpenVehicleDoor.complete({ vehicle = gcar, character = F.player("thief", { num = 1 }), part = gcar.parts.GasTank })
check(#logged == 2 and logged[2].by == false,
    "...a split-screen guest calling itself thief touches it: the alert says unverified, not thief's name")
T.Remote = savedRemote
F.runTicks(50, 450)
F.online = { thief }
F.sent = {}
cmds.inboxPull(owner, {})
check(F.lastSent("inbox") ~= nil and #F.lastSent("inbox").args.list == 20 and inbox.owner == nil,
    "inbox: pull delivers and clears")

-- ---- owner disarms by opening with the key ----
F.online = { owner, thief }
T.Battery.set(v, v.parts.GasTank, 75 * 0.19)
cmds.sentryArm(owner, { vid = v:getId() })
check(F.lastSent("deny").args.reason == "LOW_BATTERY", "sentry: re-arm denied below 20%")
T.Battery.set(v, v.parts.GasTank, 60)
cmds.sentryArm(owner, { vid = v:getId() })
ISOpenVehicleDoor.complete({ vehicle = v, character = owner, part = v.parts.GasTank })
check(md(v).sentry == nil, "touch: key holder opening disarms")

-- ---- client: inbox pull goes out on the first OnTick, not inside OnGameStart (family pitfalls.md
-- "MP client 不可在 OnGameStart 直接送 sendClientCommand"; tesla-sentry-1023b lost the pull this way) ----
if H and H.stub and H.clientSent then
    H.stub("ISUI/ISPanel")
    ISPanel = ISPanel or { derive = function(self) return setmetatable({}, { __index = self }) end }
    UIFont = UIFont or { Medium = 1, Small = 0 }
    local me = F.player("owner")
    local oldGSP = getSpecificPlayer
    getSpecificPlayer = function() return me end
    require "MinidoracatTesla/ParkModesUI"
    local n0 = #H.clientSent
    H.fire("OnGameStart")
    check(#H.clientSent == n0, "client: OnGameStart itself sends nothing")
    H.fire("OnTick")
    check(#H.clientSent == n0 + 1 and H.clientSent[#H.clientSent].command == "inboxPull", "client: first OnTick sends inboxPull")
    H.fire("OnTick")
    check(#H.clientSent == n0 + 1, "client: pull hook removed itself after one send")
    -- the intruder line of a card: the account the server named (Inbox.entry `by`), or "unverified" for false
    local oldTM, oldTex = getTextManager, getTexture
    getTextManager = function() return { getFontHeight = function() return 18 end, MeasureStringX = function(_, _, s) return #s end } end
    getTexture = function() return nil end
    local named = T.ParkUI.card({ kind = "touch", what = "door", by = "thief" }).detail
    local anon = T.ParkUI.card({ kind = "touch", what = "door", by = false }).detail
    local nobody = T.ParkUI.card({ kind = "lowBattery", what = "sentry" }).detail
    check(named:find("Sentry_ByPlayer", 1, true) and anon:find("Sentry_ByUnverified", 1, true)
        and not anon:find("Sentry_ByPlayer", 1, true) and nobody == nil,
        "client card: the intruder's account, \"unverified\" when the server had none, no line without an intruder")
    getTextManager, getTexture = oldTM, oldTex
    getSpecificPlayer = oldGSP
end

F.done()
