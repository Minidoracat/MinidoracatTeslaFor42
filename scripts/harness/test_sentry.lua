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
local easy = SandboxVars.VehicleEasyUse
SandboxVars.VehicleEasyUse = true
check(T.legit(thief, v) == false, "legit: sandbox VehicleEasyUse without VehicleManager does not count")
SandboxVars.VehicleEasyUse = easy
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
-- vanilla "Smash Window" is ISSmashWindow(player, window, part) (ISVehiclePartMenu.lua:377); the window says whose car
-- it is. Sentry runs after the inner complete (vanilla's hit, or Armor Glass's third), so it reads the glass after the hit.
local glass = { getVehicle = function() return v end, getId = function() return "WindowFrontLeft" end }
local function window(destroyed, open)
    return { _class = "VehicleWindow", getPart = function() return glass end, isDestroyed = function() return destroyed end,
        isOpen = function() return open == true end }
end
ISSmashWindow.complete({ character = thief, window = { _class = "IsoWindow" } })
check(v.alarmTriggered == 0, "break: a house window (IsoWindow) is not a car's")
ISSmashWindow.complete({ character = thief, window = window(false, true), vehiclePart = v.parts.GasTank })
check(v.alarmTriggered == 0, "break: a window rolled down and whole was not hit (Armor Glass refuses it): no alarm")
ISSmashWindow.complete({ character = thief, window = window(false), vehiclePart = v.parts.GasTank })
check(v.alarmTriggered == 1 and md(v).sentry ~= nil, "break: a smash that leaves the glass in (Armor Glass hit 1) rings, sentry re-armed")
check(F.lastSent("alert").args.kind == "break" and F.lastSent("alert").args.what == "windowHit"
    and F.lastSent("alert").args.part == "WindowFrontLeft", "break: owner alerted (windowHit, the window's own part)")
ISSmashWindow.complete({ character = thief, window = window(true) })
check(v.alarmTriggered == 2 and F.lastSent("alert").args.what == "window", "break: the smash that breaks it rings again (window)")
ISSmashWindow.complete({ character = owner, window = window(true) })
ISUninstallVehiclePart.complete({ vehicle = v, character = owner, part = v.parts.GasTank })
check(v.alarmTriggered == 2, "break: legit user does not trigger alarm")
-- hotwired by a stranger (user 2026-10-28): a hotwired car is "the key in the ignition" for T.authorized, never for
-- T.legit, so the hotwire still rings and the thief cannot disarm sentry; Camp Mode is his once he sits in it
thief.vehicle = v -- the driver's seat (ISHotwireVehicle hooks the actor's car)
v.hotwired = true -- vanilla ISHotwireVehicle:complete has just hotwired it
ISHotwireVehicle.complete({ character = thief })
check(v.alarmTriggered == 3 and md(v).sentry ~= nil, "hotwire by a stranger: alarm rings, sentry stays armed")
check(select(2, T.authorized(thief, v, "PASSENGER")) == "HOTWIRED" and not T.legit(thief, v) and not S.canDisarm(thief, v),
    "hotwired: authorized (HOTWIRED: camp, charging) but not legit, the thief cannot disarm sentry")
check(T.Camp.canEnable(thief, v) == true, "hotwired: the seated stranger may turn Camp Mode on")
v.hotwired = false
check(select(2, T.Camp.canEnable(thief, v)) == "NOT_OWNER", "not hotwired: the seated stranger may not")
thief.vehicle = nil

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
check(T.Battery.kwh(v.parts.GasTank) == kc and md(v).sentry.at == F.hours and md(v).chg.fed == nil,
    "settle on a powered charger: 10 h of standby take nothing (grid power: no fuel to bill either)")
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
check(T.Battery.kwh(v.parts.GasTank) == k2 and math.abs((md(v).chg.fed or 0) - 5 * S.KW) < 1e-9,
    "on a generator: free to the pack up to now (past the grid shut-off); its 5 h wait in chg.fed for the generator's fuel")
md(v).chg.fed = nil
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

-- ---- windows with no event (weapons in SP, zombies, crashes): one look a game minute at the armed, loaded cars ----
local function alertsTo(name)
    local n = 0
    for _, m in ipairs(F.sent) do if m.cmd == "alert" and m.to == name then n = n + 1 end end
    return n
