-- 專用伺服器補學本 MOD 配方（Recipes.lua）：伺服器開始製作時補學、電工或金屬焊接升級時補學並送配方清單；
-- 只認七條配方名稱、等級不夠不學、其他技能升級不送、單機與客戶端不包。
-- 升級件戰利品（Charging.lua C.UPGRADE_LOOT）：指定清單各一組、重載不疊加、比行動充電器稀有。
local check = H.check
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/Recipes.lua"
local GLOBALS = { "Events", "ISHandcraftAction", "Perks", "getScriptManager", "sendSyncPlayerFields" }
local saved = {}
for _, g in ipairs(GLOBALS) do saved[g] = _G[g] end -- nil ones too: set back to nil at the end
local hooks = {} -- this file's events only: nothing it adds reaches later tests
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(fn) hooks[name] = hooks[name] or {}; table.insert(hooks[name], fn) end, Remove = function() end }
    rawset(t, name, e)
    return e
end })
local function fire(name, ...) for _, fn in ipairs(hooks[name] or {}) do fn(...) end end

local starts, RESULT = 0, {}
local function vanillaStart() starts = starts + 1; return RESULT end
Perks = { Electricity = "Electricity", MetalWelding = "MetalWelding", Woodwork = "Woodwork" }
-- AutoLearnAny `perk` `need`: learns only once the character's level reaches it (CraftRecipe.java:862-872,890-905)
local asks = 0
local function recipe(name, need, perk)
    return { name = name, need = need, perk = perk or "Electricity", getName = function(self) return self.name end,
        checkAutoLearnAnySkills = function(self, c)
            asks = asks + 1
            if c[self.perk] >= self.need then c.known[self.name] = true end
        end }
end
local byName = {}
for _, r in ipairs({ recipe("MinidoracatTesla_MakeWallConnector", 3), recipe("MinidoracatTesla_MakeMobileConnector", 2),
    recipe("MinidoracatTesla_MakeDriveUnitParts", 4), recipe("MinidoracatTesla_MakeSupercharger", 6),
    recipe("MinidoracatTesla_MakeArmorInner", 3, "MetalWelding"), recipe("MinidoracatTesla_MakeArmorOuter", 5, "MetalWelding"),
    recipe("MinidoracatTesla_MakeFridge", 4) }) do byName[r.name] = r end
