-- Speed and distance units of this player's displays (dashboard, charge card, phone app): metric, or imperial by
-- the mod option (user 2026-11-23: Tesla's own option, AutoDrive keeps its own). Display only: every stored and
-- sent value stays km, km/h and tiles. Design: .claude/skills/tesla-dev/references/hud.md "units".
require "MinidoracatTesla/Core"

local T = MinidoracatTesla
local U = {}
T.Units = U
-- AutoDrive's HUD.MPH: a whole km/h reads the same mph here as on its FSD card
local MI = 0.621371

-- U.opt: the combo (nil without PZAPI). The displays compare imperial() each update and rebuild on a change,
-- so a value set any way (options page, vanilla's load, an E2E setValue) shows within one update
function U.imperial()
    local o = U.opt
    return o ~= nil and o:getValue() == 2
end
-- whole km or km/h -> the number shown. The speed is rounded in km/h first, then converted: no state, and a
-- cruise at a whole km/h limit reads the same on AutoDrive's card (70 km/h is 43.496 mph, on the rounding edge)
function U.len(km) return U.imperial() and math.floor(km * MI + 0.5) or km end
-- tiles (= m) -> feet, in tens from 10 ft (a tile is 3.3 ft)
function U.feet(m)
    local f = m * 3.28084
    return f < 10 and math.floor(f + 0.5) or math.floor(f / 10 + 0.5) * 10
end
-- tiles -> the phone app's key and its number: "Feet" up to 500, then "Miles" to one decimal (from 0.095 mi,
-- which reads "0.1")
function U.dist(m)
    local t = m / 160.9344 -- tenths of a mile
    if t < 0.95 then return "Feet", tostring(U.feet(m)) end
    t = math.floor(t + 0.5)
    return "Miles", tostring(math.floor(t / 10)) .. "." .. tostring(t % 10)
end

-- the id and "Units" are in players' ModOptions.ini: never rename them
if PZAPI and PZAPI.ModOptions then
    local o = PZAPI.ModOptions:create(T.MODULE, "IGUI_MinidoracatTesla_Options")
    -- a description, not a tooltip: vanilla's options page gives a combo box none (MainOptions.lua:2910-2927)
    o:addDescription("IGUI_MinidoracatTesla_OptionsDescription")
    U.opt = o:addComboBox("Units", "IGUI_MinidoracatTesla_Units")
    U.opt:addItem("IGUI_MinidoracatTesla_UnitsMetric", true)
    U.opt:addItem("IGUI_MinidoracatTesla_UnitsImperial")
    -- vanilla wipes ModOptions.ini when Apply is pressed with no mod's options at the main menu; the family UI
    -- framework (not required: only when installed) restores this mod's lines. OnGameBoot: every mod's Lua is
    -- loaded and vanilla's load comes after
    Events.OnGameBoot.Add(function()
        local UI = MinidoracatUI and MinidoracatUI.v1
        if UI and UI.API_MAJOR == 1 and type(UI.API_REVISION) == "number" and UI.API_REVISION >= 23
            and UI.CAPABILITIES and UI.CAPABILITIES.modOptionsBackup and UI.ModOptionsBackup then
            local n = UI.ModOptionsBackup.protect(o)
            if type(n) == "number" and n > 0 then T.log("restored " .. n .. " settings from the backup (ModOptions.ini was wiped)") end
        end
    end)
end

return U