end
local wc = F.track(F.vehicle({ pct = 80 }))
local wOwner = F.player("wowner", { keys = { [wc.keyId] = true } })
F.online = { wOwner, thief }
cmds.sentryArm(wOwner, { vid = wc:getId() })
local ws = md(wc).sentry
check(ws ~= nil and ws.win and ws.win.Windshield == 100 and ws.win.WindowFrontLeft == 100 and ws.win.GasTank == nil
    and S.armed[wc:getId()] == true, "arm: window baseline taken (windows only), car on the scan list")
F.sent = {}
local a0 = wc.alarmTriggered
wc.parts.Windshield.cond = 60 -- a zombie or a crash took some glass: no Lua event
F.fire("EveryOneMinute")
local al = F.lastSent("alert")
check(wc.alarmTriggered == a0 + 1 and al and al.to == "wowner" and al.args.what == "windowHit"
    and al.args.part == "Windshield" and al.args.by == nil, "scan: a window lost condition -> alarm, owner alerted, nobody named")
check(ws.win.Windshield == 60, "scan: the hit is the new baseline")
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 1 and alertsTo("wowner") == 1, "scan: the same damage is not reported twice")
wc.parts.Windshield.cond, wc.parts.WindowFrontLeft.cond = 50, 0 -- a crash: two windows at once
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 2 and alertsTo("wowner") == 2 and F.lastSent("alert").args.what == "window"
    and F.lastSent("alert").args.part == "WindowFrontLeft", "scan: two windows at once -> one alert, the broken one (window)")
wc.parts.WindowFrontLeft.cond = 100 -- new glass fitted
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 2 and ws.win.WindowFrontLeft == 100, "scan: a repaired window only moves the baseline")
-- a car that is not armed is never looked at
local bare = F.track(F.vehicle({ pct = 80 }))
bare.parts.Windshield.cond = 10
F.fire("EveryOneMinute")
check(bare.alarmTriggered == 0 and S.armed[bare:getId()] == nil, "scan: an unarmed car is not on the list, no alarm")
-- MP weapon hit: a client sends vanilla damageWindow, vanilla applied it before us. Named (and a legit sender kept
-- quiet) only when trusted: the one player on its connection, on foot within reach, nobody else or no zombie near.
F.sent = {}
thief.dist, wOwner.dist = 2, 50
wc.parts.Windshield.cond = 30
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, { vehicle = wc:getId(), part = "Windshield", amount = 20 })
check(wc.alarmTriggered == a0 + 3 and F.lastSent("alert").args.by == "thief" and F.lastSent("alert").args.what == "windowHit",
    "MP damageWindow from a stranger alone at the car: alarm at once, the alert names the attacker")
check(S.lastHit[wc:getId()] and S.lastHit[wc:getId()].name == "thief" and S.lastHit[wc:getId()].p == nil,
    "the trusted hit is kept as an account name, not the player object")
wc.parts.Windshield.cond = 20 -- the server's own PlayerHitVehicle pass takes more glass, no event
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 4 and F.lastSent("alert").args.by == "thief", "scan within 2 game minutes: blamed on the same attacker")
F.hours = F.hours + 3 / 60
wc.parts.Windshield.cond = 10
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 5 and F.lastSent("alert").args.by == nil, "scan after 2 game minutes: nobody named again")
thief.dist, wOwner.dist = 50, 2
wc.parts.Windshield.cond = 5
F.fire("OnClientCommand", "vehicle", "damageWindow", wOwner, { vehicle = wc:getId(), part = "Windshield", amount = 5 })
check(wc.alarmTriggered == a0 + 5 and ws.win.Windshield == 5 and md(wc).sentry ~= nil,
    "MP damageWindow from the owner (key) alone at the car: no alarm, only the baseline moves")
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, {}) -- VehicleManager's gate refused it: args emptied
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, { vehicle = -1 }) -- ...and the id set to -1 (CommandGate.lua:271-279)
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, { vehicle = bare:getId(), part = "Windshield", amount = 5 })
check(wc.alarmTriggered == a0 + 5 and bare.alarmTriggered == 0, "damageWindow refused by VehicleManager or on an unarmed car: nothing")
F.hours = F.hours + 3 / 60
F.fire("EveryOneMinute") -- the owner's trusted hit above is older than 2 game minutes now: forgotten
-- a send that took nothing (amount 0: vanilla ignores it, VehicleWindow.java:77) names nobody and silences nothing
F.fire("OnClientCommand", "vehicle", "damageWindow", wOwner, { vehicle = wc:getId(), part = "Windshield", amount = 0 })
check(S.lastHit[wc:getId()] == nil, "zero-damage damageWindow from the owner: not kept as the last hitter")
wc.parts.Windshield.cond = 4 -- a zombie or a crash right after
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 6 and F.lastSent("alert").args.by == nil,
    "...the next window loss: alarm, nobody named (the owner's empty packet does not keep it quiet)")
