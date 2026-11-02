-- Body location of the hat hider (server/MinidoracatTesla/HatHide.lua). ModRegistries runs this before the item scripts
-- load (GameWindow.java:201-203, IngameState.java:1045-1048, GameServer.java:1446-1447), so the item script names it.
-- The id is saved with the worn item (IsoPlayer.java:1255-1259): never rename it. Without the MOD a save drops it
-- (ItemBodyLocation.get -> null, Registry.java:43-44; the worn entry is skipped).
MinidoracatTeslaHatLoc = ItemBodyLocation.register("MinidoracatTesla:HatHide")
