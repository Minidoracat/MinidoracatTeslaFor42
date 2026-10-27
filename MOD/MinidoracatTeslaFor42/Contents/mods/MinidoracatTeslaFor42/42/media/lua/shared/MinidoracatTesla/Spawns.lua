-- World spawns, written at file top level: VehicleSpawnControl snapshots VehicleZoneDistribution on
-- OnInitGlobalModData and later replaces the live table (MVSC_Server.lua:99-109,322-327), so late edits are lost.
-- Format and weights next to the vanilla ModernCar (VehicleZoneDefinition.lua:43,103). Every Tesla gets the design's
-- weights (parkingstall 3, good 4): Model 3 and Model Y are Tesla's two volume cars, so neither is rarer.
local Z = VehicleZoneDistribution
for _, car in ipairs({ "Base.MinidoracatTesla_ModelY", "Base.MinidoracatTesla_Model3" }) do
    if Z and Z.parkingstall and Z.parkingstall.vehicles then
        Z.parkingstall.vehicles[car] = { index = -1, spawnChance = 3 }
    end
    if Z and Z.good and Z.good.vehicles then
        Z.good.vehicles[car] = { index = -1, spawnChance = 4 }
    end
end