-- the owner's send with a zombie at the car: may be the zombie's hit (AttackVehicleState.java:158-159) -> rings, unnamed
F.zombies[(wc.x + 1) .. "," .. wc.y] = true
wc.parts.Windshield.cond = 3
F.fire("OnClientCommand", "vehicle", "damageWindow", wOwner, { vehicle = wc:getId(), part = "Windshield", amount = 1 })
check(wc.alarmTriggered == a0 + 7 and F.lastSent("alert").args.by == nil, "damageWindow from the owner with a zombie at the car: alarm, nobody named")
F.zombies = {}
-- a split-screen pair on one connection: the server hands any send to the first player (GameServer.java:2280-2283)
local coop = F.player("coop", { num = 1 })
coop.oid, coop.dist, thief.dist, wOwner.dist = thief.oid + 1, 50, 2, 50
F.online = { wOwner, thief, coop }
wc.parts.Windshield.cond = 2
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, { vehicle = wc:getId(), part = "Windshield", amount = 1 })
check(wc.alarmTriggered == a0 + 8 and F.lastSent("alert").args.by == nil and S.lastHit[wc:getId()] == nil,
    "damageWindow from a connection with a split-screen partner: alarm, nobody named")
F.online = { wOwner, thief }
thief.dist = 30
wc.parts.Windshield.cond = 1
F.fire("OnClientCommand", "vehicle", "damageWindow", thief, { vehicle = wc:getId(), part = "Windshield", amount = 1 })
check(wc.alarmTriggered == a0 + 9 and F.lastSent("alert").args.by == nil, "damageWindow from a sender out of reach (a gun, or not the hitter): alarm, nobody named")
thief.dist, wOwner.dist = 2, 2
wc.parts.Windshield.cond = 50 -- new glass for the next cases (a higher reading only moves the baseline)
F.fire("EveryOneMinute")
a0 = wc.alarmTriggered - 5 -- the cases below count from here
-- SP: vanilla's smash breaks the glass mid-swing, our named complete comes after: a scan in between waits for it
local realServer, realQueue, realGSP, realN = isServer, ISTimedActionQueue, getSpecificPlayer, getNumActivePlayers
isServer = function() return false end
local wglass = { getVehicle = function() return wc end, getId = function() return "Windshield" end }
local smashWin = { _class = "VehicleWindow", getPart = function() return wglass end, isDestroyed = function() return true end,
    isOpen = function() return false end }
ISTimedActionQueue = { getTimedActionQueue = function() return { queue = { { Type = "ISSmashWindow", window = smashWin } } } end }
getSpecificPlayer, getNumActivePlayers = function() return thief end, function() return 1 end
F.sent = {}
wc.parts.Windshield.cond = 0
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 5 and alertsTo("wowner") == 0, "SP smash in progress: the scan waits (no nameless alert)")
ISTimedActionQueue = { getTimedActionQueue = function() return { queue = {} } end }
isServer = realServer -- the alert is caught on the MP send path
ISSmashWindow.complete({ character = thief, window = smashWin })
F.fire("EveryOneMinute")
check(wc.alarmTriggered == a0 + 6 and alertsTo("wowner") == 1 and F.lastSent("alert").args.by == "thief",
    "SP smash complete: one alert naming the smasher, the next scan adds none")
isServer, ISTimedActionQueue, getSpecificPlayer, getNumActivePlayers = realServer, realQueue, realGSP, realN
-- off the list: unloaded, disarmed, or the id now names another car (VehicleIDMap.java:49-62)
F.vehicles[wc:getId()] = nil
F.fire("EveryOneMinute")
check(S.armed[wc:getId()] == nil, "scan: an unloaded car leaves the list")
F.track(wc)
F.fire("OnSpawnVehicleEnd", wc)
check(S.armed[wc:getId()] == true, "loaded again with sentry on (OnSpawnVehicleEnd): back on the list")
local reused = F.vehicle({ pct = 80 })
reused.id = wc:getId()
F.vehicles[wc:getId()] = reused
F.fire("EveryOneMinute")
check(S.armed[wc:getId()] == nil and reused.alarmTriggered == 0, "scan: the id reused by an unarmed car: dropped, no alarm")
F.track(wc)

