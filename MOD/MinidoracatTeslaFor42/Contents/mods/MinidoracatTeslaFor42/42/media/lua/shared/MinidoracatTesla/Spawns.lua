-- World spawns, written at file top level: VehicleSpawnControl snapshots VehicleZoneDistribution on
-- OnInitGlobalModData and later replaces the live table (MVSC_Server.lua:99-109,322-327), so late edits are lost.
-- Format and weights next to the vanilla ModernCar (VehicleZoneDefinition.lua:43,103). Weights follow the designs
-- (plan-1023): both cars park in parking stalls at 3; only the Model Y also shows up in the upscale "good" zone at 4.
-- The Cybertruck (plan-cybertruck-1030) shows up only in the "good" zone, at 2; so does the Model X (plan-sx-1031).
-- The Model S Plaid (plan-sx-1031) likewise: a US$100k flagship, the "good" zone only, at 2.
-- The Model Y L (plan-yl-1111) like the Model Y, parking stalls at 3 and "good" at 4: its China price sits between the
-- Model Y Long Range and the Performance, the same class (user 2026-11-11).
-- The Roadster 2.5 Sport (plan-next-1114): a rare sports car, the "good" zone only, at 2 like the Model S, X and Cybertruck.
local Z = VehicleZoneDistribution
if Z and Z.parkingstall and Z.parkingstall.vehicles then
    Z.parkingstall.vehicles["Base.MinidoracatTesla_ModelY"] = { index = -1, spawnChance = 3 }
    Z.parkingstall.vehicles["Base.MinidoracatTesla_Model3"] = { index = -1, spawnChance = 3 }
    Z.parkingstall.vehicles["Base.MinidoracatTesla_ModelYL"] = { index = -1, spawnChance = 3 }
end
if Z and Z.good and Z.good.vehicles then
    Z.good.vehicles["Base.MinidoracatTesla_ModelY"] = { index = -1, spawnChance = 4 }
    Z.good.vehicles["Base.MinidoracatTesla_Cybertruck"] = { index = -1, spawnChance = 2 }
    Z.good.vehicles["Base.MinidoracatTesla_ModelS"] = { index = -1, spawnChance = 2 }
    Z.good.vehicles["Base.MinidoracatTesla_ModelX"] = { index = -1, spawnChance = 2 }
    Z.good.vehicles["Base.MinidoracatTesla_Roadster"] = { index = -1, spawnChance = 2 }
    Z.good.vehicles["Base.MinidoracatTesla_ModelYL"] = { index = -1, spawnChance = 4 }
end
