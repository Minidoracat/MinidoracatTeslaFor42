-- EV parts: motor power, DC-DC at spawn, charge kept across pack uninstall/install, brake wear, frunk access,
-- mechanics-window names. Engine-side behaviour (script merge, item capacity, real UI) is in E2E parts-sp.
local T, B = MinidoracatTesla, MinidoracatTesla.Battery
local check, near = H.check, H.near
H.side(false, true)

H.section("motor power")
local mv = H.vehicle({ kwh = 30 })
T.Create.Motor(mv, mv:getPartById("Engine"))
local np = H.vehicle({})
np.parts.GasTank.item = nil
T.Create.Motor(np, np:getPartById("Engine"))
check(mv.feature[3] == 6260 and np.feature[3] == 6260, "script engineForce 6260 (626 hp), with or without a pack item")

H.section("DC-DC at spawn")
Vehicles.Create = Vehicles.Create or {}
Vehicles.Create.Battery = function(v, part) part:getInventoryItem():setUsedDelta(0.2) end -- an old, drained 12V
local sv = H.vehicle({ kwh = 30 })
T.Create.Battery12V(sv, sv:getBattery())
check(near(sv:getBattery():getInventoryItem():getCurrentUsesFloat(), 1) and near(B.kwh(B.part(sv)), 30 - 0.8 * T.V12_KWH),
    "12V created after the pack: topped up from the pack")
local dead = H.vehicle({ kwh = 78.4 * 0.04 })
T.Create.Battery12V(dead, dead:getBattery())
check(near(dead:getBattery():getInventoryItem():getCurrentUsesFloat(), 0.2), "pack below 5%: 12V keeps its vanilla charge")
local early = H.vehicle({ kwh = 0 })
early:getBattery():getInventoryItem():setUsedDelta(0.3)
H.setRand(0.5)
T.Create.Battery(early, B.part(early))
check(near(early:getBattery():getInventoryItem():getCurrentUsesFloat(), 1), "12V created before the pack: pack create tops it up")
check(near(T.V12_KWH, 0.10695), "12V is 15.5 V x 6.9 Ah = 0.107 kWh")

H.section("pack uninstall / install keeps the charge")
local rv = H.vehicle({ kwh = 78.4 * 0.5 })
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
rp.item = item; rp:setContainerContentAmount(79) -- a full pack item: engine clamps to the int MaxCapacity 79
T.InstallComplete.Battery(rv, rp)
check(B.kwh(rp) == 78.4, "install complete clamps to the exact 78.4 kWh")

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
H.stub("ISUI/ISInventoryPage")
ISVehicleMechanics = {
    initParts = function(self) self.names = { getText("IGUI_VehiclePartGasTank"), getText("IGUI_VehiclePartGloveBox"),
        getText("IGUI_VehiclePartTrunkDoor") } end,
    render = function(self) if self.boom then error("boom") end return getText("Tooltip_outoffuel") end,
}
ISVehicleMenu = { showRadialMenuOutside = function(p) p.label = getText("IGUI_OpenHood") end,
    getVehicleToInteractWith = function(p) return p.target end }
ISInventoryPage = { addContainerButton = function(self, container, texture, name, tooltip) return { name = name, tooltip = tooltip } end }
local vanillaGetText = getText
require "MinidoracatTesla/PartNames"
local tw = { vehicle = H.vehicle({}) }
ISVehicleMechanics.initParts(tw)
check(tw.names[1] == "IGUI_MinidoracatTesla_Part_GasTank" and tw.names[2] == "IGUI_VehiclePartGloveBox",
    "Tesla: GasTank shows the EV name, unmapped parts keep vanilla keys")
check(tw.names[3] == "IGUI_MinidoracatTesla_Part_TrunkDoor", "Model Y: TrunkDoor shows the liftgate")
local m3w = { vehicle = H.vehicle({ script = "Base.MinidoracatTesla_Model3" }) }
ISVehicleMechanics.initParts(m3w)
check(m3w.names[1] == "IGUI_MinidoracatTesla_Part_GasTank" and m3w.names[3] == "IGUI_MinidoracatTesla_Part_TrunkLid",
    "Model 3: the shared EV names, and TrunkDoor shows the trunk lid (T.CarPartNames)")
check(ISVehicleMechanics.render(tw) == "IGUI_MinidoracatTesla_OutOfCharge", "Tesla: empty pack says out of charge")
local vw = { vehicle = H.vehicle({ script = "Base.CarNormal" }) }
ISVehicleMechanics.initParts(vw)
check(vw.names[1] == "IGUI_VehiclePartGasTank" and getText == vanillaGetText, "vanilla car: vanilla names, getText restored")
tw.boom = true
check(not pcall(ISVehicleMechanics.render, tw) and getText == vanillaGetText, "error inside: getText still restored")
local p = { target = H.vehicle({}), getVehicle = function() return nil end }
ISVehicleMenu.showRadialMenuOutside(p)
check(p.label == "IGUI_MinidoracatTesla_OpenFrunk", "outside radial: Open Frunk on a Tesla")
local function container(v, id)
    local part = { getId = function() return id end, getVehicle = function() return v end }
    return { getVehiclePart = function() return part end }
end
local function button(c, name) return ISInventoryPage.addContainerButton({}, c, nil, name, name) end
local b = button(container(H.vehicle({}), "TruckBed"), "IGUI_VehiclePartTruckBed")
check(b.name == "IGUI_MinidoracatTesla_Part_TruckBed" and b.tooltip == b.name, "inventory window: a Tesla's trunk button says Rear Trunk")
b = button(container(H.vehicle({ script = "Base.CarNormal" }), "TruckBed"), "IGUI_VehiclePartTruckBed")
check(b.name == "IGUI_VehiclePartTruckBed", "inventory window: a vanilla car's trunk keeps its name")
b = button(container(H.vehicle({}), "SeatFrontLeft"), "IGUI_VehiclePartSeatFrontLeft")
check(b.name == "IGUI_VehiclePartSeatFrontLeft", "inventory window: unmapped Tesla parts (seats) keep their name")
b = button({ getVehiclePart = function() return nil end }, "bag")
check(b.name == "bag", "inventory window: non-vehicle containers untouched")
local mapped = 0
for _ in pairs(T.PartNames) do mapped = mapped + 1 end
check(mapped == 16, "16 vanilla keys mapped (7 parts, category, out of charge, 3 engine labels, 4 hood actions)")

H.section("cargo capacities (each car script)")
-- trunk anchored to the vanilla class (Model Y: SUV NormalTrunk2 85; Model 3: sedan NormalTrunk3 45), frunk by the
-- owner's manual ratio (Model Y 114 / 835 L, Model 3 88 / 594 L)
for _, c in ipairs({ { "ModelY", 85, 12, 114 / 835 }, { "Model3", 45, 7, 88 / 594 } }) do
    local f = assert(io.open("MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/scripts/vehicles/MinidoracatTesla_"
        .. c[1] .. ".txt", "r"))
    local script = f:read("*a")
    f:close()
    local function partCapacity(id)
        local body = script:match("\n        part " .. id .. "\n        {(.-)\n        }")
        return body and tonumber(body:match("capacity%s*=%s*(%d+)"))
    end
    local trunk, frunkCap = partCapacity("TruckBed"), partCapacity("Frunk")
    check(trunk == c[2] and frunkCap == c[3], c[1] .. ": TruckBed " .. tostring(trunk) .. ", Frunk " .. tostring(frunkCap))
    check(trunk and frunkCap and math.abs(frunkCap - trunk * c[4]) < 0.5, c[1] .. ": frunk / trunk follows the manual's litres")
end
