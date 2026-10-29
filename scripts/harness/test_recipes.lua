-- 專用伺服器補學本 MOD 配方（Recipes.lua）：伺服器開始製作時補學、電工升級時補學並送配方清單；
-- 只認三條配方名稱、等級不夠不學、其他技能升級不送、單機與客戶端不包。
local check = H.check
local SRC = "MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42/42/media/lua/server/MinidoracatTesla/Recipes.lua"
local saved = { Events = Events, ISHandcraftAction = ISHandcraftAction, Perks = Perks,
    getScriptManager = getScriptManager, sendSyncPlayerFields = sendSyncPlayerFields }
local hooks = {} -- this file's events only: nothing it adds reaches later tests
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(fn) hooks[name] = hooks[name] or {}; table.insert(hooks[name], fn) end, Remove = function() end }
    rawset(t, name, e)
    return e
end })
local function fire(name, ...) for _, fn in ipairs(hooks[name] or {}) do fn(...) end end

local starts, RESULT = 0, {}
local function vanillaStart() starts = starts + 1; return RESULT end
Perks = { Electricity = "Electricity", Woodwork = "Woodwork" }
-- AutoLearnAny Electricity `need`: learns only once the character's level reaches it (CraftRecipe.java:862-872,890-905)
local asks = 0
local function recipe(name, need)
    return { name = name, need = need, getName = function(self) return self.name end,
        checkAutoLearnAnySkills = function(self, c)
            asks = asks + 1
            if c.elec >= self.need then c.known[self.name] = true end
        end }
end
local byName = {}
for _, r in ipairs({ recipe("MinidoracatTesla_MakeWallConnector", 3), recipe("MinidoracatTesla_MakeMobileConnector", 2),
    recipe("MinidoracatTesla_MakeDriveUnitParts", 4) }) do byName[r.name] = r end
getScriptManager = function() return { getCraftRecipe = function(_, n) return byName[n] end } end
local syncs = {}
sendSyncPlayerFields = function(p, flags) syncs[#syncs + 1] = { p = p, flags = flags } end
local function character(elec)
    return { elec = elec, known = {}, isRecipeActuallyKnown = function(self, r) return self.known[r:getName()] == true end }
end
local function start(c, r) return ISHandcraftAction.serverStart({ character = c, craftRecipe = r }) end
local wall, mobile = byName.MinidoracatTesla_MakeWallConnector, byName.MinidoracatTesla_MakeMobileConnector

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
local n = asks
start(c, wall)
check(asks == n and starts == 3, "already learned: no learning asked")
local alike = recipe("MinidoracatTesla_MakeSomethingElse", 0) -- named like ours, not one of the three
local other = recipe("Base.MakeSpearCrafted", 0)
start(c, alike)
start(c, other)
check(asks == n and not c.known[alike.name] and not c.known[other.name] and starts == 5,
    "another recipe, even one named like ours: never learned here")
check(start(c, nil) == RESULT and starts == 6, "no recipe: straight to vanilla")

local p = character(2)
fire("LevelPerk", p, Perks.Woodwork)
check(#syncs == 0 and not p.known[mobile.name], "another skill's level-up: nothing learned here, nothing sent")
fire("LevelPerk", p, Perks.Electricity)
check(p.known[mobile.name] == true and not p.known[wall.name] and #syncs == 1 and syncs[1].p == p and syncs[1].flags == 1,
    "Electricity level-up: ours up to the level learned, the recipe list sent to that player")
byName.MinidoracatTesla_MakeDriveUnitParts = nil -- its script missing
logs = #H.logLines
fire("LevelPerk", p, Perks.Electricity)
fire("LevelPerk", p, Perks.Electricity)
check(#H.logLines == logs + 1 and #syncs == 3, "a recipe script not loaded: logged once, the list still sent")

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
for k, v in pairs(saved) do _G[k] = v end