-- ---- towing: vanilla attachTrailer (the only way to hook up), after vanilla linked the two ----
local trailer = { id = 9001, getId = function(self) return self.id end, getScriptName = function() return "Base.TrailerCover" end }
function trailer:getVehicleTowing() return self.towing end
F.vehicles[trailer.id] = trailer
F.sent = {}
local t0 = wc.alarmTriggered
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = wc:getId(), vehicleB = trailer.id })
check(wc.alarmTriggered == t0, "attachTrailer that vanilla did not link (too far, no hitch): nothing")
wc.towing = trailer
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = wc:getId(), vehicleB = trailer.id })
check(wc.alarmTriggered == t0 + 1 and F.lastSent("alert").to == "wowner" and F.lastSent("alert").args.what == "tow"
    and F.lastSent("alert").args.by == "thief" and md(wc).sentry ~= nil, "a stranger hooks the Tesla (A) to a trailer: alarm, owner alerted (tow)")
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = wc:getId(), vehicleB = trailer.id })
check(wc.alarmTriggered == t0 + 1, "the same hook-up sent again (vanilla unhooks and hooks again, BaseVehicle.java:10047-10062): no second alarm")
local trailer2 = { id = 9002, getId = function(self) return self.id end, getScriptName = function() return "Base.Trailer" end }
F.vehicles[trailer2.id] = trailer2
wc.towing = trailer2
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = wc:getId(), vehicleB = trailer2.id })
check(wc.alarmTriggered == t0 + 2 and F.lastSent("alert").args.what == "tow", "hooked to another trailer: alarm again")
F.fire("OnClientCommand", "vehicle", "detachTrailer", thief, { vehicle = trailer2.id })
wc.towing = nil
trailer.towing = wc -- the menu swaps A and B by hitch: here the trailer side is A and pulls the Tesla
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = trailer.id, vehicleB = wc:getId() })
check(wc.alarmTriggered == t0 + 3, "after a detach, a stranger hooks it as B (towed): alarm too")
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, {})
F.fire("OnClientCommand", "vehicle", "attachTrailer", thief, { vehicleA = -1, vehicleB = -1 })
check(wc.alarmTriggered == t0 + 3, "attachTrailer refused by VehicleManager (args emptied, ids -1): nothing")
F.fire("OnClientCommand", "vehicle", "detachTrailer", wOwner, { vehicle = trailer.id })
F.fire("OnClientCommand", "vehicle", "attachTrailer", wOwner, { vehicleA = trailer.id, vehicleB = wc:getId() })
check(wc.alarmTriggered == t0 + 3 and md(wc).sentry == nil and S.tow[wc:getId()] == nil,
    "the owner hooks it up: sentry off, no alarm, the tow forgotten")
cmds.sentryArm(wOwner, { vid = wc:getId() })
local sharer = F.player("sharer")
MinidoracatVehicleManagerAPI = { canUse = function(p) return p == sharer, "SHARED" end }
F.fire("OnClientCommand", "vehicle", "attachTrailer", sharer, { vehicleA = trailer.id, vehicleB = wc:getId() })
check(wc.alarmTriggered == t0 + 3 and md(wc).sentry == nil, "someone with VehicleManager's PASSENGER right hooks it up: sentry off")
MinidoracatVehicleManagerAPI = nil
trailer.towing = nil
-- fitting glass: the part takes the item's condition (VehiclePart.java:202), a worse pane is no hit
wc.parts.Windshield.cond = 100
cmds.sentryArm(wOwner, { vid = wc:getId() })
local i0 = wc.alarmTriggered
ISUninstallVehiclePart.complete({ vehicle = wc, character = wOwner, part = wc.parts.Windshield })
wc.parts.Windshield.cond = 60
ISInstallVehiclePart.complete({ vehicle = wc, character = wOwner, part = wc.parts.Windshield })
F.fire("EveryOneMinute")
check(md(wc).sentry ~= nil and wc.alarmTriggered == i0 and md(wc).sentry.win.Windshield == 60,
    "the owner takes the windshield out and fits a 60% one: the next scan does not ring, 60 is the baseline")

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
    local tow = T.ParkUI.card({ kind = "break", what = "tow", by = "thief" })
    local scanned = T.ParkUI.card({ kind = "break", what = "windowHit", part = "Windshield" })
    check(tow and tow.title:find("Sentry_BreakTow", 1, true) and scanned
        and not (scanned.detail or ""):find("Sentry_By", 1, true),
        "client card: tow has its title; a window found by the scan names nobody")
    getTextManager, getTexture = oldTM, oldTex
    getSpecificPlayer = oldGSP
end

F.done()
