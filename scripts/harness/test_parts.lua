-- EV parts: power by pack, DC-DC at spawn, charge kept across pack uninstall/install, brake wear, frunk access,
-- mechanics-window names. Engine-side behaviour (script merge, item capacity, real UI) is in E2E parts-sp.
local T, B = MinidoracatTesla, MinidoracatTesla.Battery
local check, near = H.check, H.near
H.side(false, true)
local SR, LR = "Base.MinidoracatTesla_ModelYBatterySR", "Base.MinidoracatTesla_ModelYBatteryLR"

H.section("motor power by pack")
local sr = H.vehicle({ kwh = 30 })
T.Create.Motor(sr, sr:getPartById("Engine"))
local lr = H.vehicle({ pack = LR, kwh = 30 })
T.Create.Motor(lr, lr:getPartById("Engine"))
check(sr.feature[3] == 3000 and lr.feature[3] == 5000, "SR 3000 (300 hp), LR 5000 (500 hp)")
local np = H.vehicle({})
np.parts.GasTank.item = nil
T.Create.Motor(np, np:getPartById("Engine"))
check(np.feature[3] == 5000, "no pack item: script engineForce")

H.section("DC-DC at spawn")
Vehicles.Create = Vehicles.Create or {}
Vehicles.Create.Battery = function(v, part) part:getInventoryItem():setUsedDelta(0.2) end -- an old, drained 12V
local sv = H.vehicle({ kwh = 30 })
T.Create.Battery12V(sv, sv:getBattery())
check(near(sv:getBattery():getInventoryItem():getCurrentUsesFloat(), 1) and near(B.kwh(B.part(sv)), 30 - 0.8 * T.V12_KWH),
    "12V created after the pack: topped up from the pack")
local dead = H.vehicle({ kwh = 62.5 * 0.04 })
T.Create.Battery12V(dead, dead:getBattery())
check(near(dead:getBattery():getInventoryItem():getCurrentUsesFloat(), 0.2), "pack below 5%: 12V keeps its vanilla charge")
local early = H.vehicle({ kwh = 0 })
early:getBattery():getInventoryItem():setUsedDelta(0.3)
H.setRand(0.5)
T.Create.Battery(early, B.part(early))
check(near(early:getBattery():getInventoryItem():getCurrentUsesFloat(), 1), "12V created before the pack: pack create tops it up")
check(near(T.V12_KWH, 0.10695), "12V is 15.5 V x 6.9 Ah = 0.107 kWh")

H.section("pack uninstall / install keeps the charge")
local rv = H.vehicle({ pack = LR, kwh = 78.1 * 0.5 })
local rp = B.part(rv)
local item = rp:getInventoryItem()
local stored = B.kwh(rp)                       -- ISUninstallVehiclePart: item:setItemCapacity(content)
rp.md.sentKwh = stored                         -- last value sent before the pack came out
rp.item = nil; rp.md.contentAmount = 0         -- setInventoryItem(nil) -> content 0
rp.item = item; rp:setContainerContentAmount(stored) -- install: doInventoryItemStats restores it
local tx = rv.transmits
T.InstallComplete.Battery(rv, rp)
check(near(B.pct(rp), 50) and rv.transmits == tx + 1, "install complete: still 50%, part modData sent")
rp.item = nil; rp.md.contentAmount = 0
rp.item = item; rp:setContainerContentAmount(82.1) -- an old 82.1 kWh LR item: engine clamps to int 79
T.InstallComplete.Battery(rv, rp)
check(B.kwh(rp) == 78.1, "install complete clamps to the exact 78.1 kWh")

H.section("brake wear x0.5")
local wear = 0
Vehicles.Update.Brakes = function() wear = wear + 1 end
local bv = H.vehicle({})
H.setRand(0.49); T.Update.Brakes(bv, {}, 1)
H.setRand(0.5); T.Update.Brakes(bv, {}, 1)
check(wear == 1 and T.BRAKE_WEAR == 0.5, "vanilla brake wear runs when the 0..1 roll < 0.5 only")
H.setRand(0.5)

