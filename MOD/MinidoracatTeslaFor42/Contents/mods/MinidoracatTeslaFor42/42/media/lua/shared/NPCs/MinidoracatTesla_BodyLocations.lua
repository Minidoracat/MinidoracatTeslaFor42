-- The hat hider's location hides whatever is worn in base:hat and base:fullhat (PopTemplateManager.isItemModelHidden,
-- PopTemplateManager.java:177,202-220): model and texture both. Rules only add (BodyLocation.java:31-37), so the hiding
-- is switched by wearing the hider (server/MinidoracatTesla/HatHide.lua), not by the rule.
require "NPCs/BodyLocations"

local group, loc = BodyLocations.getGroup("Human"), MinidoracatTeslaHatLoc
group:getOrCreateLocation(loc)
group:setHideModel(loc, ItemBodyLocation.HAT)
group:setHideModel(loc, ItemBodyLocation.FULL_HAT)
