-- Tesla Collection core: names, specs, battery readers, authorization, net helpers.
-- Every other file does require "MinidoracatTesla/Core". Battery writers live in server/MinidoracatTesla/Battery.lua.
MinidoracatTesla = MinidoracatTesla or {}
local T = MinidoracatTesla

T.MOD_ID = "MinidoracatTeslaFor42"
T.MODULE = "MinidoracatTesla"
T.BATTERY_PART = "GasTank"   -- Java requires a part with this id and content > 0 to start (VehiclePartOwner.java:84-95)
T.CONTENT_TYPE = "Electricity"

T.ServerCommands = T.ServerCommands or {}
T.ClientCommands = T.ClientCommands or {}
T.Update = T.Update or {}
T.Create = T.Create or {}
T.CheckEngine = T.CheckEngine or {}
T.CheckOperate = T.CheckOperate or {}
T.Battery = T.Battery or {}
T.ContainerAccess = T.ContainerAccess or {}

-- Energy is in kWh of game time: a kW drawn for one game hour is one kWh.
-- kwPerKmh, idleKw: at vanilla's default Gas Consumption (1) a full pack drives as far as a full vanilla CarNormal
-- tank at 50 km/h: 75.7 km here (references/vehicle-battery.md "續航校正"). MP measurements on the same road:
-- tesla-rangegas-1029-calib-g1 (Gas Consumption 1) 288.7 tiles took 0.1891 L of the 49 L tank (74.8 km a tank);
-- the 2026-10-23 calibration tesla-calib-normal-1023a (0.0189 L for 290.9 tiles, 756 km, which the coefficients were
-- fitted to: 757 km) ran at the E2E server template's Gas Consumption 0.1, and vanilla's burn is proportional to it
-- (Vehicles.lua:485; measured ratio 10.08). Hence DRIVE_SCALE: the 10-23 coefficients (62.5 kWh pack
-- 0.03, 0.00456, x 78.4 / 62.5 for the Performance pack: 0.0376, 0.00572) times 10; at Gas Consumption 0.1 the car
-- drives the 757 km again. The drive and summon draw also follow T.driveMul (sandbox). massKg (Performance curb mass)
-- and regenEff size the regen (Regen.lua scales it by DRIVE_SCALE too, so it keeps its share of the drive draw).
T.DRIVE_SCALE = 10
-- model: the atlas sprite suffix (top view car_<model> on the HUD and the app's maps, wordmark wm_<model>,
-- trim_<model>) and the HUD door zones (HUD.lua). appCar: the app's car picture file prefix
-- (scripts/blender/skf/convert.py appcar, + the paint name). v12Kwh: the low voltage battery (Battery.lua topUp12V).
-- plug: the charge cable's plug segment (client/MinidoracatTesla/Cable.lua): render-only item and its handle height
-- above the floor in units (1 level = 2.44949), measured at the car's chargeport (E2E integration-mp `port`);
-- scripts/blender/props/props_blender.py PLUGS builds one mesh per entry (build.py --check compares the two).
-- hepa: a HEPA filter and Bioweapon Defense Mode (owner's manuals: Model Y p.169, Cybertruck p.165, Model S p.148,
-- Model X p.165; none in the Model 3's), Camp.lua C.filterAir and the radial slice.
-- dcKw: the car's DC fast charging peak (Supercharger, Chargers.lua T.chargerKw; T.DC_KW 250 without one): Model Y P,
-- Model 3 P, Model S / X Plaid 250 kW (tesla.com), Cybertruck (Cyberbeast) 325 kW (Korean spec page footnote).
-- doorClip: every car's door parts whose clip is not 0.8 s, part id -> clip seconds (= scripts/blender/skf/cars/<car>.py
-- DOORS; Liftgate.syncShell times the cabin shell's door bits on it; harness test_liftgate compares the two).
-- Cybertruck only: tonneau (the app's tonneau cover button), armorGlass (smashes a window takes, Truck.lua),
-- powershare and bedOutlet (Powershare, the bed outlets).
-- Model X only: falcon (the app's falcon wing doors button), doorWait (clip seconds into a door's opening swing the
-- climb starts at, per door part, on T.clipStep's clock; EnterDoor.lua, else its E.WAIT).
T.Specs = {
    ["Base.MinidoracatTesla_ModelY"] = {
        model = "ModelY",
        appCar = "app_car_",
        plug = { item = "Base.MinidoracatTesla_CablePlug", z = 0.87 }, -- E2E integration-mp tesla-yhn (15dba30 body: port 0.870)
        v12Kwh = 15.5 * 6.9 / 1000, -- lithium-ion 15.5 V, 6.9 Ah (Model Y owner's manual, R10)
        idleKw = 0.0376 * T.DRIVE_SCALE,
        kwPerKmh = 0.00572 * T.DRIVE_SCALE,
        massKg = 2033,
        dcKw = 250,
        regenEff = 0.6,
        hepa = true,
        doorClip = { TrunkDoor = 3.6 }, -- cars/model_y.py DOORS
        -- official Model Y paints (TeslaModelY, references/models.md): entry i = vehicle script skin i-1, and saved
        -- games keep the skin index (BaseVehicle.java:2635/2741), so only append. h/s/v (setColorHSV) tint the
        -- damage overlays to the paint (vehicle_common.frag.glsl:6-15), written by scripts/blender/skf/convert.py build
        -- from each skin's median paint colour; the skins themselves are full colour.
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.759, s = 0.572, v = 0.231 },
            { name = "PearlWhite", code = "PPSW", h = 0.597, s = 0.492, v = 0.854 },
            { name = "DiamondBlack", code = "PX02", h = 0.922, s = 0.55, v = 0.179 },
            { name = "Quicksilver", code = "PN00", h = 0.795, s = 0.525, v = 0.352 },
            { name = "UltraRed", code = "PR01", h = 0.996, s = 1.0, v = 0.399 },
            { name = "GlacierBlue", code = "PB01", h = 0.606, s = 0.793, v = 0.369 },
            { name = "MarineBlue", code = "PB02", h = 0.61, s = 0.801, v = 0.215 },
            { name = "FrostBlue", code = "PB00", h = 0.61, s = 0.839, v = 0.483 },
        },
    },
    ["Base.MinidoracatTesla_Model3"] = {
        model = "Model3",
        appCar = "app_car_model3_",
        plug = { item = "Base.MinidoracatTesla_CablePlugModel3", z = 0.74 },
        v12Kwh = 15.5 * 6.9 / 1000, -- 15.5 V, 6.9 Ah (tesla.cn Model 3 owner's manual 2026, Battery - Low Voltage, p.179)
        idleKw = 0.0376 * T.DRIVE_SCALE,
        kwPerKmh = 0.00572 * T.DRIVE_SCALE,
        massKg = 1851, -- curb mass, China owner's manual / MIIT filing TSL7000BEVBA5
        dcKw = 250,
        regenEff = 0.6,
        doorClip = { TrunkDoor = 3.0 }, -- cars/model_3.py DOORS
        -- official Model 3 Performance paints (US, DE, TW design studios; references/models.md): same rules as above
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.71, s = 0.546, v = 0.305 },
            { name = "PearlWhite", code = "PPSW", h = 0.532, s = 0.491, v = 0.81 },
            { name = "DiamondBlack", code = "PX02", h = 0.923, s = 0.557, v = 0.211 },
            { name = "Quicksilver", code = "PN00", h = 0.808, s = 0.484, v = 0.456 },
            { name = "UltraRed", code = "PR01", h = 0.997, s = 1.0, v = 0.463 },
            { name = "DeepBlue", code = "PPSB", h = 0.602, s = 1.0, v = 0.393 },
            { name = "MarineBlue", code = "PB02", h = 0.584, s = 0.756, v = 0.281 },
            { name = "FrostBlue", code = "PB00", h = 0.6, s = 0.769, v = 0.477 },
        },
    },
    ["Base.MinidoracatTesla_Cybertruck"] = {
        model = "Cybertruck",
        appCar = "app_car_cybertruck_",
        -- z: handle height at this car's charge port (E2E integration-mp tesla-ctbody-integ-1030a: port 0.902)
        plug = { item = "Base.MinidoracatTesla_CablePlugCybertruck", z = 0.90 },
        v12Kwh = 48 * 4 / 1000, -- 48 V, 4 Ah (Cybertruck owner's manual p.251)
        -- the Model Y coefficients x 123 / 78.4: a full pack still drives one vanilla tank's distance
        idleKw = 0.0590 * T.DRIVE_SCALE,
        kwPerKmh = 0.00897 * T.DRIVE_SCALE,
        massKg = 3113, -- Cyberbeast curb mass 6,863 lb (tesla.com 2026-10-30)
        dcKw = 325,
        regenEff = 0.6,
        hepa = true,
        doorClip = { TrunkDoor = 2.0 }, -- cars/cybertruck.py DOORS
        powershare = true, -- Powershare (owner's manual p.204)
        bedOutlet = { area = "TruckBed", tiles = 2 }, -- bed outlets: a Mobile Connector this near the bed (p.200)
        tonneau = true, -- powered tonneau cover (owner's manual p.60)
        armorGlass = 3, -- Armor Glass: three smashes a window
        -- Cyberbeast is built in stainless only ($PDD, US design studio 2026-07-10); the other 11 are Tesla's Color Paint
        -- Film wraps (shop 2024-06). weight: T.pickColor draws by it, so stainless takes half the spawns. Same order
        -- and append-only rules as above; h/s/v by convert.py build.
        colors = {
            { name = "Stainless", code = "PDD", weight = 11, h = 0.836, s = 0.523, v = 0.389 },
            { name = "SatinStealthBlack", weight = 1, h = 0.062, s = 0.511, v = 0.187 },
            { name = "SatinCeramicWhite", weight = 1, h = 0.7, s = 0.509, v = 0.778 },
            { name = "SatinRoseGold", weight = 1, h = 0.074, s = 0.663, v = 0.418 },
            { name = "SatinTacticalGreen", weight = 1, h = 0.125, s = 0.494, v = 0.303 },
            { name = "SatinDarkGrey", weight = 1, h = 0.889, s = 0.485, v = 0.29 },
            { name = "SatinForestGreen", weight = 1, h = 0.445, s = 0.596, v = 0.307 },
            { name = "SatinAbyssBlue", weight = 1, h = 0.566, s = 1.0, v = 0.312 },
            { name = "CopperTintedClear", weight = 1, h = 0.063, s = 0.837, v = 0.441 },
            { name = "SatinCrimsonRed", weight = 1, h = 0.986, s = 1.0, v = 0.244 },
            { name = "SatinIridescentPurple", weight = 1, h = 0.895, s = 0.557, v = 0.164 },
            { name = "SlipGrey", weight = 1, h = 0.807, s = 0.49, v = 0.594 },
        },
    },
    ["Base.MinidoracatTesla_ModelS"] = {
        model = "ModelS",
        appCar = "app_car_models_",
        -- z: handle height at this car's charge port (E2E integration-mp)
        plug = { item = "Base.MinidoracatTesla_CablePlugModelS", z = 0.73 },
        v12Kwh = 15.5 * 6.9 / 1000, -- 15.5 V, 6.9 Ah (Model S owner's manual, Subsystems 2026-05)
        -- the Model Y coefficients x 100 / 78.4: a full pack still drives one vanilla tank's distance
        idleKw = 0.0480 * T.DRIVE_SCALE,
        kwPerKmh = 0.00730 * T.DRIVE_SCALE,
        massKg = 2178, -- Plaid curb mass 4,802 lb (tesla.com 2026-04-21)
        dcKw = 250,
        regenEff = 0.6,
        doorClip = { TrunkDoor = 3.6 }, -- cars/model_s.py DOORS
        hepa = true, -- HEPA filter and Bioweapon Defense Mode (Model S owner's manual p.148)
        -- the last US design studio's six paints (2026-03-06) and the China pre-refresh Solid Black and Deep Blue
        -- (user 2026-10-31); same order and append-only rules as above, h/s/v by convert.py build
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.812, s = 0.512, v = 0.35 },
            { name = "LunarSilver", code = "PN02", h = 0.726, s = 0.523, v = 0.556 },
            { name = "PearlWhite", code = "PPSW", h = 0.82, s = 0.475, v = 0.893 },
            { name = "UltraRed", code = "PR01", h = 0.987, s = 1.0, v = 0.416 },
            { name = "DiamondBlack", code = "PX02", h = 0.062, s = 0.58, v = 0.215 },
            { name = "FrostBlue", code = "PB00", h = 0.592, s = 0.976, v = 0.494 },
            { name = "SolidBlack", code = "PBSB", h = 0.032, s = 0.547, v = 0.194 },
            { name = "DeepBlue", code = "PPSB", h = 0.616, s = 1.0, v = 0.399 },
        },
    },
    ["Base.MinidoracatTesla_ModelX"] = {
        model = "ModelX",
        appCar = "app_car_modelx_",
        -- z: handle height at this car's charge port (E2E integration-mp)
        plug = { item = "Base.MinidoracatTesla_CablePlugModelX", z = 0.84 }, -- tesla-mx-1101b (port 0.837)
        v12Kwh = 15.5 * 6.9 / 1000, -- 15.5 V, 6.9 Ah (Model X owner's manual 2025.2, p.226)
        -- the Model Y coefficients x 100 / 78.4: a full pack still drives one vanilla tank's distance
        idleKw = 0.0480 * T.DRIVE_SCALE,
        kwPerKmh = 0.00730 * T.DRIVE_SCALE,
        massKg = 2465, -- Model X Plaid curb mass 5,434 lb (tesla.com 2026-03-09)
        dcKw = 250,
        regenEff = 0.6,
        hepa = true, -- HEPA filtration, Bioweapon Defense Mode (Model X owner's manual)
        falcon = true, -- falcon wing doors: the app's button opens both rear doors (owner's manual p.31-33)
        -- the falcon wing doors swing up in a 2.4 s clip (cars/model_x.py DOORS): the climb waits until they are nearly
        -- up (EnterDoor.lua; modelx-sp tesla-mx-1101g: CLIMB 1.84 s into the clip, the wing up); the front doors keep
        -- E.WAIT
        doorWait = { DoorRearLeft = 1.84, DoorRearRight = 1.84 },
        doorClip = { TrunkDoor = 3.6, DoorRearLeft = 2.4, DoorRearRight = 2.4 }, -- cars/model_x.py DOORS
        -- Model X Plaid paints: the last US design studio's six (Lexicon 2026-03-06) and China's pre-refresh Solid
        -- Black and Deep Blue (2025-03). Same order and append-only rules as above; h/s/v by convert.py build.
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.72, s = 0.538, v = 0.283 },
            { name = "LunarSilver", code = "PN02", h = 0.634, s = 0.53, v = 0.56 },
            { name = "PearlWhite", code = "PPSW", h = 0.645, s = 0.514, v = 0.904 },
            { name = "UltraRed", code = "PR01", h = 0.987, s = 1.0, v = 0.449 },
            { name = "DiamondBlack", code = "PX02", h = 0.953, s = 0.537, v = 0.227 },
            { name = "FrostBlue", code = "PB00", h = 0.586, s = 0.894, v = 0.487 },
            { name = "SolidBlack", code = "PBSB", h = 0.925, s = 0.52, v = 0.24 },
            { name = "DeepBlue", code = "PPSB", h = 0.589, s = 1.0, v = 0.49 },
        },
    },
    ["Base.MinidoracatTesla_ModelYL"] = {
        model = "ModelYL",
        label = "Model Y L", -- the app's car name (PhoneApp.carLabel; else the model split at its capitals)
        appCar = "app_car_modelyl_",
        -- z: handle height at this car's charge port (E2E integration-mp tesla-ylb-geo, 4a067bd body: port 0.900)
        plug = { item = "Base.MinidoracatTesla_CablePlugModelYL", z = 0.90 },
        v12Kwh = 14.4 * 12 / 1000, -- 14.4 V, 12 Ah (Model Y owner's manual 2026.26, 6-seater, p.208)
        -- the Model Y coefficients x 82 / 78.4: a full pack still drives one vanilla tank's distance
        idleKw = 0.0393 * T.DRIVE_SCALE,
        kwPerKmh = 0.00598 * T.DRIVE_SCALE,
        massKg = 2088, -- curb mass (China owner's manual p.204; MIIT filing TSL6500BEVBA0)
        dcKw = 250,
        regenEff = 0.6,
        hepa = true, -- HEPA filter, Bioweapon Defense Mode (China design studio $MTY87 compare table)
        doorClip = { TrunkDoor = 3.6 }, -- cars/model_yl.py DOORS
        -- Model Y L paints: China's six ($MTY87, Lexicon 2026-10-30) and the US Marine Blue ($MTY83, 2026-07-10).
        -- Same order and append-only rules as above; h/s/v by convert.py build.
        colors = {
            { name = "StealthGrey", code = "PN01", h = 0.725, s = 0.523, v = 0.28 },
            { name = "PearlWhite", code = "PPSW", h = 0.701, s = 0.48, v = 0.885 },
            { name = "DiamondBlack", code = "PX02", h = 0.932, s = 0.518, v = 0.21 },
            { name = "UltraRed", code = "PR01", h = 0.986, s = 1.0, v = 0.493 },
            { name = "CosmicSilver", code = "PN03", h = 0.984, s = 0.504, v = 0.519 },
            { name = "GlacierBlue", code = "PB01", h = 0.603, s = 0.751, v = 0.442 },
            { name = "MarineBlue", code = "PB02", h = 0.6, s = 0.823, v = 0.265 },
        },
    },
}

-- Index into a colors table, drawn by each entry's weight (none = 1: the Model Y and Model 3 paints stay even)
function T.pickColor(colors)
    local total = 0
    for _, c in ipairs(colors) do total = total + (c.weight or 1) end
    local r = ZombRand(total)
    for i, c in ipairs(colors) do
        r = r - (c.weight or 1)
        if r < 0 then return i end
    end
    return #colors
end

-- Pack items: exact kWh. Item MaxCapacity is an int (Item.java:2502-2503), so it is rounded up and the exact value
-- lives here. Model Y Performance 78.4 kWh and Model 3 Performance (TSL7000BEVBA5) 78.4 kWh are China MIIT filings
-- (Tesla publishes no kWh for them, references/vehicle-battery.md), the latter purchase-tax exemption catalogue batch 6
-- (2024 No. 11); Cyberbeast 123 kWh is Tesla's own figure (tesla.com Cybertruck page 2026-10-30, Powershare).
T.Packs = {
    ["Base.MinidoracatTesla_ModelYBattery"] = 78.4,
    ["Base.MinidoracatTesla_Model3Battery"] = 78.4,
    ["Base.MinidoracatTesla_CybertruckBattery"] = 123,
    -- Model S Plaid: Tesla publishes no kWh; EV Database's nominal 100 kWh (ev-database.org car 3384)
    ["Base.MinidoracatTesla_ModelSBattery"] = 100,
    -- Model X Plaid: EV Database's nominal 100 kWh (Tesla publishes none)
    ["Base.MinidoracatTesla_ModelXBattery"] = 100,
    -- Model Y L: 82.0 kWh, China MIIT filing as reported by the press (Tesla publishes none)
    ["Base.MinidoracatTesla_ModelYLBattery"] = 82,
}

-- Tesla display names for vanilla text keys: vanilla key -> Tesla key. Read by client/MinidoracatTesla/PartNames.lua
-- (the vanilla mechanics window, radial menu and container buttons, for Teslas only), the HUD and the phone app.
T.PartNames = {
    IGUI_VehiclePartGasTank = "IGUI_MinidoracatTesla_Part_GasTank",
    IGUI_VehiclePartEngine = "IGUI_MinidoracatTesla_Part_Engine",
    IGUI_VehiclePartBattery = "IGUI_MinidoracatTesla_Part_Battery",
    IGUI_VehiclePartHeater = "IGUI_MinidoracatTesla_Part_Heater",
    IGUI_VehiclePartEngineDoor = "IGUI_MinidoracatTesla_Part_EngineDoor",
    IGUI_VehiclePartTruckBed = "IGUI_MinidoracatTesla_Part_TruckBed",
    IGUI_VehiclePartTrunkDoor = "IGUI_MinidoracatTesla_Part_TrunkDoor",
    IGUI_VehiclePartCatengine = "IGUI_MinidoracatTesla_PartCat_engine", -- category header (ISVehicleMechanics.lua:59)
    Tooltip_outoffuel = "IGUI_MinidoracatTesla_OutOfCharge",        -- empty GasTank (:1085, :1265)
    IGUI_EnginePower = "IGUI_MinidoracatTesla_MotorPower",           -- header "Engine Power: N hp" (:1178)
    IGUI_Vehicle_EngineLoudness = "IGUI_MinidoracatTesla_MotorLoudness", -- drive unit detail (:1325-1327)
    IGUI_Vehicle_EngineQuality = "IGUI_MinidoracatTesla_MotorQuality",
    IGUI_OpenHood = "IGUI_MinidoracatTesla_OpenFrunk",               -- outside radial menu (ISVehicleMenu.lua:318-337)
    IGUI_CloseHood = "IGUI_MinidoracatTesla_CloseFrunk",
    IGUI_LockHood = "IGUI_MinidoracatTesla_LockFrunk",
    IGUI_UnlockHood = "IGUI_MinidoracatTesla_UnlockFrunk",
}
-- per car, on top of T.PartNames (vehicle script full name -> vanilla or Tesla key -> this car's key); the phone app's
-- lid texts go through it too (PhoneApp.lua carKey)
T.CarPartNames = {
    -- a sedan's trunk lid, not a liftgate (Model 3 owner's manuals; the Model Y keeps Liftgate)
    ["Base.MinidoracatTesla_Model3"] = {
        IGUI_VehiclePartTrunkDoor = "IGUI_MinidoracatTesla_Part_TrunkLid",
        IGUI_MinidoracatTesla_App_Trunk = "IGUI_MinidoracatTesla_App_TrunkLid",
        IGUI_MinidoracatTesla_App_Done_trunk = "IGUI_MinidoracatTesla_App_Done_trunkLid",
        IGUI_MinidoracatTesla_App_Done_trunk_on = "IGUI_MinidoracatTesla_App_Done_trunkLid_on",
        IGUI_MinidoracatTesla_App_Done_trunk_off = "IGUI_MinidoracatTesla_App_Done_trunkLid_off",
        IGUI_MinidoracatTesla_Tip_AppLock = "IGUI_MinidoracatTesla_Tip_AppLockLid",
        IGUI_MinidoracatTesla_Tip_AppUnlock = "IGUI_MinidoracatTesla_Tip_AppUnlockLid",
        IGUI_MinidoracatTesla_Tip_AppTrunk = "IGUI_MinidoracatTesla_Tip_AppTrunkLid",
        IGUI_MinidoracatTesla_App_ControlsSub = "IGUI_MinidoracatTesla_App_ControlsSubLid",
    },
    -- Cybertruck owner's manual: Tailgate, Cargo Bed (the tonneau cover is its own part, IGUI_VehiclePartTrunkTonneau);
    -- the app's lock texts name the tonneau too (it locks with the car, Liftgate.lua L.LIDS)
    ["Base.MinidoracatTesla_Cybertruck"] = {
        IGUI_VehiclePartTrunkDoor = "IGUI_MinidoracatTesla_Part_Tailgate",
        IGUI_VehiclePartTruckBed = "IGUI_MinidoracatTesla_Part_CargoBed",
        IGUI_MinidoracatTesla_App_Trunk = "IGUI_MinidoracatTesla_App_Tailgate",
        IGUI_MinidoracatTesla_App_Done_trunk = "IGUI_MinidoracatTesla_App_Done_tailgate",
        IGUI_MinidoracatTesla_App_Done_trunk_on = "IGUI_MinidoracatTesla_App_Done_tailgate_on",
        IGUI_MinidoracatTesla_App_Done_trunk_off = "IGUI_MinidoracatTesla_App_Done_tailgate_off",
        IGUI_MinidoracatTesla_Tip_AppLock = "IGUI_MinidoracatTesla_Tip_AppLockCybertruck",
        IGUI_MinidoracatTesla_Tip_AppUnlock = "IGUI_MinidoracatTesla_Tip_AppUnlockCybertruck",
        IGUI_MinidoracatTesla_Tip_AppTrunk = "IGUI_MinidoracatTesla_Tip_AppTailgate",
        IGUI_MinidoracatTesla_App_ControlsSub = "IGUI_MinidoracatTesla_App_ControlsSubCybertruck",
    },
    -- Model X owner's manual: the rear doors are the falcon wing doors (p.31-33)
    ["Base.MinidoracatTesla_ModelX"] = {
        IGUI_VehiclePartDoorRearLeft = "IGUI_MinidoracatTesla_Part_FalconWingLeft",
        IGUI_VehiclePartDoorRearRight = "IGUI_MinidoracatTesla_Part_FalconWingRight",
        IGUI_MinidoracatTesla_App_ControlsSub = "IGUI_MinidoracatTesla_App_ControlsSubModelX",
    },
}
-- the Tesla key for a key on this car (script full name), or nil
function T.partNameKey(script, key)
    local car = T.CarPartNames[script]
    return car and car[key] or T.PartNames[key]
end

local PREFIX = "[" .. T.MOD_ID .. "] "
function T.log(msg)
    print(PREFIX .. tostring(msg))
end

function T.hours()
    return getGameTime():getWorldAgeHours() -- GameTime.java:901
end

local function sandbox(name, default)
    local s = SandboxVars and SandboxVars.MinidoracatTesla
    local v = s and s[name]
    if type(v) ~= "number" then return default end
    return v
end
function T.rangeMul() return math.max(0.25, math.min(10, sandbox("RangeMultiplier", 1))) end
-- vanilla sandbox Gas Consumption (CarGasConsumption 0-100, default 1; SandboxOptions.java:184) multiplies the petrol a
-- running engine burns, idling too (Vehicles.lua:485); the drive and summon draw follow it the same way (user
-- 2026-10-29). Unreadable: 1.
function T.gasMul()
    local v = SandboxVars and SandboxVars.CarGasConsumption
    if type(v) ~= "number" then return 1 end
    return math.max(0, math.min(100, v))
end
-- the drive and summon draw (idle included) as a multiple of the calibration (Battery.lua); 0 = driving is free
function T.driveMul() return T.gasMul() / T.rangeMul() end
function T.chargeMul() return math.max(0.1, math.min(10, sandbox("ChargeSpeedMultiplier", 1))) end
-- generator fuel per kWh as a multiple of the default (sandbox ChargeFuelMultiplier, user 2026-10-29; Chargers.lua T.fuelPerKwh)
function T.chargeFuelMul() return math.max(0, math.min(10, sandbox("ChargeFuelMultiplier", 1))) end
T.Camp = T.Camp or {}
-- Camp Mode low-battery limit (sandbox CampMinBattery, 10-20 %; Tesla's Low Power Mode setting has the same range)
function T.Camp.minPct() return math.max(10, math.min(20, sandbox("CampMinBattery", 20))) end

function T.spec(vehicle)
    return vehicle and T.Specs[vehicle:getScriptName()] or nil -- BaseVehicle.java:1621 (full name, :1540)
end
function T.isTesla(vehicle) return T.spec(vehicle) ~= nil end
-- clip seconds a part anim (door swing) advances this update: 1/60 x 0.8 x the unmodded multiplier
-- (BaseVehicle.java:3898-3904), which carries the game speed (GameTime.java:1018-1022): fast forward runs it sooner,
-- a pause holds it. Timers that wait on a door count on this clock.
function T.clipStep() return 0.8 / 60 * getGameTime():getUnmoddedMultiplier() end

-- ---- battery readers (any side) ----
local B = T.Battery
function B.part(vehicle)
    if not T.isTesla(vehicle) then return nil end
    local part = vehicle:getPartById(T.BATTERY_PART)
    if part and part:getContainerContentType() == T.CONTENT_TYPE then return part end
    return nil
end
-- capped at the exact pack size: vanilla repair() (admin / debug "repair", E2E probe spawns) fills the tank to the
-- item's whole-number MaxCapacity (VehiclePart.java:989-992), 79 for a 78.1 kWh pack, and nothing writes it back
-- until the next Battery.set; uncapped, that first write looked like 0.9 kWh spent on whatever it was for
function B.kwh(part) return part and math.min(part:getContainerContentAmount(), B.capacity(part)) or 0 end -- VehiclePart.java:375
function B.capacity(part)
    local item = part and part:getInventoryItem()
    if not item then return 0 end
    return T.Packs[item:getFullType()] or part:getContainerCapacity() -- VehiclePart.java:349-361
end
function B.pct(part)
    local cap = B.capacity(part)
    if cap <= 0 then return 0 end
    return math.max(0, math.min(100, B.kwh(part) * 100 / cap))
end
-- Plugged in and the charger has power (grid or a running generator, chg.power from the last settle, also while full
-- or stopped): the car's own loads (motor standby, climate, camp, 12V, sentry) run on the charger, not the pack. Model Y
-- owner's manual, Charging Instructions: "when Model Y is parked and plugged in ... it uses energy from the charging
-- equipment instead of the battery". Writers: server Battery.lua B.draw.
function B.onCharger(part)
    local chg = part and part:getModData().chg
    return chg ~= nil and chg.power ~= nil
end

-- km per kWh at the reference speed. Consumption is per game minute (like vanilla Vehicles.Update.GasTank),
-- so distance per game minute depends on DayLength: real seconds per game minute = minutesPerDay*60/1440
-- (GameTime.java:946). 1 km = 1000 tiles (getCurrentSpeedKmHour is tiles per real second * 3.6).
-- nil = no range limit (Gas Consumption 0, driving takes no charge): the HUD draws "∞ km", texts say "--"
-- (UIFont.Small has no ∞, media/fonts/*.fnt).
T.REF_KMH = 50 -- the calibration speed
function T.secPerGameMin() return getGameTime():getMinutesPerDay() * 60 / 1440 end
function T.kmPerKwh(vehicle)
    local s = T.spec(vehicle)
    if not s then return 0 end
    local mul = T.driveMul()
    if mul <= 0 then return nil end
    local kmPerMin = T.REF_KMH / 3600 * T.secPerGameMin()
    local kwhPerMin = (s.idleKw + s.kwPerKmh * T.REF_KMH * T.towMul(vehicle)) / 60
    return kmPerMin / kwhPerMin / mul
end
-- Towing: the drive term (not idle) costs 1 + 2 x towed mass / own mass, at most 3 (user 2026-10-31, towMul = mass).
-- The manuals only say range "can decrease significantly"; MotorTrend's Model Y with a trailer about half its weight
-- used about 2x the energy. getMass counts parts and cargo (BaseVehicle.java:9046-9063): measured (features-sp
-- tesla-feat-1101b) Model Y 1122, small trailer 277 -> x1.49, CarNormal 1112 -> x2.98. The client has the link
-- (VehicleTowingAttachPacket) and the masses, so the HUD and the app show the same range the server bills. A
-- VirtualVehicle (SP, unloaded) tows nothing.
T.TOW_MAX = 3
function T.towMul(vehicle)
    local t = vehicle.getVehicleTowing and vehicle:getVehicleTowing() -- BaseVehicle.java:9918
    if not t then return 1 end
    return math.min(T.TOW_MAX, 1 + 2 * t:getMass() / math.max(1, vehicle:getMass()))
end
-- Chill (owner's manuals: "Limits acceleration for a smooth and gentle ride"; top speed unchanged): the engine force
-- while on, one value for every car (Chill takes about 7 s to 60 mph on each model, about 2.2x a Model Y Performance's
-- 3.3 s). Calibration knob: E2E feel-sp 0-100 km/h, Model Y 6260 -> 7.19 s, 3300 -> 14.75 s, 2800 -> 17.60 s
-- (tesla-chill-1101a); 3100 -> 15.78 s = 2.19x, Cybertruck at 3100 16.02 s, top speed 122 as before (tesla-chill-1101b).
T.CHILL_FORCE = 3100
-- DC fast charging curve (Supercharger, plan-chargers-1028 design's 250 kW table normalised): charge % -> share of
-- the peak, linear in between. Model Y 10->90 % 36.4 game minutes, 0->100 % 63.6; Cybertruck at 325 kW 10->90 % 44.0
-- (harness test_charging.lua "DC curve").
T.DC_CURVE = { { 0, 0.80 }, { 5, 1.00 }, { 15, 1.00 }, { 30, 0.78 }, { 40, 0.64 }, { 50, 0.512 }, { 60, 0.408 },
    { 70, 0.32 }, { 80, 0.232 }, { 90, 0.144 }, { 100, 0.032 } }
function B.dcShare(pct)
    local c = T.DC_CURVE
    if pct <= c[1][1] then return c[1][2] end
    for i = 2, #c do
        local a, b = c[i - 1], c[i]
        if pct <= b[1] then return a[2] + (b[2] - a[2]) * (pct - a[1]) / (b[1] - a[1]) end
    end
    return c[#c][2]
end
-- kW flowing into a pack of cap kWh holding kwh, on cable record chg: chg.kw is the source's limit (the charger, or a
-- Cybertruck's share); a DC charger's (chg.peak, Charging.lua C.start) also follows the curve.
function B.chargeKwAt(chg, cap, kwh)
    local kw = chg.kw or 0
    if not chg.peak or cap <= 0 then return kw end
    return math.min(kw, chg.peak * B.dcShare(kwh * 100 / cap))
end
-- Charging from kwh for at most `hours`, never past toKwh: kWh added, hours it took. AC (no chg.peak): chg.kw flat.
-- DC: the kW at the middle of each 1 % step all through it (so a partial step and B.chargeHours agree), at most
-- about 100 steps.
function B.chargeGain(chg, cap, kwh, hours, toKwh)
    local need = math.max(0, toKwh - kwh)
    if hours <= 0 or need <= 0 then return 0, 0 end
    if not chg.peak or cap <= 0 then
        local kw = chg.kw or 0
        if kw <= 0 then return 0, 0 end
        local g = kw * hours
        if g >= need then return need, need / kw end
        return g, hours
    end
    local step, to = cap / 100, math.min(toKwh, cap)
    local k, h = kwh, 0
    while k < to - 1e-9 do
        local i = math.floor(k / step + 1e-9)
        local nxt = math.min(to, (i + 1) * step)
        local kw = B.chargeKwAt(chg, cap, (i + 0.5) * step)
        if kw <= 0 then break end
        local dh = (nxt - k) / kw
        if h + dh >= hours then return k + kw * (hours - h) - kwh, hours end
        k, h = nxt, h + dh
    end
    return k - kwh, h
end
-- hours to charge from kwh to toKwh (0 when nothing flows)
function B.chargeHours(chg, cap, kwh, toKwh)
    local _, h = B.chargeGain(chg, cap, kwh, math.huge, toKwh)
    return h
end

-- Charge projection between server settlements: the charge since chg.last on the same curve the server books
-- (B.chargeGain, Charging.lua C.settle), capped at the target (architecture §4). The HUD, the charge card and the
-- phone app's record (Remote.lua) all show this, so they agree.
function B.chargeEstimate(part, chg, now)
    local cap = B.capacity(part)
    local kwh = B.kwh(part)
    local target = (chg.target or 100) * cap / 100
    local added = chg.added or 0
    if not chg.paused and chg.kw and chg.last and now > chg.last then
        local gain = B.chargeGain(chg, cap, kwh, now - chg.last, target)
        kwh = kwh + gain
        added = added + gain
    end
    return kwh, added, B.chargeHours(chg, cap, kwh, target), cap
end

-- math.huge with charge left when driving takes none (Gas Consumption 0); an empty pack still cannot start
function T.rangeKm(vehicle)
    local part = B.part(vehicle)
    if not part then return 0 end
    local kwh, k = B.kwh(part), T.kmPerKwh(vehicle)
    if not k then return kwh > 0 and math.huge or 0 end
    return kwh * k
end

-- "Stopped" for Park-only actions (plug in, power off, liftgate, camp): |speed| <= 1 km/h; the HUD shows N below
-- 1 km/h too. A remote driver's speed on the server is the client-reported jniSpeed (BaseVehicle.java:4312-4316).
T.STOP_KMH = 1
function T.stopped(vehicle)
    return math.abs(vehicle:getCurrentSpeedKmHour()) <= T.STOP_KMH
end

-- GasTank checkEngine (shared: isEngineWorking runs on clients too, VehicleParts.java:167-177, e.g. the radial
-- menu's start-engine slice ISVehicleMenu.lua:88-106). Empty pack = cannot start. A plugged-in car may start (powers
-- on in Park, owner's manual "Shifting"); CheckOperate keeps it from driving off.
function T.CheckEngine.Battery(vehicle, part)
    return part:getInventoryItem() ~= nil and vehicle:hasEnoughGasToRun()
end

-- GasTank checkOperate: the local driver's input reaches the car only while this is true (BaseVehicle.java:4616-4625
-- isOperational -> CarController.updateControls, called each frame for the local driver from IsoPlayer.java:4386-4387;
-- vanilla tires have the same per-frame hook, Vehicles.CheckOperate.Tire). Plugged in = no driving: "Model Y does not
-- shift out of Park while a charge cable is plugged in" (owner's manual, Shifting). MP driving physics run on the
-- driver's client, so this is where it is stopped; the server still unplugs a car that got away (Charging checkCable).
-- Plugged in, T.onPluggedDrive (client ChargerMenu.lua) brakes the car while a pedal is down and says why; it holds
-- the input back only on the frames it renews the brake, so the controls stay live (a pedal held since before the
-- plug is braked too) and the brake key works. Cruise control presses the accelerator by itself
-- (CarController.java:242-246): switched off.
function T.CheckOperate.Battery(vehicle, part)
    if part:getModData().chg == nil then return true end
    if vehicle:isRegulator() then vehicle:setRegulator(false) end
    local f = T.onPluggedDrive
    return not (f and f(vehicle))
end

-- Frunk container test (both sides: inventory page on the client, transfers on the server). Same rule as
-- vanilla Vehicles.ContainerAccess.TruckBed (Vehicles.lua:24-34) with the frunk lid (EngineDoor) as the door.
function T.ContainerAccess.Frunk(vehicle, part, chr)
    if chr:getVehicle() then return false end
    if not vehicle:isInArea(part:getArea(), chr) then return false end
    return T.lidOpen(vehicle, "EngineDoor")
end

-- a lid (door part) counts as open when it is open, removed, or the car has none
function T.lidOpen(vehicle, id)
    local lid = vehicle:getPartById(id)
    if lid and lid:getDoor() and lid:getInventoryItem() then return lid:getDoor():isOpen() end
    return true
end

-- Cybertruck bed, the vault (owner's manual p.60-61): from the rear (the bed's area) with the tailgate or the
-- tonneau open; from either side (area BedSide) with the tonneau open.
function T.ContainerAccess.Vault(vehicle, part, chr)
    if chr:getVehicle() then return false end
    if vehicle:isInArea(part:getArea(), chr) then return T.lidOpen(vehicle, "TrunkDoor") or T.lidOpen(vehicle, "TrunkTonneau") end
    return vehicle:isInArea("BedSide", chr) and T.lidOpen(vehicle, "TrunkTonneau")
end

-- ---- authorization ----
-- VehicleManager present: its canUse (server authoritative, client projection; MinidoracatVehicleManager_API.lua:141).
-- Otherwise: holds this car's key or the key is in the ignition (ISVehicleMenu.lua:96); the key card / phone key also
-- counts from a wallet or bag (Keys.lua; vanilla haveThisKeyId only sees loose keys and keyrings). A hotwired car counts
-- like a key in the ignition ("HOTWIRED", user 2026-10-28, decisions.md keyless rules): vanilla starts it without a key
-- (ISVehicleMenu.lua:100-101), so whoever sits in it already drives it. The flag is saved and synced to clients
-- (BaseVehicle.java:2659,2767,8594; network/fields/vehicle/VehicleProperties.java:19,54).
function T.authorized(player, vehicle, perm)
    if not player or not vehicle then return false, "NO_TARGET" end
    local api = MinidoracatVehicleManagerAPI
    if api and api.canUse then return api.canUse(player, vehicle, perm or "DRIVE", { mod = T.MODULE }) end
    if SandboxVars and SandboxVars.VehicleEasyUse then return true, "EASY_USE" end
    if vehicle:isKeysInIgnition() or player:getInventory():haveThisKeyId(vehicle:getKeyId()) then return true, "KEY" end
    if T.Keys and T.Keys.card and (T.Keys.card(player, vehicle) or T.Keys.phoneKey(player, vehicle)) then return true, "KEY" end
    if vehicle:isHotwired() then return true, "HOTWIRED" end
    return false, "NO_KEY"
end
-- VehicleManager refusals that keep their own reason text (IGUI_MinidoracatTesla_Deny_<reason>); any other is NOT_OWNER
T.VM_REASONS = { RENT_LOCKED = true, FACTION_PAUSED = true, QUARANTINED = true }

-- Admin: same capability VehicleManager uses (MinidoracatVehicleManager_OwnershipSystem.lua:192-195).
function T.isAdmin(player)
    if not isServer() or not player or not Capability then return false end
    return checkPermissions(player, Capability.ManipulateVehicle) == true
end

-- The account a player speaks for (sentry owner, notifications, the offline inbox), or nil; family conventions.md,
-- player identity. The server's getUsername() is the client's word: a respawn or a split-screen join names itself in
-- ConnectCoopPacket (only names connected right now are refused, ConnectCoopPacket.java:65-97; a dead slot 0 may be
-- replaced too, :69-109) and the server takes it as the player's name (GameServer.java:2838,2848); no Lua API reads
-- the connection's login name. So on a server: a split-screen guest (slot 1-3, its host's SteamID) has none; on a
-- Steam server the name must be bound to this SteamID (Store.lua T.Store.verify); a no-steam server has nothing to
-- check it against and takes the name. SP: the username; an MP client: slot 0's username, none for a split-screen
-- guest (no Steam binding check there: UI hints only, the server decides).
T.steamMode = function() return getSteamModeActive() == true end -- both overridable: E2E (conventions.md item 6)
T.sidOf = function(player) return player:getSteamID() end -- a long rounded to a double in Lua: compare, never print
function T.account(player)
    if not player then return nil end
    if not isServer() then -- SP by name; an MP client none for a split-screen guest, like its server (hints only)
        if isClient() and player:getPlayerNum() ~= 0 then return nil end
        return player:getUsername()
    end
    if player:getPlayerNum() ~= 0 then return nil end
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" then return nil end
    if not T.steamMode() then return name end
    return T.Store.verify(player, name) and name or nil
end

-- ---- server -> client ----
-- SP: sendServerCommand is a no-op off the server (LuaManager.java:8956-8960), so call the handler directly.
function T.send(player, cmd, args)
    if isServer() then
        sendServerCommand(player, T.MODULE, cmd, args or {})
    elseif not isClient() then
        local fn = T.ClientCommands[cmd]
        if fn then fn(args or {}) end
    end
end
function T.deny(player, reason, vid)
    T.send(player, "deny", { reason = reason, vid = vid })
end
-- Text of IGUI_MinidoracatTesla_Deny_<reason>; CAMP_LOW_BATTERY carries the sandbox limit as %1, NO_LINK the Bluetooth
-- range (Keys.btRange, this side's SandboxVars: the server sends the code only). A summon refused by
-- AutoDrive (Remote.lua ACT.summon) carries a whole translation key instead: AutoDrive's "UI_MinidoracatAutoDrive_...",
-- or VehicleManager's "IGUI_MVM_..." from its wrapper around startSummon. Tesla's own reasons are bare CODES.
function T.denyText(reason)
    if type(reason) == "string" and (reason:find("UI_", 1, true) == 1 or reason:find("IGUI_", 1, true) == 1) then
        return getText(reason)
    end
    local key = "IGUI_MinidoracatTesla_Deny_" .. tostring(reason)
    if reason == "CAMP_LOW_BATTERY" then return getText(key, tostring(T.Camp.minPct())) end
    if reason == "NO_LINK" then return getText(key, tostring(T.Keys.btRange())) end
    return getText(key)
end

-- ---- line breaks (client layout: the phone app's wrapped lines, the radial menu's second line) ----
-- The family rules (pitfalls.md "self-written wrapping", "CJK code point ranges", "French punctuation"), copied from
-- MinidoracatUI TextWrap.cut (this mod does not require the UI framework). A line may end at a space or beside a CJK
-- character, not before closing punctuation (Japanese small kana, the long vowel mark) nor after an opening one; the
-- space before French ":;!?" and the one between a number and a CJK unit ("2 マス") hold. Kahlua strings are UTF-16
-- units, the harness's Lua is UTF-8 bytes: cuts land on character boundaries in both. Numbers only (Kahlua cuts
-- non-ASCII literals). The app's old wrap took the last space in the right half: Japanese "...から 2 / マス...".
-- One difference from TextWrap: Hangul syllables break at spaces only, like Korean UIs do (keep-all); breaking them
-- anywhere cut words in two (E2E tesla-ctlang-1031n-ko: "...공급하 / 지 않습니다").
local UTF16 = (function() local ok, c = pcall(string.char, 256); return ok and string.byte(c) == 256 end)()
local ASTRAL = 0x10000
local function codeSet(codes) local t = {}; for _, c in ipairs(codes) do t[c] = true end; return t end
local NO_START = codeSet({ 0x21, 0x29, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, 0x5D, 0x7D, 0x2019, 0x201D, 0x2026,
    0x3001, 0x3002, 0x3005, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B, 0x301C,
    0x309B, 0x309C, 0x309D, 0x309E, 0x30A0, 0x30FB, 0x30FD, 0x30FE,
    0xFF01, 0xFF05, 0xFF09, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF3D, 0xFF5D, 0xFF5E, 0xFF61, 0xFF63, 0xFF64,
    0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096,
    0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, 0x30FC })
local NO_END = codeSet({ 0x28, 0x5B, 0x7B, 0x2018, 0x201C, 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016,
    0x3018, 0x301A, 0x301C, 0x301D, 0xFF08, 0xFF3B, 0xFF5B, 0xFF5E, 0xFF62 })
local FRENCH_BEFORE, FRENCH_AFTER = codeSet({ 0x21, 0x3A, 0x3B, 0x3F, 0xBB }), 0xAB
-- CJK ideographs and symbols, kana, fullwidth forms, astral characters: a line may break on either side
local function ideographic(c)
    return (c >= 0x2E80 and c <= 0x9FFF) or (c >= 0xF900 and c <= 0xFAFF)
        or (c >= 0xFE30 and c <= 0xFE4F) or (c >= 0xFF00 and c <= 0xFFEF) or c >= ASTRAL
end
-- n moved back onto a character boundary (the first n units never split a character)
local function boundary(s, n)
    if UTF16 then
        local unit = n > 0 and string.byte(s, n) or 0
        return (unit >= 0xD800 and unit <= 0xDBFF) and n - 1 or n
    end
    while n > 0 do
        local unit = string.byte(s, n + 1)
        if not unit or unit < 128 or unit >= 192 then break end
        n = n - 1
    end
    return n
end
local function codeAt(s, i)
    local unit = string.byte(s, i)
    if UTF16 then return (unit >= 0xD800 and unit <= 0xDFFF) and ASTRAL or unit end
    if unit < 0xC0 then return unit end
    if unit < 0xE0 then return (unit - 0xC0) * 64 + ((string.byte(s, i + 1) or 0x80) - 0x80) end
    if unit >= 0xF0 then return ASTRAL end
    local b2, b3 = string.byte(s, i + 1, i + 2)
    return (unit - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
end
-- the spaces around unit n hold both sides: after a left guillemet, before French ":;!?" / a right guillemet, or
-- between an ASCII digit (or digit %) and a CJK character
local function gluedSpace(s, n)
    local i = n
    while i > 0 and string.byte(s, i) == 32 do i = i - 1 end
    if i > 0 and codeAt(s, boundary(s, i - 1) + 1) == FRENCH_AFTER then return true end
    local j, len = n + 1, #s
    while j <= len and string.byte(s, j) == 32 do j = j + 1 end
    if i == 0 or j > len then return false end
    local right = codeAt(s, j)
    if FRENCH_BEFORE[right] then return true end
    local left = string.byte(s, i)
    if left == 37 and i > 1 then left = string.byte(s, i - 1) end
    return left >= 0x30 and left <= 0x39 and ideographic(right)
end
local function breakable(s, n)
    local left, right = codeAt(s, boundary(s, n - 1) + 1), codeAt(s, n + 1)
    if left == 32 or right == 32 then return not gluedSpace(s, n) end
    return (ideographic(left) or ideographic(right)) and not NO_START[right] and not NO_END[left]
end
-- the head of `s` that fits `maxW` in `font`, ending at a break, and the rest; no break at all: cut where it fits;
-- not one character fits: that character anyway (a caller's loop always moves on)
function T.cutLine(s, maxW, font)
    local tm = getTextManager()
    local low, high, best = 1, #s, 0
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local n = boundary(s, mid)
        if n >= 1 and tm:MeasureStringX(font, s:sub(1, n)) <= maxW then best, low = n, mid + 1 else high = mid - 1 end
    end
    local n = best
    if best == 0 then
        repeat n = n + 1 until boundary(s, n) == n
    else
        while n > 0 and not breakable(s, n) do n = boundary(s, n - 1) end
        if n == 0 then n = best end
    end
    return (s:sub(1, n):gsub("%s+$", "")), (s:sub(n + 1):gsub("^%s+", ""))
end
local function wrapLines(s, maxW, font)
    local tm, out = getTextManager(), {}
    while tm:MeasureStringX(font, s) > maxW do
        local line, rest = T.cutLine(s, maxW, font)
        out[#out + 1] = line
        s = rest
    end
    out[#out + 1] = s
    return out
end
-- `s` broken into lines of at most `maxW` in `font`, joined by "\n" (vanilla's radial menu draws one centre line per
-- "\n", RadialMenu.java:157-198). Balanced: the narrowest width that still needs no more lines, so centred lines come
-- out even ("Powers the home / in a blackout", not "Powers the home in a / blackout"). Menu build time only.
function T.wrapText(s, maxW, font)
    local lines = wrapLines(s, maxW, font)
    if #lines < 2 then return s end
    local lo, hi = 1, maxW
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if #wrapLines(s, mid, font) <= #lines then hi = mid else lo = mid + 1 end
    end
    return table.concat(wrapLines(s, lo, font), "\n")
end

-- ---- client -> server ----
function T.request(player, cmd, args)
    sendClientCommand(player, T.MODULE, cmd, args or {}) -- SP routes to OnClientCommand too (LuaManager.java:8936-8950)
end

return T