H.section("frunk access")
local lid = { open = false, item = true }
local fv = H.vehicle({})
fv.parts.EngineDoor = { getDoor = function() return { isOpen = function() return lid.open end } end,
    getInventoryItem = function() return lid.item end }
function fv:isInArea(area, chr) return chr.near end
local frunk = { getArea = function() return "Engine" end }
local chr = { near = true, getVehicle = function(self) return self.inCar end }
check(T.ContainerAccess.Frunk(fv, frunk, chr) == false, "lid closed: no access")
lid.open = true
check(T.ContainerAccess.Frunk(fv, frunk, chr) == true, "lid open: access")
lid.open, lid.item = false, nil
check(T.ContainerAccess.Frunk(fv, frunk, chr) == true, "lid removed: access")
chr.near = false
check(T.ContainerAccess.Frunk(fv, frunk, chr) == false, "outside the Engine area: no access")
chr.near, chr.inCar = true, fv
check(T.ContainerAccess.Frunk(fv, frunk, chr) == false, "sitting in a car: no access")

H.section("mechanics window names")
H.stub("Vehicles/ISUI/ISVehicleMechanics")
H.stub("Vehicles/ISUI/ISVehicleMenu")
ISVehicleMechanics = {
    initParts = function(self) self.names = { getText("IGUI_VehiclePartGasTank"), getText("IGUI_VehiclePartTruckBed") } end,
    render = function(self) if self.boom then error("boom") end return getText("Tooltip_outoffuel") end,
}
ISVehicleMenu = { showRadialMenuOutside = function(p) p.label = getText("IGUI_OpenHood") end,
    getVehicleToInteractWith = function(p) return p.target end }
local vanillaGetText = getText
require "MinidoracatTesla/PartNames"
local tw = { vehicle = H.vehicle({}) }
ISVehicleMechanics.initParts(tw)
check(tw.names[1] == "IGUI_MinidoracatTesla_Part_GasTank" and tw.names[2] == "IGUI_VehiclePartTruckBed",
    "Tesla: GasTank shows the EV name, unmapped parts keep vanilla keys")
check(ISVehicleMechanics.render(tw) == "IGUI_MinidoracatTesla_OutOfCharge", "Tesla: empty pack says out of charge")
local vw = { vehicle = H.vehicle({ script = "Base.CarNormal" }) }
ISVehicleMechanics.initParts(vw)
check(vw.names[1] == "IGUI_VehiclePartGasTank" and getText == vanillaGetText, "vanilla car: vanilla names, getText restored")
tw.boom = true
check(not pcall(ISVehicleMechanics.render, tw) and getText == vanillaGetText, "error inside: getText still restored")
local p = { target = H.vehicle({}), getVehicle = function() return nil end }
ISVehicleMenu.showRadialMenuOutside(p)
check(p.label == "IGUI_MinidoracatTesla_OpenFrunk", "outside radial: Open Frunk on a Tesla")
local mapped = 0
for _ in pairs(T.PartNames) do mapped = mapped + 1 end
check(mapped == 14, "14 vanilla keys mapped (5 parts, category, out of charge, 3 engine labels, 4 hood actions)")

H.section("cargo capacities (vehicle template)")
-- 2025+ owner's manual: trunk 835 L behind the 2nd row, frunk 114 L. Trunk anchored to vanilla SUV (NormalTrunk2 85).
local tf = assert(io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/scripts/vehicles/MinidoracatTesla_template.txt", "r"))
local tpl = tf:read("*a")
tf:close()
local function partCapacity(id)
    local body = tpl:match("\n        part " .. id .. "\n        {(.-)\n        }")
    return body and tonumber(body:match("capacity%s*=%s*(%d+)"))
end
local trunk, frunkCap = partCapacity("TruckBed"), partCapacity("Frunk")
check(trunk == 85, "TruckBed capacity override 85 (vanilla SUV trunk), not the sedan NormalTrunk3 45 (" .. tostring(trunk) .. ")")
check(frunkCap == 12, "Frunk capacity 12 (" .. tostring(frunkCap) .. ")")
check(trunk and frunkCap and math.abs(frunkCap - trunk * 114 / 835) < 0.5, "frunk / trunk follows 114 L / 835 L")
