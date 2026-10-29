-- The Tesla recipes are AutoLearnAny Electricity (scripts/recipes/MinidoracatTesla_recipes.txt). On a dedicated server
-- vanilla keeps the two copies of a character's known recipes apart (E2E craft-chargers-mp: tesla-craftmp-1030b, and
-- after a relog tesla-craftmp-relog-1030a):
-- * the client learns them at login (IsoWorld.java:2424 checkAutoLearn on the local player); the server only on a
--   level-up (server/XpSystem/XpUpdate.lua:197-198). A character who had the level before this MOD was added knows
--   them on the client only: the window lets them craft, the action runs, and the server's perform refuses
--   (CraftRecipeManager.java:348, CraftRecipeData.java:490-509): nothing used, nothing made.
-- * a level-up learns them on the server only and nothing sends the list (SyncPlayerFieldsPacket PF_Recipes is sent
--   only by ISResearchRecipe / ISReadABook): the window says "not learned" until the next login.
-- Only this MOD's recipes, one by one (CraftRecipe.checkAutoLearnAnySkills: not known yet, skill reached, Inventive
-- one level less; CraftRecipe.java:862-872,890-905), as AutoDrive's MDAD_Server.lua onRecipeRescan: the global
-- ScriptManager.checkAutoLearn would also teach other MODs' recipes.
if not isServer() then return end
require "Entity/TimedActions/ISHandcraftAction"
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local PREFIX = "MinidoracatTesla_"
local RECIPES = { "MinidoracatTesla_MakeWallConnector", "MinidoracatTesla_MakeMobileConnector", "MinidoracatTesla_MakeDriveUnitParts" }

-- the server half of a craft (NetTimedAction.java:95-104 -> ISHandcraftAction.lua:67-83), before vanilla rebuilds the
-- logic: learn this recipe if the level already gives it. A level too low learns nothing and complete() still refuses.
local serverStart = ISHandcraftAction.serverStart
function ISHandcraftAction:serverStart()
    local r = self.craftRecipe
    if r and r:getName():sub(1, #PREFIX) == PREFIX and not self.character:isRecipeActuallyKnown(r) then
        r:checkAutoLearnAnySkills(self.character)
        if self.character:isRecipeActuallyKnown(r) then T.log("craft " .. r:getName() .. ": learned on the server at use") end
    end
    return serverStart(self)
end

-- an Electricity level-up (IsoGameCharacter.java:4810-4833): learn ours here too (not relying on vanilla's handler
-- running first) and send the list to that player (LuaManager.java:4273; the client adds what it lacks,
-- SyncPlayerFieldsPacket.java:86-93). Electricity levels only: a few packets per character, ever.
Events.LevelPerk.Add(function(owner, perk)
    if perk ~= Perks.Electricity then return end
    local sm = getScriptManager()
    for _, name in ipairs(RECIPES) do
        local r = sm:getCraftRecipe(name)
        if r then r:checkAutoLearnAnySkills(owner) end
    end
    sendSyncPlayerFields(owner, 1)
end)