getScriptManager = function() return { getCraftRecipe = function(_, n) return byName[n] end } end
local syncs = {}
sendSyncPlayerFields = function(p, flags) syncs[#syncs + 1] = { p = p, flags = flags } end
local function character(elec, weld)
    return { Electricity = elec, MetalWelding = weld or 0, known = {},
        isRecipeActuallyKnown = function(self, r) return self.known[r:getName()] == true end }
end
local function start(c, r) return ISHandcraftAction.serverStart({ character = c, craftRecipe = r }) end
local wall, mobile, sc = byName.MinidoracatTesla_MakeWallConnector, byName.MinidoracatTesla_MakeMobileConnector,
    byName.MinidoracatTesla_MakeSupercharger
local inner, outer, fridge = byName.MinidoracatTesla_MakeArmorInner, byName.MinidoracatTesla_MakeArmorOuter,
    byName.MinidoracatTesla_MakeFridge

H.section("recipes: the server learns this MOD's recipes its client already knows (dedicated server)")
H.stub("Entity/TimedActions/ISHandcraftAction")
ISHandcraftAction = { serverStart = vanillaStart }
H.side(false, true)
dofile(SRC)
local c, logs = character(3), #H.logLines
check(start(c, wall) == RESULT and starts == 1 and c.known[wall.name] == true,
    "a craft of ours the server has not learned, level reached: learned, then vanilla's serverStart (its result kept)")
check(#H.logLines == logs + 1 and H.logLines[#H.logLines]:find("learned on the server at use", 1, true) ~= nil,
    "... and logged once")
local low = character(1)
start(low, wall)
check(starts == 2 and not low.known[wall.name], "level too low: nothing learned, vanilla still runs (and refuses)")
local five = character(5)
start(five, sc)
check(starts == 3 and not five.known[sc.name], "Supercharger at Electricity 5: nothing learned (it needs 6)")
local six = character(6)
start(six, sc)
check(starts == 4 and six.known[sc.name] == true, "... at 6: learned, then vanilla's serverStart")
local n = asks
start(c, wall)
check(asks == n and starts == 5, "already learned: no learning asked")
local alike = recipe("MinidoracatTesla_MakeSomethingElse", 0) -- named like ours, not one of the seven
local other = recipe("Base.MakeSpearCrafted", 0)
start(c, alike)
start(c, other)
check(asks == n and not c.known[alike.name] and not c.known[other.name] and starts == 7,
    "another recipe, even one named like ours: never learned here")
check(start(c, nil) == RESULT and starts == 8, "no recipe: straight to vanilla")
local welder = character(0, 4)
start(welder, inner)
start(welder, outer)
check(starts == 10 and welder.known[inner.name] == true and not welder.known[outer.name],
    "upgrade kits at Metal Welding 4: Reinforcement Kit learned at use, Bull Bar Kit (5) not")
local sparky = character(4)
start(sparky, fridge)
check(starts == 11 and sparky.known[fridge.name] == true, "Car Fridge at Electricity 4: learned at use")

local p = character(2)
fire("LevelPerk", p, Perks.Woodwork)
check(#syncs == 0 and not p.known[mobile.name], "another skill's level-up: nothing learned here, nothing sent")
fire("LevelPerk", p, Perks.Electricity)
check(p.known[mobile.name] == true and not p.known[wall.name] and #syncs == 1 and syncs[1].p == p and syncs[1].flags == 1,
    "Electricity level-up: ours up to the level learned, the recipe list sent to that player")
local w = character(0, 5)
fire("LevelPerk", w, Perks.MetalWelding)
check(w.known[inner.name] == true and w.known[outer.name] == true and not w.known[fridge.name] and #syncs == 2
    and syncs[2].p == w, "Metal Welding level-up: both armour kits learned, the list sent")
syncs = {}
byName.MinidoracatTesla_MakeDriveUnitParts = nil -- its script missing
logs = #H.logLines
fire("LevelPerk", p, Perks.Electricity)
fire("LevelPerk", p, Perks.Electricity)
check(#H.logLines == logs + 1 and #syncs == 2, "a recipe script not loaded: logged once, the list still sent")

H.section("recipes: SP and the MP client leave crafting alone")
for _, s in ipairs({ { false, false }, { true, false } }) do
    hooks.LevelPerk = nil
    ISHandcraftAction = { serverStart = vanillaStart }
    H.side(s[1], s[2])
    dofile(SRC)
    check(ISHandcraftAction.serverStart == vanillaStart and hooks.LevelPerk == nil,
        (s[1] and "MP client" or "SP") .. ": serverStart not wrapped, no LevelPerk hook")
end

H.side(false, true)
for _, g in ipairs(GLOBALS) do _G[g] = saved[g] end

H.section("upgrade kit loot")
local C = MinidoracatTesla.Charge
local INNER, OUTER, FRIDGE = "Base.MinidoracatTesla_ArmorInner", "Base.MinidoracatTesla_ArmorOuter", "Base.MinidoracatTesla_Fridge"
ProceduralDistributions = { list = {
    GarageMechanics = { items = { "CarBatteryCharger", 4, "Wrench", 10 } },
    MechanicSpecial = { items = { "ModernTire3", 0.5 } },
    CampingStoreCases = { items = { "Cooler", 20 } },
    CrateElectronics = { rolls = 4, items = {} },
    KitchenCutlery = { items = { "Fork", 10 } },
} }
H.fire("OnPostDistributionMerge")
H.fire("OnPostDistributionMerge") -- a reload must not stack our pairs
local L = ProceduralDistributions.list
local function weight(items, item)
    local n, wt = 0, nil
    for i = 1, #items - 1, 2 do if items[i] == item then n, wt = n + 1, items[i + 1] end end
    return n, wt
end
local gm = L.GarageMechanics.items
local ni, wi = weight(gm, INNER)
local no, wo = weight(gm, OUTER)
local nf, wf = weight(gm, FRIDGE)
local _, wm = weight(gm, C.LOOT_ITEM)
check(ni == 1 and no == 1 and nf == 1 and wi == 0.2 and wo == 0.1 and wf == 0.2 and wm == 2,
    "a garage: one pair of each kit, also after a reload, beside the Mobile Connector")
check(select(2, weight(L.MechanicSpecial.items, INNER)) == 0.5 and select(2, weight(L.MechanicSpecial.items, OUTER)) == 0.2
    and weight(L.MechanicSpecial.items, FRIDGE) == 0, "a mechanic's special shelf: armour only, the bull bar rarer")
check(select(2, weight(L.CampingStoreCases.items, FRIDGE)) == 1 and weight(L.CampingStoreCases.items, INNER) == 0
    and select(2, weight(L.CrateElectronics.items, FRIDGE)) == 0.1, "camping and electronics: the fridge only")
check(#L.KitchenCutlery.items == 2, "lists not chosen stay as they are")
local okRare = true
for item, where in pairs(C.UPGRADE_LOOT) do
    for name, wt in pairs(where) do
        if wt >= 2 or (item == OUTER and wt > C.UPGRADE_LOOT[INNER][name]) then okRare = false end
    end
end
check(okRare, "every kit under the Mobile Connector's lowest store weight (2); the bull bar never above the inner kit")
ProceduralDistributions = nil
