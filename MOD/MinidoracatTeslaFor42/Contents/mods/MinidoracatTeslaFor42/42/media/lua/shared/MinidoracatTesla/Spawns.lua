-- World spawns, written at file top level: VehicleSpawnControl snapshots VehicleZoneDistribution on
-- OnInitGlobalModData and later replaces the live table (MVSC_Server.lua:99-109,322-327), so late edits are lost.
-- Format and weights next to the vanilla ModernCar (VehicleZoneDefinition.lua:43,103). Weights follow the design
-- (plan-1023): both cars park in parking stalls at 3; only the Model Y also shows up in the upscale "good" zone at 4.
local Z = VehicleZoneDistribution
if Z and Z.parkingstall and Z.parkingstall.vehicles then
    Z.parkingstall.vehicles["Base.MinidoracatTesla_ModelY"] = { index = -1, spawnChance = 3 }
    Z.parkingstall.vehicles["Base.MinidoracatTesla_Model3"] = { index = -1, spawnChance = 3 }
end
if Z and Z.good and Z.good.vehicles then
    Z.good.vehicles["Base.MinidoracatTesla_ModelY"] = { index = -1, spawnChance = 4 }
end
