-- Tesla HUD (client): vanilla dashboard hand-over, hudRect contract, zero-allocation redraw, read model, radial menu.
-- Engine-only behaviour (real drawing, focus, screenshots) is covered by E2E hud-sp / hud-mp.
local check = H.check

-- ---------------------------------------------------------------- client fakes (only what HUD*.lua touches)
H.side(true, false)
local SCREEN_W, SCREEN_H = 1920, 1080
function getPlayerScreenLeft() return 0 end
function getPlayerScreenTop() return 0 end
function getPlayerScreenWidth() return SCREEN_W end
function getPlayerScreenHeight() return SCREEN_H end
UIFont = { Small = "Small", Medium = "Medium", Large = "Large" }
local fontH = 19
function getTextManager()
    return { getFontHeight = function() return fontH end, MeasureStringX = function(_, _, s) return #s * 8 end }
end
function getTexture(path) return { path = path } end
BaseVehicle = { getFakeSpeedModifier = function() return 1.0 end }
local sounds = {}
function getSpecificPlayer() return { playSound = function(_, s) sounds[#sounds + 1] = s end } end
HaloTextHelper = { addBadText = function() end }
UIManager = { getSpeedControls = function() return { getCurrentGameSpeed = function() return 1 end } end }

local drawCalls = 0
ISUIElement = {}
ISUIElement.__index = ISUIElement
function ISUIElement:derive(name) local t = { Type = name }; setmetatable(t, { __index = self }); t.__index = t; return t end
function ISUIElement:new(x, y, w, h)
    local o = { x = x, y = y, width = w, height = h, visible = true }
    setmetatable(o, self); self.__index = self
    return o
end
function ISUIElement:initialise() end
function ISUIElement:instantiate()
    self.javaObject = {
        DrawSubTextureRGBA = function() drawCalls = drawCalls + 1 end,
        DrawText = function(_, font, text, x, y)
            drawCalls = drawCalls + 1
            lastText = text
            if type(x) ~= "number" or type(y) ~= "number" then badText = (badText or 0) + 1 end -- Java NPEs on nil
        end,
    }
end
function ISUIElement:setWidth(w) self.width = w end
function ISUIElement:setHeight(h) self.height = h end
function ISUIElement:setX(x) self.x = x end
function ISUIElement:setY(y) self.y = y end
function ISUIElement:setVisible(v) self.visible = v end
function ISUIElement:isVisible() return self.visible end
function ISUIElement:addToUIManager() self.inManager = true end
function ISUIElement:removeFromUIManager() self.inManager = false end

-- vanilla dashboard: setVehicle mirrors ISVehicleDashboard.lua:180-229 (visible + add, or remove)
ISVehicleDashboard = ISUIElement:derive("ISVehicleDashboard")
function ISVehicleDashboard:setVehicle(vehicle)
    self.vehicle = vehicle
    if not vehicle then self:removeFromUIManager(); return end
    self:setVisible(true)
    self:addToUIManager()
end
H.stub("ISUI/ISUIElement")
H.stub("Vehicles/ISUI/ISVehicleDashboard")

-- radial menu: vanilla toggles (ISVehicleMenu.lua:67-76) and adds its own "Sleep" slice (:225); `hotwireSlice` set =
-- vanilla's hotwire slice for a keyless driver (:109-121) before Sleep
local menu, hotwireSlice = { slices = {}, open = false }, nil
function menu:isReallyVisible() return self.open end
function menu:addSlice(text, tex, fn, a1, a2, a3)
    self.slices[#self.slices + 1] = { text = text, tex = tex, fn = fn, a1 = a1, a2 = a2, a3 = a3, command = { fn, a1, a2, a3 } }
end
function menu:setSliceText(i, text) self.slices[i].text = text end -- ISRadialMenu.lua:55
function menu:setSliceTexture(i, tex) self.slices[i].tex = tex end
function getPlayerRadialMenu() return menu end
ISVehicleMenu = { onSleep = function() end, onHotwire = function() end, onStartEngine = function() end }
ISVehicleMenu.showRadialMenu = function()
    if menu.open then menu.open = false; menu.slices = {}; return end
    menu.slices = {}; menu:addSlice("vanilla")
    if hotwireSlice then menu:addSlice(hotwireSlice.text, nil, hotwireSlice.fn) end
    menu:addSlice("Sleep", nil, ISVehicleMenu.onSleep); menu.open = true
end
H.stub("Vehicles/ISUI/ISVehicleMenu")
ISWorldObjectContextMenu = { getBedQuality = function() return "badBed" end } -- vanilla: any car seat (ISWorldObjectContextMenu.lua:2923-2934)
H.stub("ISUI/ISWorldObjectContextMenu")

require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/HUD"
require "MinidoracatTesla/HUDRadial"
require "MinidoracatTesla/Thruster" -- shared (in game every shared file loads before the client's)
local T = MinidoracatTesla
local HUD = T.HUD

-- vehicle fake on top of H.vehicle (doors, transmission, throttle)
local function car(o)
    local v = H.vehicle(o)
    v.gear, v.throttle, v.lights, v.locked = 0, 0, false, false
    for _, id in ipairs({ "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight", "TrunkDoor" }) do
        local d = { open = false }
        function d:isOpen() return self.open end
        v.parts[id] = { door = d, getDoor = function(self) return self.door end, getModData = function() return {} end,
            getInventoryItem = function() return {} end }
    end
    function v:getTransmissionNumber() return self.gear end
    function v:getThrottle() return self.throttle end
    function v:getHeadlightsOn() return self.lights end
    function v:areAllDoorsLocked() return self.locked end
    function v:isStarting() return false end
    function v:isHotwired() return false end
    return v
end

-- ---------------------------------------------------------------- hand-over
H.section("dashboard hand-over")
local dash = ISVehicleDashboard:new(0, 0, 552, 121)
dash.playerNum = 0
local _, _, _, _, vis0 = MinidoracatTeslaAPI.hudRect(0)
check(vis0 == false, "hudRect: no HUD yet -> visible=false")

local tesla = car({ kwh = 39.2 }) -- 50% of the 78.4 kWh pack
dash:setVehicle(tesla)
local h = HUD.get(0)
check(dash.inManager == true and dash.visible == false, "tesla: vanilla stays in UIManager but invisible")
check(h.inManager == true and h.vehicle == tesla, "tesla: HUD shown and attached")
local x, y, w, hh, vis = MinidoracatTeslaAPI.hudRect(0)
check(vis == true and w == 506 and y + hh == SCREEN_H and x == (SCREEN_W - 506) / 2,
    "hudRect: 506 wide at S=1 (four quick keys), bottom-centre of the player screen")

dash:removeFromUIManager() -- joypad inventory opens (ISInventoryPage.lua:774)
check(h.inManager == false and select(5, MinidoracatTeslaAPI.hudRect(0)) == false, "joypad inventory: HUD hidden, hudRect not visible")
dash:addToUIManager() -- and closes (:759)
check(h.inManager == true and dash.visible == false, "joypad inventory closed: HUD back, vanilla still hidden")

local gas = car({ script = "Base.CarNormal" })
dash:setVehicle(gas)
check(dash.visible == true and h.inManager == false, "normal car: vanilla visible, HUD hidden")
dash:setVehicle(nil)
dash:setVehicle(nil) -- damageChecker calls this every tick on foot
check(h.inManager == false and h.vehicle == nil, "on foot: HUD stays hidden (repeated nil is harmless)")

-- split screen (4 players at 1280x720 = 640 wide) and big fonts: the strip shrinks to fit its quarter
SCREEN_W, fontH = 640, 33
dash:setVehicle(tesla)
local xq, _, wq, _, visq = MinidoracatTeslaAPI.hudRect(0)
check(visq and wq <= 632 and xq >= 0 and xq + wq <= 640, "640 px wide split view at font 4x: fits (" .. wq .. " px)")
SCREEN_W, fontH = 1920, 19
dash:setVehicle(nil)

-- ---------------------------------------------------------------- a start's phone key comes back (KeysUI.phoneBack)
H.section("phone key back from the ignition once the start ends")
do
    local keysUI, backs = T.KeysUI, 0
    T.KeysUI = { phoneBack = function() backs = backs + 1 end, checkSoon = function() end }
    local c = car({ kwh = 30 })
    dash:setVehicle(c)
    h:update()
    check(backs == 0, "getting in: nothing asked (a phone key lying in the ignition stays)")
    c.starting = true
    h:update()
    check(backs == 0, "starting: not yet (StartingSuccess would put the key back)")
    c.starting, c.running = false, true
    h:update(); h:update()
    check(backs == 1, "running: asked once")
    c.starting, c.running = true, false
    h:update()
    dash:setVehicle(tesla)
    h:update()
    check(backs == 1, "another car: the last car's start is forgotten")
    dash:setVehicle(c)
    check(backs == 1, "back in mid-start: not yet")
    c.starting = false
    h:update()
    check(backs == 2, "the start failed (back to idle): asked too")
    -- hidden over the end of the start (gamepad inventory: ISInventoryPage.lua:759,774), nobody known in the seat
    -- (this fake has no driver): asked once it is shown again, same car and seat
    c.starting = true
    h:update()
    dash:removeFromUIManager()
    check(h.inManager == false, "hidden, no driver in the seat: out of UIManager")
    c.starting, c.running = false, true
    dash:addToUIManager()
    h:update()
    check(backs == 3, "HUD hidden while the start ended: asked once when it is back")
    c.running = false
    -- hidden with its driver seated: stays in UIManager unseen and still sees the start end
    c.driver = h.character
    dash:removeFromUIManager()
    check(h.inManager == true and h.visible == false and h.vehicle == nil and select(5, MinidoracatTeslaAPI.hudRect(0)) == false,
        "hidden, its driver seated: unseen, still in UIManager, hudRect not visible")
    c.starting = true
    h:update()
    c.starting, c.running = false, true
    h:update(); h:update()
    check(backs == 4, "... a whole start while hidden: asked once")
    dash:addToUIManager()
    c.driver = h.character
    h:update()
    check(backs == 4 and h.visible == true and h.vehicle == c, "... shown again: nothing asked twice")
    c.running = false
    -- all UI hidden before getting in: vanilla adds, then removes the dashboard (ISVehicleDashboard.lua:219-228)
    c.driver = nil
    dash:setVehicle(nil)
    dash:setVehicle(c)
    c.driver = h.character
    dash:removeFromUIManager()
    c.starting = true
    h:update()
    c.starting, c.running = false, true
    h:update()
    check(backs == 5 and h.visible == false, "UI hidden before getting in: the start is still seen")
    c.driver = nil
    h:update()
    check(h.inManager == false and h.dark == nil, "... the driver left: out of UIManager")
    c.running = false
    dash:setVehicle(nil)
    T.KeysUI = keysUI
end

-- ---------------------------------------------------------------- D1: the soft landing's watch with the dashboard dark
H.section("thrusters: a fall still watched with all UI hidden")
do
    local c = car({ kwh = 30 })
    local spec = T.spec(c)
    local watch, seen = T.Thruster.watch, {}
    T.Thruster.watch = function(_, v) seen[#seen + 1] = v end
    dash:setVehicle(c)
    c.driver = h.character
    dash:removeFromUIManager()
    h:update()
    check(h.vehicle == nil and h.dark == c and #seen == 0, "dark, a car without thrusters: nothing watched")
    spec.thruster = {}
    h:update()
    check(#seen == 1 and seen[1] == c, "D1: dark, a car with thrusters: its fall still watched (Thruster.watch)")
    spec.thruster = nil
    T.Thruster.watch = watch
    c.driver = nil
    h:update()
    dash:setVehicle(nil)
end

-- ---------------------------------------------------------------- read model
H.section("read model")
dash:setVehicle(tesla)
check(h.st.gear == 1 and h.st.kmh == 0 and h.st.pct == 50, "parked: P, 0 km/h, 50%")
tesla.running, tesla.gear, tesla.throttle, tesla.speed = true, 1, 0.6, 40
h:update()
check(h.st.gear == 4 and h.st.use == 6 and h.st.kmh == 40, "driving: D, throttle 0.6 -> use 6, 40 km/h")
check(sounds[#sounds] == "VehicleInsertIgnitionKey", "ignition sound kept from vanilla prerender")
tesla.gear, tesla.throttle, tesla.speed = 0, 0, 39.5
h:update()
check(h.st.gear == 4 and h.st.regen == 5 and h.st.use == 0, "coasting in N: still D, 0.5 km/h per 0.1 s -> regen 5")
tesla.speed = 0
h:update()
h:update()
check(h.st.gear == 3, "standing with motor on in N: N")
tesla.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 1 and h.msgId == 1 and h.msgH > 0, "open door: bit set, door pill on")
local _, y2, _, h2 = MinidoracatTeslaAPI.hudRect(0)
check(h2 > hh and y2 + h2 == SCREEN_H, "pill grows the HUD upward; bottom stays at the screen bottom")
-- getting in with an alert already up: the engine can call prerender before the first update()
-- (a fresh HUD: player 1's first seat-in, no earlier build to reuse)
local dash1 = ISVehicleDashboard:new(0, 0, 552, 121)
dash1.playerNum = 1
badText = 0
dash1:setVehicle(tesla)
local h1 = HUD.get(1)
h1:prerender()
check(h1.msgTitle ~= nil and badText == 0 and h1.n > 0, "first prerender after seating: quads built, pill text has a position")
dash1:setVehicle(nil)
tesla.parts.DoorFrontLeft.door.open = false

-- ---------------------------------------------------------------- charge projection
H.section("charge projection")
local part = T.Battery.part(tesla)
local chg = { kw = 10, last = H.hours() - 0.5, added = 1, target = 60 }
local kwh, added, hours = T.Battery.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 44.2) and H.near(added, 6) and H.near(hours, (47.04 - 44.2) / 10), "kw * (now - last) added on top of the synced kWh")
chg.last = H.hours() - 5
kwh = T.Battery.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 47.04), "projection capped at the target")
chg.paused = "nopower"
kwh = T.Battery.chargeEstimate(part, chg, H.hours())
check(H.near(kwh, 39.2), "paused: no projection")
part:getModData().chg = { kw = 11.5, last = H.hours(), added = 0, target = 90 }
h:update(); h:update(); h:update()
check(h.st.chg == 1 and h.msgId == 4, "charging state and pill")
part:getModData().chg = nil

-- ---------------------------------------------------------------- redraw cost
H.section("redraw")
h:update(); h:update(); h:update()
local quads = h.n / 12
drawCalls = 0
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 1000 do h:prerender() end
local grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "prerender x1000 allocates nothing (" .. grew .. " KB)")
check(drawCalls == 1000 * quads, "prerender: one draw call per cached quad, no text without a pill (" .. quads .. " quads)")
check(quads <= 60, "quad budget <= 60 (" .. quads .. ")")
local n0 = h.n
h:update()
check(h.n == n0, "no state change: list not rebuilt into a different size")

-- ---------------------------------------------------------------- hover help (render)
H.section("hover help")
local mx, my
local function hoverAt(el) -- the E2E trick: instance methods instead of the engine mouse
    el.isMouseOver = function() return mx ~= nil end
    el.getMouseX = function() return mx end
    el.getMouseY = function() return my end
    el.getAbsoluteX = function(self) return self.x end
    el.getAbsoluteY = function(self) return self.y end
end
hoverAt(h)
drawCalls = 0
h:render()
check(drawCalls == 0, "no hover: render draws nothing")
local function tipOk(el, i)
    local ax = el.keyX + (i - 1) * el.keyStep
    mx, my = ax + el.keyS / 2, el.keyY + el.keyS / 2
    el:render()
    local r = el.tipRect
    local over = r.x < ax + el.keyS and r.x + r.w > ax and r.y < el.keyY + el.keyS and r.y + r.h > el.keyY
    return not over and el.x + r.x >= 0 and el.x + r.x + r.w <= SCREEN_W and el.y + r.y >= 0
end
local allOk = true
for i = 1, 4 do allOk = allOk and tipOk(h, i) end
check(allOk, "each of the 4 keys: tip on screen and not over the key")
local function partName(id) local k = "IGUI_VehiclePart" .. id; return T.partNameKey(tesla:getScriptName(), k) or k end
mx, my = h.keyX + 3 * h.keyStep + h.keyS + 4, h.keyY + h.keyS / 2 -- right of the camp key: no fifth key any more
drawCalls = 0
h:render()
check(h:keyAt(mx, my) == nil and drawCalls == 0 and h.keyX + 4 * h.keyStep - 6 >= 506 - 16,
    "four keys only: nothing right of the camp key, the camp key ends at the right edge")
mx, my = h.keyX - 5, h.keyY + 2
drawCalls = 0
h:render()
check(drawCalls == 0, "mouse on the HUD but not on a key: no tip")
tipOk(h, 4)
collectgarbage("collect")
collectgarbage("stop")
h:render() -- the collect above frees Lua call frames; let the deeper render->drawTip->quad chain re-grow them first
before = collectgarbage("count")
for _ = 1, 1000 do h:render() end
grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "hovered render x1000 allocates nothing (" .. grew .. " KB)")
-- 640 px split view, big font: the last key sits near the right edge; the tip is pushed back inside
SCREEN_W, fontH = 640, 33
h:layout()
check(tipOk(h, 4) and tipOk(h, 1), "640 px split view at font 4x: tips stay inside the screen")
-- a translation wider than that view: two lines, still inside
local realGetText = getText
getText = function(key) return key:find("Tip_", 1, true) and string.rep("wide words ", 9) .. "end" or key end -- 102 chars, 816 px
h:layout()
local twoOk = tipOk(h, 1)
getText = realGetText
check(twoOk and h.tipText2 ~= nil and h.tipRect.w <= 640 - 8, "tip wider than the 640 px view: broken into two lines that fit")
getText = function(key) return key:find("Tip_", 1, true) and string.rep("\233\155\187", 40) or key end -- 40 CJK chars, no spaces
h:layout()
twoOk = tipOk(h, 1)
getText = realGetText
check(twoOk and h.tipText2 ~= nil and #h.tipText % 3 == 0 and #h.tipText2 % 3 == 0, "no spaces: split on a character boundary")
SCREEN_W, fontH = 1920, 19
h:layout()
mx = nil

-- ---------------------------------------------------------------- car picture: click a door to open / close it
H.section("car picture doors")
local lid = { open = false }
function lid:isOpen() return self.open end
tesla.parts.EngineDoor = { door = lid, getDoor = function(self) return self.door end, getModData = function() return {} end,
    getInventoryItem = function() return {} end }
dash:setVehicle(tesla) -- re-attach: the frunk lid is a door now
-- a point inside each zone, design units from the car sprite's top-left (HUD.lua ZONES), and the part it toggles
local ZC = { { 22, 42, "TrunkDoor" }, { 57, 20, "DoorRearLeft" }, { 57, 64, "DoorRearRight" },
    { 83, 20, "DoorFrontLeft" }, { 83, 64, "DoorFrontRight" }, { 118, 42, "EngineDoor" } }
local toggled = {}
local realToggle = T.Liftgate.toggle
T.Liftgate.toggle = function(_, _, id) toggled[#toggled + 1] = id; return true end
local function at(ux, uy) return (172 + ux) * h.S, (14 + uy) * h.S end
local function clickAt(ux, uy)
    local x, y = at(ux, uy)
    local down = h:onMouseDown(x, y)
    return down, h:onMouseUp(x, y)
end
local function allZones()
    toggled = {}
    local ok = true
    for i, z in ipairs(ZC) do
        local down, up = clickAt(z[1], z[2])
        ok = ok and down == true and up == true and toggled[i] == z[3]
    end
    return ok and #toggled == #ZC
end
check(allZones(), "S=1: each of the 6 zones (liftgate, 4 doors, frunk lid) toggles its own part")
toggled = {}
check(h:onMouseDown(4, 4) == false and h:onMouseUp(4, 4) == false and select(1, clickAt(142, 30)) == false
    and #toggled == 0, "off the car picture and the keys: the click passes through")
check(h.keyX == (172 + 140) * h.S, "the quick keys start where the car picture's zones end (x 312)")
fontH = 38
h:layout()
check(h.S == 2 and allZones(), "S=2: the zones scale with S")
fontH = 19
h:layout()
-- hover: zone tinted + door drawn in accent, tip "Open / Close <name>" above the zone
mx, my = at(83, 20)
drawCalls = 0
h:render()
local r = h.tipRect
check(drawCalls > 2 and lastText == "IGUI_MinidoracatTesla_Tip_DoorOpen" and h.tipArg == partName("DoorFrontLeft")
    and r.y + r.h <= 14 * h.S, "hover front-left door: highlight, tip 'open' + its name above the picture")
tesla.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
h:render()
check(lastText == "IGUI_MinidoracatTesla_Tip_DoorClose", "front-left door open: tip says close")
mx, my = at(118, 42)
h:render()
check(lastText == "IGUI_MinidoracatTesla_Tip_DoorOpen" and h.tipArg == partName("EngineDoor"), "hover frunk lid: open + its name")
collectgarbage("collect")
collectgarbage("stop")
h:render()
before = collectgarbage("count")
for _ = 1, 1000 do h:render() end
grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "hovered door render x1000 allocates nothing (" .. grew .. " KB)")
-- a removed door: its zone darkened, no highlight or tip, the click passes through
tesla.parts.DoorFrontLeft.door.open = false
h:update(); h:update(); h:update()
local n1 = h.n
tesla.parts.DoorRearRight.getInventoryItem = function() return nil end
h:update(); h:update(); h:update()
check(h.n == n1 + 12, "rear right door removed: one dimming quad over its zone")
toggled = {}
mx, my = at(57, 64)
drawCalls = 0
h:render()
check(select(1, clickAt(57, 64)) == false and #toggled == 0 and drawCalls == 0, "removed door: not clickable, no highlight")
tesla.parts.DoorRearRight.getInventoryItem = function() return {} end
h:update(); h:update(); h:update()
-- each car its own top view and zones (HUD.ZONES[Specs model]): the Model Y's liftgate carries the rear glass, the
-- Model 3's trunk lid ends at its seam (x 35) and its rear doors start at their outline (x 49), so the rear glass
-- between opens nothing; the tail is named per car
toggled = {}
mx, my = at(22, 42)
h:render()
check(h.carSpr == "car_ModelY" and h.zones == HUD.ZONES.ModelY and h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkDoor"
    and select(1, clickAt(41, 42)) == true and toggled[1] == "TrunkDoor",
    "Model Y: car_ModelY and its zones; x 41 (the liftgate's glass) opens the liftgate, named liftgate")
local m3 = car({ script = "Base.MinidoracatTesla_Model3", kwh = 39.2 })
m3.parts.EngineDoor = tesla.parts.EngineDoor
dash:setVehicle(m3)
check(h.carSpr == "car_Model3" and h.zones == HUD.ZONES.Model3 and T.HUDAtlas[1].car_Model3 ~= nil
    and T.HUDAtlas[2].car_Model3 ~= nil and allZones(), "Model 3: car_Model3 (both scales), its zones, all 6 toggle their part")
toggled = {}
check(select(1, clickAt(41, 42)) == false and select(1, clickAt(47, 20)) == false and select(1, clickAt(47, 64)) == false
    and #toggled == 0, "Model 3: x 41 and 47 are the rear glass, neither the trunk lid nor a rear door: passes through")
mx, my = at(22, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkLid", "Model 3: hovering the tail names the trunk lid")
-- the open-door message names this car's lid, also when the last car had the same door bits open (message cache)
local realGT = getText
getText = function(k, a) return a and (k .. "|" .. a) or k end
tesla.parts.TrunkDoor.door.open, m3.parts.TrunkDoor.door.open = true, true
dash:setVehicle(tesla)
local yTitle = h.msgTitle
dash:setVehicle(m3)
local m3Title = h.msgTitle
getText = realGT
tesla.parts.TrunkDoor.door.open, m3.parts.TrunkDoor.door.open = false, false
check(yTitle == "IGUI_MinidoracatTesla_HUD_DoorOpen|IGUI_MinidoracatTesla_Part_TrunkDoor"
    and m3Title == "IGUI_MinidoracatTesla_HUD_DoorOpen|IGUI_MinidoracatTesla_Part_TrunkLid",
    "open-door message: Model Y 'liftgate open', then the Model 3 with the same bits 'trunk lid open' (" .. tostring(m3Title) .. ")")
-- Cybertruck: its own top view, door overlays (door_<kind>_Cybertruck) and zones: tailgate x 0-14, tonneau over the
-- bed x 14-51, the rear glass x 51-55 opens nothing; the tonneau has its own zone and message name
local ct = car({ script = "Base.MinidoracatTesla_Cybertruck", kwh = 61.5 })
ct.parts.EngineDoor = tesla.parts.EngineDoor
local tn = { open = false }
function tn:isOpen() return self.open end
ct.parts.TrunkTonneau = { door = tn, getDoor = function(self) return self.door end, getModData = function() return {} end,
    getInventoryItem = function() return {} end }
dash:setVehicle(ct)
local own = true
for _, d in ipairs(h.doors) do own = own and d.spr:find("_Cybertruck", 1, true) ~= nil and T.HUDAtlas[2][d.spr] ~= nil end
check(h.carSpr == "car_Cybertruck" and h.zones == HUD.ZONES.Cybertruck and #h.doors == 7 and own,
    "Cybertruck: car_Cybertruck, its zones, 7 doors each with its own overlay sprite at both scales")
toggled = {}
local hits = { { 7, 42, "TrunkDoor" }, { 30, 42, "TrunkTonneau" }, { 60, 20, "DoorRearLeft" }, { 60, 64, "DoorRearRight" },
    { 90, 20, "DoorFrontLeft" }, { 90, 64, "DoorFrontRight" }, { 120, 42, "EngineDoor" } }
local allOk = true
for i, z in ipairs(hits) do allOk = allOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(allOk and #toggled == 7, "Cybertruck: tailgate, tonneau, 4 doors and the frunk lid each toggle their part")
toggled = {}
check(select(1, clickAt(53, 42)) == false and #toggled == 0, "Cybertruck: x 53 is the rear glass: passes through")
mx, my = at(30, 42)
h:render()
check(h.tipArg == "IGUI_VehiclePartTrunkTonneau", "hovering the bed names the tonneau cover")
mx, my = at(7, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_Tailgate", "hovering the tail names the tailgate")
tn.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 128, "tonneau open: door bit 128 (DOORS[8])")
tn.open = false
-- Model S: its own top view and overlays; the liftgate (rear glass with it) x 0-42, rear doors 42-67, front doors 67-93,
-- the frunk lid 93-140; past x 140 (the quick keys) is not the car; the tail is the liftgate (Model Y's name)
local ms = car({ script = "Base.MinidoracatTesla_ModelS", kwh = 50 })
ms.parts.EngineDoor = tesla.parts.EngineDoor
dash:setVehicle(ms)
own = true
for _, d in ipairs(h.doors) do own = own and d.spr:find("_ModelS", 1, true) ~= nil and T.HUDAtlas[1][d.spr] ~= nil end
check(h.carSpr == "car_ModelS" and h.zones == HUD.ZONES.ModelS and T.HUDAtlas[2].car_ModelS ~= nil and #h.doors == 6
    and own and allZones(), "Model S: car_ModelS, its zones, 6 doors with their own overlays, all 6 toggle their part")
toggled = {}
hits = { { 38, 42, "TrunkDoor" }, { 50, 20, "DoorRearLeft" }, { 50, 64, "DoorRearRight" }, { 80, 20, "DoorFrontLeft" },
    { 80, 64, "DoorFrontRight" }, { 110, 42, "EngineDoor" } }
allOk = true
for i, z in ipairs(hits) do allOk = allOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(allOk and #toggled == 6, "Model S: x 38 (the liftgate's glass) opens the liftgate, each door and the frunk its own")
toggled = {}
check(select(1, clickAt(145, 42)) == false and #toggled == 0, "Model S: x 145 is past the car (quick keys): passes through")
mx, my = at(20, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkDoor", "Model S: hovering the tail names the liftgate")
-- Model X: its own top view and overlays (door_<kind>_ModelX; an open falcon wing is drawn raised, door_RL/RR_ModelX)
-- and zones: the liftgate x 0-44, the falcon wings (DoorRearLeft / DoorRearRight) x 44-75 split at the roof's spine,
-- the front doors x 75-106, the frunk lid x 106-140; hovering a wing names the falcon wing door
do
local mxc = car({ script = "Base.MinidoracatTesla_ModelX", kwh = 80 })
mxc.parts.EngineDoor = tesla.parts.EngineDoor
dash:setVehicle(mxc)
local mine, sprs = true, {}
for _, d in ipairs(h.doors) do
    mine = mine and d.spr:find("_ModelX", 1, true) ~= nil and T.HUDAtlas[1][d.spr] ~= nil and T.HUDAtlas[2][d.spr] ~= nil
    sprs[d.name] = d.spr
end
check(h.carSpr == "car_ModelX" and h.zones == HUD.ZONES.ModelX and T.HUDAtlas[1].car_ModelX ~= nil
    and T.HUDAtlas[2].car_ModelX ~= nil and #h.doors == 6 and mine and sprs.DoorRearLeft == "door_RL_ModelX"
    and sprs.DoorRearRight == "door_RR_ModelX", "Model X: car_ModelX, its zones, 6 doors each with its own overlay at both scales")
toggled = {}
local xh = { { 20, 42, "TrunkDoor" }, { 60, 20, "DoorRearLeft" }, { 60, 64, "DoorRearRight" },
    { 90, 20, "DoorFrontLeft" }, { 90, 64, "DoorFrontRight" }, { 120, 42, "EngineDoor" } }
local xOk = true
for i, z in ipairs(xh) do xOk = xOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(xOk and #toggled == 6, "Model X: liftgate, both falcon wings, both front doors and the frunk lid each toggle their part")
toggled = {}
check(select(1, clickAt(43, 20)) == true and toggled[1] == "TrunkDoor" and select(1, clickAt(45, 20)) == true
    and toggled[2] == "DoorRearLeft" and select(1, clickAt(74, 64)) == true and toggled[3] == "DoorRearRight"
    and select(1, clickAt(76, 64)) == true and toggled[4] == "DoorFrontRight", "Model X: the seams at x 44 and 75 split the zones")
mx, my = at(60, 20)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_FalconWingLeft", "Model X: hovering the left wing names the falcon wing door")
mx, my = at(60, 64)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_FalconWingRight", "...and the right one")
mxc.parts.DoorRearLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 4, "Model X: left falcon wing open -> door bit 4 (drawn with door_RL_ModelX)")
mxc.parts.DoorRearLeft.door.open = false
-- Model Y L: its own top view (the longer tail), the Model Y's front doors and frunk overlays (door_FL / FR / HD), its
-- own rear doors and liftgate (door_RL / RR / TR_ModelYL); the liftgate x 0-41, rear doors 41-69, the rest the Model Y's
local ylc = car({ script = "Base.MinidoracatTesla_ModelYL", kwh = 60 })
ylc.parts.EngineDoor = tesla.parts.EngineDoor
dash:setVehicle(ylc)
local ylSpr = {}
for _, d in ipairs(h.doors) do ylSpr[d.name] = T.HUDAtlas[1][d.spr] and T.HUDAtlas[2][d.spr] and d.spr end
check(h.carSpr == "car_ModelYL" and h.zones == HUD.ZONES.ModelYL and T.HUDAtlas[1].car_ModelYL ~= nil
    and T.HUDAtlas[2].car_ModelYL ~= nil and #h.doors == 6 and ylSpr.DoorRearLeft == "door_RL_ModelYL"
    and ylSpr.DoorRearRight == "door_RR_ModelYL" and ylSpr.TrunkDoor == "door_TR_ModelYL" and ylSpr.DoorFrontLeft == "door_FL"
    and ylSpr.DoorFrontRight == "door_FR" and ylSpr.EngineDoor == "door_HD",
    "Model Y L: car_ModelYL, its zones, its own rear door and liftgate overlays, the Model Y's front ones, at both scales")
toggled = {}
local ylh = { { 20, 42, "TrunkDoor" }, { 55, 20, "DoorRearLeft" }, { 55, 64, "DoorRearRight" },
    { 80, 20, "DoorFrontLeft" }, { 80, 64, "DoorFrontRight" }, { 120, 42, "EngineDoor" } }
local ylOk = true
for i, z in ipairs(ylh) do ylOk = ylOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(ylOk and #toggled == 6, "Model Y L: liftgate, 4 doors and the frunk lid each toggle their part")
toggled = {}
check(select(1, clickAt(40, 20)) == true and toggled[1] == "TrunkDoor" and select(1, clickAt(42, 20)) == true
    and toggled[2] == "DoorRearLeft", "Model Y L: the liftgate glass's front edge at x 41 splits liftgate and rear door")
mx, my = at(55, 20)
h:render()
check(h.tipArg == "IGUI_VehiclePartDoorRearLeft", "Model Y L: hovering a rear door names an ordinary rear door")
mx, my = at(20, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkDoor", "Model Y L: hovering the tail names the liftgate")
ylc.parts.DoorRearLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 4, "Model Y L: left rear door open -> door bit 4 (drawn with door_RL_ModelYL)")
ylc.parts.DoorRearLeft.door.open = false
-- Roadster: its own top view, two doors, the trunk lid, the soft top (DOORS[9], door_ST_Roadster) between the doors
-- over the seats; the rear deck x 53-67 opens nothing. An open soft top is drawn but asks nobody to close it
local rdc = car({ script = "Base.MinidoracatTesla_Roadster", kwh = 28 })
rdc.parts.DoorRearLeft, rdc.parts.DoorRearRight = nil, nil
rdc.parts.EngineDoor = tesla.parts.EngineDoor
local st = { open = false }
function st:isOpen() return self.open end
rdc.parts.SoftTop = { door = st, getDoor = function(self) return self.door end, getModData = function() return {} end,
    getInventoryItem = function() return {} end }
dash:setVehicle(rdc)
local rdSpr = {}
for _, d in ipairs(h.doors) do rdSpr[d.name] = T.HUDAtlas[1][d.spr] and T.HUDAtlas[2][d.spr] and d.spr end
check(h.carSpr == "car_Roadster" and h.zones == HUD.ZONES.Roadster and T.HUDAtlas[1].car_Roadster ~= nil
    and T.HUDAtlas[2].car_Roadster ~= nil and #h.doors == 5 and rdSpr.SoftTop == "door_ST_Roadster"
    and rdSpr.DoorFrontLeft == "door_FL_Roadster" and rdSpr.TrunkDoor == "door_TR_Roadster" and rdSpr.EngineDoor == "door_HD",
    "Roadster: car_Roadster, its zones, two doors, trunk lid and soft top with their own overlays, the Model Y's hood")
toggled = {}
local rdh = { { 20, 42, "TrunkDoor" }, { 80, 15, "DoorFrontLeft" }, { 80, 42, "SoftTop" }, { 80, 70, "DoorFrontRight" },
    { 120, 42, "EngineDoor" } }
local rdOk = true
for i, z in ipairs(rdh) do rdOk = rdOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(rdOk and #toggled == 5, "Roadster: trunk lid, both doors, the soft top and the hood each toggle their part")
toggled = {}
check(select(1, clickAt(60, 42)) == false and #toggled == 0, "Roadster: x 60 is the rear deck: passes through")
mx, my = at(80, 42)
h:render()
check(h.tipArg == "IGUI_VehiclePartSoftTop", "Roadster: hovering the roof names the soft top")
mx, my = at(20, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkLid", "Roadster: hovering the tail names the trunk lid (owner's manual: Trunk)")
st.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 256 and h.msgId == 0, "soft top open: door bit 256 (DOORS[9]) drawn, no 'close before driving' message")
rdc.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 257 and h.msgId == 1 and h.msgA1 == 1, "soft top and a door open: the message counts only the door")
st.open, rdc.parts.DoorFrontLeft.door.open = false, false
h:update(); h:update(); h:update()
-- the shared rule behind the click and the server's liftgate command (Liftgate.check): driver only, stopped only
local rdDrv, rdPas = H.player({ name = "rdDrv" }), H.player({ name = "rdPas" })
rdc.driver = rdDrv
local _, why1 = T.Liftgate.check(rdPas, rdc, "SoftTop")
rdc.speed = 20
local _, why2 = T.Liftgate.check(rdDrv, rdc, "SoftTop")
rdc.speed = 0
local teslaDrv = tesla.driver
tesla.driver = rdDrv
check(why1 == "NOT_DRIVER" and why2 == "MOVING" and T.Liftgate.check(rdDrv, rdc, "SoftTop") == rdc.parts.SoftTop
    and select(2, T.Liftgate.check(rdDrv, tesla, "SoftTop")) == "NO_DOOR",
    "soft top: a passenger -> NOT_DRIVER, moving -> MOVING, the stopped driver -> the part; a car without one -> NO_DOOR")
rdc.driver, tesla.driver = nil, teslaDrv
mx = nil
do -- Cybercab: its own top view, two doors and the trunk lid; no front trunk, so its hood (the part is there, vanilla's
-- mechanics open it) is no lid here: no zone, no overlay, no "close before driving" message
local ccc = car({ script = "Base.MinidoracatTesla_Cybercab", kwh = 28 })
ccc.parts.DoorRearLeft, ccc.parts.DoorRearRight = nil, nil
ccc.parts.EngineDoor = tesla.parts.EngineDoor
dash:setVehicle(ccc)
local ccSpr = {}
for _, d in ipairs(h.doors) do ccSpr[d.name] = T.HUDAtlas[1][d.spr] and T.HUDAtlas[2][d.spr] and d.spr end
check(h.carSpr == "car_Cybercab" and h.zones == HUD.ZONES.Cybercab and T.HUDAtlas[1].car_Cybercab ~= nil
    and T.HUDAtlas[2].car_Cybercab ~= nil and #h.doors == 3 and ccSpr.EngineDoor == nil
    and ccSpr.DoorFrontLeft == "door_FL_Cybercab" and ccSpr.DoorFrontRight == "door_FR_Cybercab"
    and ccSpr.TrunkDoor == "door_TR_Cybercab" and T.HUDAtlas[2].door_HD_Cybercab == nil,
    "Cybercab: car_Cybercab, its zones, two butterfly doors and the trunk lid with their own overlays, no hood")
toggled = {}
local cch = { { 20, 42, "TrunkDoor" }, { 85, 20, "DoorFrontLeft" }, { 85, 64, "DoorFrontRight" } }
local ccOk = true
for i, z in ipairs(cch) do ccOk = ccOk and select(1, clickAt(z[1], z[2])) == true and toggled[i] == z[3] end
check(ccOk and #toggled == 3, "Cybercab: trunk lid and both doors each toggle their part")
toggled = {}
check(select(1, clickAt(120, 42)) == false and select(1, clickAt(66, 42)) == false and #toggled == 0,
    "Cybercab: the hood (x 120) and the rear quarter (x 66) pass through")
mx, my = at(20, 42)
h:render()
check(h.tipArg == "IGUI_MinidoracatTesla_Part_TrunkLid", "Cybercab: hovering the tail names the trunk lid (rider guide: Trunk)")
ccc.parts.EngineDoor.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 0 and h.msgId == 0, "Cybercab: the hood opened by hand (vanilla mechanics): not drawn, no message")
ccc.parts.EngineDoor.door.open = false
ccc.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
check(h.st.doors == 1 and h.msgId == 1, "Cybercab: a door open: bit 1, 'close before driving'")
ccc.parts.DoorFrontLeft.door.open = false
h:update(); h:update(); h:update()
mx = nil
end
do -- Semi: its own top view and two cab doors hinged at their rear edge; the trailer drawn over it while one is hitched
-- (read with the doors in readSlow, every third 10 Hz update: no poll of its own); the charge bolt over its port, on
-- the left side behind the cab (the cars' at their tail)
local smc = car({ script = "Base.MinidoracatTesla_Semi", kwh = 822 })
smc.parts.DoorRearLeft, smc.parts.DoorRearRight, smc.parts.TrunkDoor = nil, nil, nil
local asks = 0
function smc:getVehicleTowing() asks = asks + 1; return self.towing end
function smc:getMass() return 9000 end
dash:setVehicle(smc)
local smSpr = {}
for _, d in ipairs(h.doors) do smSpr[d.name] = T.HUDAtlas[1][d.spr] and T.HUDAtlas[2][d.spr] and d.spr end
check(h.carSpr == "car_Semi" and h.zones == HUD.ZONES.Semi and T.HUDAtlas[1].car_Semi ~= nil
    and T.HUDAtlas[2].car_Semi ~= nil and #h.doors == 2 and smSpr.DoorFrontLeft == "door_FL_Semi"
    and smSpr.DoorFrontRight == "door_FR_Semi" and h.towSpr == "tow_Semi" and T.HUDAtlas[2].tow_Semi ~= nil,
    "Semi: car_Semi, its zones, two doors with their own overlays, the trailer's sprite, at both scales")
toggled = {}
local smOk = select(1, clickAt(92, 20)) == true and select(1, clickAt(112, 64)) == true
check(smOk and toggled[1] == "DoorFrontLeft" and toggled[2] == "DoorFrontRight" and #toggled == 2,
    "Semi: both cab doors toggle their part")
toggled = {}
check(select(1, clickAt(128, 42)) == false and select(1, clickAt(84, 20)) == false and select(1, clickAt(40, 42)) == false
    and #toggled == 0, "Semi: the windscreen (x 128), the cab's side behind the doors (x 84) and the drive axles (x 40) pass through")
-- index of the sprite's quad in the list (the first at x, y when given), or nil
local function drawn(name, x, y)
    local e, L = h.A[name], h.L
    for i = 1, h.n, 12 do
        if L[i] == e[1] and L[i + 1] == e[2] and L[i + 2] == e[3] and L[i + 3] == e[4]
            and (not x or L[i + 4] == math.floor(x + 0.5) and L[i + 5] == math.floor(y + 0.5)) then return i end
    end
end
local builds, realBuild = 0, h.build
h.build = function(self) builds = builds + 1; return realBuild(self) end
h:update(); h:update(); h:update()
asks, builds = 0, 0
for _ = 1, 9 do h:update() end
check(h.st.tow == false and drawn("tow_Semi") == nil and asks == 6 and builds == 0,
    "no trailer: none drawn; asked only in readSlow (3 of 9 updates, its range's tow factor and the trailer), nothing rebuilt")
smc.towing = { getScriptName = function() return "Base.Trailer" end, getMass = function() return 600 end }
h:update(); h:update(); h:update()
check(h.st.tow == false and drawn("tow_Semi") == nil, "a vanilla trailer: not drawn")
smc.towing = { getScriptName = function() return "Base.MinidoracatTesla_SemiTrailer" end, getMass = function() return 6000 end }
builds = 0
h:update(); h:update(); h:update()
local ti, ci = drawn("tow_Semi"), drawn("car_Semi")
check(h.st.tow == true and builds == 1 and ti == ci + 12 and drawn("tow_Semi", 172 * h.S + h.A.tow_Semi[5] * h.f,
    14 * h.S + h.A.tow_Semi[6] * h.f) == ti,
    "the Semi trailer hitched: one rebuild, its quad on the car picture right after the car's (under the doors)")
smc.parts.DoorFrontLeft.door.open = true
h:update(); h:update(); h:update()
check(drawn(smSpr.DoorFrontLeft) > ti, "an open door drawn over the trailer")
smc.parts.DoorFrontLeft.door.open = false
smc.towing = nil
h:update(); h:update(); h:update()
check(h.st.tow == false and drawn("tow_Semi") == nil, "unhitched: the trailer gone")
local smPart = T.Battery.part(smc)
smPart:getModData().chg = { kw = 0, last = H.hours(), added = 0, target = 100, paused = "full" }
h:update(); h:update(); h:update()
check(drawn("i_bolt", (172 + 50) * h.S, (14 + 1) * h.S) ~= nil,
    "Semi charged: the bolt over its port behind the cab (x 50, y 1 on the picture)")
smPart:getModData().chg = nil
h.build = nil
dash:setVehicle(tesla)
part:getModData().chg = { kw = 0, last = H.hours(), added = 0, target = 100, paused = "full" }
h:update(); h:update(); h:update()
check(h.towSpr == nil and h.st.tow == false and drawn("i_bolt", (172 + 2) * h.S, (14 - 4) * h.S) ~= nil,
    "a car: no trailer sprite, the trailer never read (its fake has no getVehicleTowing); its bolt at the tail")
part:getModData().chg = nil
h:update(); h:update(); h:update()
mx = nil
end
-- every car's zones: inside the picture before the quick keys (x <= 140, 0 <= y <= 85), none overlapping
local zOk = true
for model, zs in pairs(HUD.ZONES) do
    for i, a in ipairs(zs) do
        zOk = zOk and a[2] >= 0 and a[3] >= 0 and a[4] <= 140 and a[5] <= 85 and a[2] < a[4] and a[3] < a[5]
        for j = i + 1, #zs do
            local b = zs[j]
            if a[2] < b[4] and b[2] < a[4] and a[3] < b[5] and b[3] < a[5] then zOk = false; print("overlap " .. model) end
        end
    end
end
check(zOk, "every car's zones inside x 0-140, y 0-85, none overlapping")
end
dash:setVehicle(tesla)
T.Liftgate.toggle = realToggle
mx = nil

-- ---------------------------------------------------------------- power key (user 2026-10-27)
H.section("power key")
local started, shut, halo = 0, 0, nil
ISVehicleMenu.onStartEngine = function() started = started + 1 end
ISVehicleMenu.onShutOff = function() shut = shut + 1 end
local realBad = HaloTextHelper.addBadText
HaloTextHelper.addBadText = function(_, t) halo = t end
local drv = H.player({ name = "drv" })
drv.playSound = function() end
tesla.driver, tesla.running, tesla.speed = drv, false, 0
dash:setVehicle(tesla)
h.character = drv
local px, py = h.pwrX + h.pwrS / 2, h.pwrY + h.pwrS / 2
check(h.pwrX == 136 and h.pwrS == 28 and h.pwrY + h.pwrS < 36 and h.pwrX + h.pwrS + 8 <= 172 and h.pwrX > 110,
    "power key: after the gear row, left of the car picture, above the speed digits")
check(select(3, MinidoracatTeslaAPI.hudRect(0)) == 506, "power key fits: the strip stays 506 wide (AutoDrive FSD card)")
check(h:onMouseDown(px, py) == true and h:onMouseUp(px, py) == true and started == 1 and shut == 0,
    "motor off: click starts the car the vanilla way (ISVehicleMenu.onStartEngine)")
tesla.running, tesla.speed = true, 30
h:update()
h:onMouseUp(px, py)
check(shut == 0 and halo == "IGUI_MinidoracatTesla_Deny_MOVING", "driving at 30 km/h: no power off, red 'stop the car first'")
tesla.speed = -1
h:update()
h:onMouseUp(px, py)
check(shut == 1, "stopped (1 km/h): click powers off (ISVehicleMenu.onShutOff)")
h.character = H.player({ name = "pax" })
h:onMouseUp(px, py)
check(shut == 1 and started == 1, "not the driver: the power key does nothing")
h.character = drv
check(h:onMouseDown(h.pwrX - 3, py) == false and h:onMouseDown(px, h.pwrY + h.pwrS + 3) == false,
    "just outside the power key: the click passes through")
mx, my = px, py
h:render()
local pr = h.tipRect
check(lastText == "IGUI_MinidoracatTesla_Tip_PowerOff" and (pr.y + pr.h <= h.pwrY or pr.y >= h.pwrY + h.pwrS),
    "hover, motor on: 'power off' help, not covering the key")
tesla.running = false
h:update()
h:render()
check(lastText == "IGUI_MinidoracatTesla_Tip_PowerOn", "hover, motor off: 'start' help")
local nOff = h.n
tesla.running = true
h:update()
check(h.n == nOff + 12, "motor on: the power key gets its blue underline (one more quad)")
-- the thrusters' air (Thruster.lua H.air): hovering the cell's area (its %, the cell, the air bar) says how much and
-- when it is full again; full: no "full in"; a car without thrusters: no such tip
local realAir, realWatch = T.Thruster.air, T.Thruster.watch
T.Thruster.air, T.Thruster.watch = function() return 0.65 end, function() end
h:update(); h:update(); h:update()
mx, my = h.airX + 1, h.airY + 2
h:render()
local airLow = lastText
mx = h.airX + h.airW - 1
h:render()
check(airLow == "IGUI_MinidoracatTesla_Tip_ThrustTankRefill" and lastText == airLow and h.airPct == 65,
    "hover the cell area, air 65 %: the air tip with when it is full again (its % and the cell both)")
collectgarbage("collect")
collectgarbage("stop")
h:render()
before = collectgarbage("count")
for _ = 1, 1000 do h:render() end
grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "hovered air tip render x1000 allocates nothing (" .. grew .. " KB)")
T.Thruster.air = function() return 1 end
h:update(); h:update(); h:update()
h:render()
check(lastText == "IGUI_MinidoracatTesla_Tip_ThrustTank", "air full: the tip without a refill time")
-- T7: the pack can't pay the refill (Thruster.lua H.refillShort): no "full in N min", "charge the battery" in its
-- place; the tip made again when that alone changes (the same %)
do
    local realShort, gt0 = T.Thruster.refillShort, getText
    local short = true
    T.Thruster.refillShort = function(car) return car == h.vehicle and short end
    getText = function(k, ...) return table.concat({ k, ... }, "|") end
    T.Thruster.air = function() return 0.65 end
    h:update(); h:update(); h:update()
    mx, my = h.airX + 1, h.airY + 2
    h:render()
    local low = "IGUI_MinidoracatTesla_Tip_ThrustTankRefill|65|IGUI_MinidoracatTesla_Thrust_RefillLow"
    check(lastText == low, "T7: air 65 %, the pack at its floor: the tip says charge the battery, no minutes (" .. tostring(lastText) .. ")")
    short = false
    h:update(); h:update(); h:update()
    h:render()
    check(lastText == "IGUI_MinidoracatTesla_Tip_ThrustTankRefill|65|IGUI_MinidoracatTesla_Thrust_Refill|"
        .. T.Thruster.minutesToFull(0.65), "T7: the pack can pay again, the same %: the minutes back (" .. tostring(lastText) .. ")")
    short = true
    h:update(); h:update(); h:update()
    T.Thruster.air = function() return 1 end
    h:update(); h:update(); h:update()
    h:render()
    check(lastText == "IGUI_MinidoracatTesla_Tip_ThrustTank|100", "T7: a full tank: no refill line, short or not")
    -- Codex residual: the air tip's text is its own cache key (drawTip key nil); a new scale (a resolution or font
    -- change) with the same text must measure it again
    T.Thruster.air = function() return 0.65 end
    h:update(); h:update(); h:update()
    h:render()
    check(lastText == low and h.tipText2 == nil, "residual: 1920 px wide, the air tip on one line")
    SCREEN_W = 640
    h:layout()
    mx, my = h.airX + 1, h.airY + 2
    h:render()
    check(h.tipText2 ~= nil and h.tipRect.x + h.tipRect.w <= 640,
        "residual: 640 px wide after a new scale, the same text: measured again, two lines inside the view")
    SCREEN_W = 1920
    h:layout()
    mx, my = h.airX + 1, h.airY + 2
    h:render()
    check(h.tipText2 == nil, "residual: back to 1920 px: one line again")
    T.Thruster.refillShort, getText = realShort, gt0
    T.Thruster.air = function() return 1 end
    h:update(); h:update(); h:update()
end
-- flying (Thruster.lua H.flight): this driver's pill comes first, its seconds counting down, the last 3 a warning;
-- FreeFlight: no seconds; coming down: "Landing", no keys; a controller's driver: its keys; not flying: no pill
local realFlight, realGT, realTip = T.Thruster.flight, getText, T.Thruster.flyTip
local fl
T.Thruster.flight = function(p, car) if p == h.character and car == h.vehicle then return fl end end
getText = function(k, a) return a and (k .. "|" .. a) or k end
-- the keys line is Thruster.lua H.flyTip's (test_thruster.lua: the keys bound now, the controller's words)
T.Thruster.flyTip = function(p, key) return key .. (p:getJoypadBind() ~= -1 and "Pad" or "") end
h.character.getJoypadBind = function() return -1 end
local function slow() h:update(); h:update(); h:update() end
slow()
local id0, title0 = h.msgId, h.msgTitle
fl = 8
slow()
check(h.msgId == 8 and h.msgTitle == "IGUI_MinidoracatTesla_HUD_Flying|8" and h.msgIcon == "i_wing"
    and h.msgColor == HUD.C.accent and h.msgSub == "IGUI_MinidoracatTesla_HUD_FlyKeys",
    "flying: 'Flying, 8 s left', the car icon in accent, the keys below (" .. tostring(h.msgSub) .. ")")
fl = 7
slow()
check(h.msgTitle == "IGUI_MinidoracatTesla_HUD_Flying|7" and h.msgIcon == "i_wing", "a second later: 7 s left")
fl = 3
slow()
check(h.msgTitle == "IGUI_MinidoracatTesla_HUD_Flying|3" and h.msgIcon == "i_warn" and h.msgColor == HUD.C.warn,
    "3 s left: the warning icon and colour (the pill's own warning level)")
fl = true
slow()
check(h.msgId == 8 and h.msgTitle == "IGUI_MinidoracatTesla_HUD_FlyingFree" and h.msgIcon == "i_wing",
    "FreeFlight: 'Flying', no seconds, no warning")
h.character.getJoypadBind = function() return 1 end
slow()
check(h.msgSub == "IGUI_MinidoracatTesla_HUD_FlyKeysPad", "a controller's driver: the controller's keys")
collectgarbage("collect")
collectgarbage("stop")
before = collectgarbage("count")
for _ = 1, 1000 do h:prerender() end
grew = collectgarbage("count") - before
collectgarbage("restart")
check(grew == 0, "flying pill prerender x1000 allocates nothing (" .. grew .. " KB)")
fl = "land"
slow()
check(h.msgId == 9 and h.msgTitle == "IGUI_MinidoracatTesla_HUD_FlyLanding" and h.msgSub == nil
    and h.msgIcon == "i_chevdown", "coming down: 'Landing', no keys line")
tesla.parts.DoorFrontLeft.door.open = true -- a door open too: flying first, the door's pill once it is down
slow()
local flyFirst = h.msgId
fl = nil
slow()
check(flyFirst == 9 and h.msgId == 1, "a door open while landing: the landing's pill first, the door's after")
tesla.parts.DoorFrontLeft.door.open = false
slow()
check(h.msgId == id0 and h.msgTitle == title0, "landed, door shut: the pill as before the flight (" .. tostring(h.msgTitle) .. ")")
local realAir2 = T.Thruster.air
T.Thruster.air = function() return nil end -- a car without thrusters: H.flight never asked
local asked = false
T.Thruster.flight = function() asked = true end
slow()
check(not asked, "no thrusters: the flight is never asked for")
T.Thruster.air = realAir2
T.Thruster.flight, getText, T.Thruster.flyTip, h.character.getJoypadBind = realFlight, realGT, realTip, nil
T.Thruster.air = realAir
h:update(); h:update(); h:update()
T.Thruster.watch = realWatch -- (after: the dashboard asks it while it still shows the air)
drawCalls = 0
h:render()
check(h.airX == nil and drawCalls == 0, "no thrusters: no air tip")
-- the Roadster Rocket's wing (DOORS' 10th) is raised and lowered, not opened
local doors0 = h.st.doors
h.st.doors = 0
h:doorTip(10, 0, 100, 10, 10)
local wingUp = lastText
h.st.doors = 512
h:doorTip(10, 0, 100, 10, 10)
check(wingUp == "IGUI_MinidoracatTesla_Tip_WingUp" and lastText == "IGUI_MinidoracatTesla_Tip_WingDown" and h.tipArg == nil,
    "the wing's tip: raise it / lower it (no part name)")
h.st.doors = doors0
mx = nil
-- plugged in: Park, whatever the transmission says (owner's manual, Shifting)
tesla.speed, tesla.gear = 0, 0
T.Battery.part(tesla):getModData().chg = { kw = 11.5, last = H.hours(), added = 0, target = 90 }
h:update(); h:update(); h:update(); h:update()
check(h.st.gear == 1 and h.st.on == true, "plugged in with the motor on: gear shows P")
-- the pedal hint (ChargerMenu.lua T.onPluggedDrive, run from CheckOperate while plugged in)
for _, m in ipairs({ "Map/CGlobalObjectSystem", "Map/CGlobalObject", "TimedActions/ISBaseTimedAction" }) do H.stub(m) end
local function derive(base, name) local c = setmetatable({ Type = name }, { __index = base }); c.__index = c; return c end
CGlobalObject = CGlobalObject or { derive = derive }
CGlobalObjectSystem = CGlobalObjectSystem or { derive = derive, RegisterSystemClass = function() end }
ISBaseTimedAction = ISBaseTimedAction or { derive = derive }
require "MinidoracatTesla/ChargerMenu"
local keys = {}
KeybindId = { FORWARD = "fwd", BACKWARD = "back" }
function isKeyDown(k) return keys[k] == true end
function isJoypadRTPressed() return false end
function isJoypadLTPressed() return false end
drv.isLocalPlayer = function() return true end
drv.getJoypadBind = function() return -1 end
drv.getPlayerNum = function() return 0 end
tesla.isRegulator = function() return false end
local brakes, C = 0, T.Charge
tesla.setForceBrake = function() brakes = brakes + 1 end
local part = T.Battery.part(tesla)
halo = nil
check(T.CheckOperate.Battery(tesla, part) == true and halo == nil and brakes == 0, "plugged in, no pedal: controls live, no brake, no hint")
keys.fwd = true
check(T.CheckOperate.Battery(tesla, part) == false and brakes == 1 and halo == "IGUI_MinidoracatTesla_Deny_CABLE_PLUGGED",
    "plugged in, accelerator down: forced brake set (its own frame held back), red 'unplug the charge cable first'")
halo = nil
check(T.CheckOperate.Battery(tesla, part) == true and brakes == 1 and halo == nil,
    "still held next frame: controls live (the forced brake beats the accelerator), hint at most every 3 s")
H.advanceMs(C.BRAKE_MS)
check(T.CheckOperate.Battery(tesla, part) == false and brakes == 2, "still held BRAKE_MS later: forced brake renewed (1 s window)")
check(T.CheckOperate.Battery(tesla, part) == true and brakes == 2, "never two held-back calls in a row: the next one updates")
H.advanceMs(3001)
T.CheckOperate.Battery(tesla, part)
check(halo == "IGUI_MinidoracatTesla_Deny_CABLE_PLUGGED", "still on the pedal 3 s later: hint again")
keys.fwd, keys.back = nil, true
T.CheckOperate.Battery(tesla, part)
H.advanceMs(C.BRAKE_MS)
check(T.CheckOperate.Battery(tesla, part) == false and brakes == 4, "reverse held: braked too")
keys.back = nil
check(T.CheckOperate.Battery(tesla, part) == true, "pedal released: controls live (a pedal held since before the plug clears)")
drv.getPlayerNum = function() return 1 end -- split screen: player 0's keyboard is not this driver's pedal
keys.fwd = true
H.advanceMs(C.BRAKE_MS)
local b0 = brakes
check(T.CheckOperate.Battery(tesla, part) == true and brakes == b0, "split-screen driver 2: player 0's W key does not count")
drv.getJoypadBind = function() return 2 end
function isJoypadRTPressed(pad) return pad == 2 end
check(T.CheckOperate.Battery(tesla, part) == false and brakes == b0 + 1, "split-screen driver 2: their joypad trigger does")
keys.fwd = nil
-- updateControls as the engine runs it (CarController.java:936-980, brake beats gas :174-178), the accelerator held
-- since before the plug (forward already true, no forced brake yet), at 60 fps and at 600 ms frames: never gas while
-- held past the first frame, clears on release
local fbAt = 0
tesla.setForceBrake = function() fbAt = getTimestampMs() end
drv.getPlayerNum, drv.getJoypadBind = function() return 0 end, function() return -1 end
local function drive(frameMs, frames)
    local ctl, gas = { forward = true, brake = false }, 0
    keys.fwd = nil
    T.CheckOperate.Battery(tesla, part) -- no pedal: nothing pending
    H.advanceMs(1000)
    keys.fwd = true
    for _ = 1, frames do
        H.advanceMs(frameMs)
        if T.CheckOperate.Battery(tesla, part) then -- isOperational -> updateControls
            ctl.forward = keys.fwd == true
            local dt = getTimestampMs() - fbAt
            ctl.brake = dt > 0 and dt < 1000
        end
        if ctl.forward and not ctl.brake then gas = gas + 1 end
    end
    keys.fwd = nil
    H.advanceMs(frameMs)
    if T.CheckOperate.Battery(tesla, part) then ctl.forward = keys.fwd == true end
    return gas, ctl.forward
end
for _, ms in ipairs({ 16, 600 }) do
    local gas, fwd = drive(ms, 60)
    check(gas <= 1 and fwd == false, ms .. " ms frames, accelerator held since before the plug: at most the first frame on gas ("
        .. gas .. "), released -> forward clears")
end
T.Battery.part(tesla):getModData().chg = nil
tesla.driver, tesla.running = nil, false
h:update(); h:update(); h:update()
HaloTextHelper.addBadText = realBad

-- ---------------------------------------------------------------- chargeCardRect (AutoDrive stacks its FSD card on it)
H.section("chargeCardRect")
ISPanelJoypad = ISUIElement:derive("ISPanelJoypad")
function ISPanelJoypad:instantiate() ISUIElement.instantiate(self); if self.createChildren then self:createChildren() end end
function ISPanelJoypad:update() end
function ISPanelJoypad:addChild() end
function ISPanelJoypad:insertNewLineOfButtons() end
function ISPanelJoypad:bringToTop() end
ISButton = ISUIElement:derive("ISButton")
function ISButton:new(x, y, w, hh, title)
    local o = ISUIElement.new(self, x, y, w, hh)
    o.title, o.enable = title, true
    return o
end
function ISButton:setTitle(t) self.title = t end
function ISButton:setEnable(e) self.enable = e end
JoypadState = { players = {} }
H.stub("ISUI/ISPanelJoypad")
H.stub("ISUI/ISButton")
require "MinidoracatTesla/HUDChargeCard"
local cardPlayer = { isDead = function() return false end, getVehicle = function() return tesla end,
    DistTo = function() return 0 end, getSteamID = function() return 0 end, getPlayerNum = function() return 0 end }
local realGetSpecific = getSpecificPlayer
getSpecificPlayer = function() return cardPlayer end
dash:setVehicle(tesla)
local _, _, _, _, cv0 = MinidoracatTeslaAPI.chargeCardRect(0)
check(cv0 == false and select(3, MinidoracatTeslaAPI.chargeCardRect(0)) == 0, "card not open: 0, 0, 0, 0, false")
local card = T.ChargeCard.open(0, tesla)
local function cardAboveHud()
    local cx, cy, cw, ch, cvis = MinidoracatTeslaAPI.chargeCardRect(0)
    local _, hy = MinidoracatTeslaAPI.hudRect(0)
    return cvis == true and cw > 0 and ch > 0 and cy + ch == hy - math.floor(8 * card.S)
        and cx == math.floor((SCREEN_W - cw) / 2), cy + ch
end
local ok1, bottom1 = cardAboveHud()
check(ok1, "card open: rect is the drawn card, centred, bottom 8*S above hudRect")
tesla.parts.DoorFrontLeft.door.open = true -- door pill: the HUD grows upward
h:update(); h:update(); h:update()
card:update()
local ok2, bottom2 = cardAboveHud()
check(ok2 and bottom2 < bottom1, "HUD grew (pill): card and its rect moved up with it (" .. bottom1 .. " -> " .. bottom2 .. ")")
tesla.parts.DoorFrontLeft.door.open = false
h:update(); h:update(); h:update()
card:update()
check((cardAboveHud()), "pill gone: card back down, still 8*S above the HUD")
card:setVisible(false) -- ESC / UI toggled off
local _, _, cw3, _, cv3 = MinidoracatTeslaAPI.chargeCardRect(0)
check(cw3 > 0 and cv3 == false, "UI hidden: rect kept, visible=false (like hudRect)")
card:setVisible(true)
collectgarbage("collect"); collectgarbage("stop")
MinidoracatTeslaAPI.chargeCardRect(0)
local kb = collectgarbage("count")
for _ = 1, 1000 do MinidoracatTeslaAPI.chargeCardRect(0) end
local cgrew = collectgarbage("count") - kb
collectgarbage("restart")
check(cgrew == 0, "chargeCardRect x1000 allocates nothing (" .. cgrew .. " KB)")
-- nopower line by charger kind: a Mobile Connector says where it works (it may sit 5 tiles from a running generator)
local tmd = T.Battery.part(tesla):getModData()
local savedChg, savedItemName, savedPlayer = tmd.chg, getItemName, card.player
card.player = nil -- the cable rule's pre-check (keyless rules, below) needs an inventory; this checks only the line
getItemName = savedItemName or function(t) return t end -- the card names the charger kind (LuaManager.java:8745-8763)
for _, e in ipairs({ { "MobileConnector", "ContextMenu_MinidoracatTesla_MobileNoPower" },
    { "Supercharger", "ContextMenu_MinidoracatTesla_SuperchargerNoPower" },
    { "WallConnector", "IGUI_MinidoracatTesla_Card_NoPowerHint" } }) do
    tmd.chg = { kind = e[1], paused = "nopower", kw = T.Chargers[e[1]].kw, last = T.hours(), target = 90, added = 0 }
    card.key = ""
    card:read()
    check(card.state == "nopower" and card.sAlert == e[2], "card nopower line for the " .. e[1] .. ": " .. tostring(card.sAlert))
end
-- a Supercharger charging: its own title, the kW on the DC curve right now (Core.lua B.chargeKwAt), as the app's
local tpart = T.Battery.part(tesla)
for _, e in ipairs({ { "Supercharger", 250, "IGUI_MinidoracatTesla_Card_Supercharging" },
    { "WallConnector", nil, "IGUI_MinidoracatTesla_Card_Charging" } }) do
    tmd.chg = { kind = e[1], kw = e[2] or 11.5, peak = e[2], last = T.hours(), target = 90, added = 0, src = "grid" }
    card.key = ""
    card:read()
    local want = T.Battery.chargeKwAt(tmd.chg, T.Battery.capacity(tpart), T.Battery.kwh(tpart))
    local t = math.floor(want * 10 + 0.5)
    check(card.state == "charging" and card.sTitle == e[3] and card.sKw == math.floor(t / 10) .. "." .. t % 10 .. " kW"
        and (e[2] == nil or want < e[2]), string.format("%s charging: title %s, %s at %.0f %%", e[1], card.sTitle,
            card.sKw, T.Battery.pct(tpart)))
end
tmd.chg, card.kind, card.key, card.player = savedChg, nil, "", savedPlayer
card:read()
getItemName = savedItemName
-- vanilla Gas Consumption (CarGasConsumption): 2 halves the range; 0 = driving takes no charge, no range limit
-- (Core.lua T.kmPerKwh nil). The dashboard's Inter atlas draws "∞ km"; the game's UIFont.Small has no ∞
-- (media/fonts/*.fnt), so the texts say "--"
local realGT0, savedChg0, savedPlayer0 = getText, tmd.chg, card.player
getItemName = function(t) return t end -- LuaManager.java:8745-8763 (the charger's name on the card)
getText = function(k, a) return a and (k .. "|" .. a) or k end
dash:setVehicle(nil); dash:setVehicle(tesla)
local range1 = h.st.range
-- no re-attach below: an admin's sandbox window changes these mid-drive (drive-range-ui-mp saw the range stay put)
SandboxVars.MinidoracatTesla = SandboxVars.MinidoracatTesla or {}
local savedRange = SandboxVars.MinidoracatTesla.RangeMultiplier
SandboxVars.MinidoracatTesla.RangeMultiplier = 10
h:update(); h:update(); h:update()
check(math.abs(h.st.range - range1 * 10) <= 10, "RangeMultiplier 10 set while seated: the dashboard range x 10 (" .. range1 .. " -> " .. h.st.range .. ")")
SandboxVars.MinidoracatTesla.RangeMultiplier = savedRange
SandboxVars.CarGasConsumption = 2
h:update(); h:update(); h:update()
check(math.abs(h.st.range - range1 / 2) <= 1, "Gas Consumption 2: the dashboard range halves (" .. range1 .. " -> " .. h.st.range .. ")")
SandboxVars.CarGasConsumption = 0
dash:setVehicle(nil); dash:setVehicle(tesla)
local inf = T.HUDAtlas[1].inf
local function drawsInf()
    if not inf then return false end
    for i = 1, h.n, 12 do
        if h.L[i] == inf[1] and h.L[i + 1] == inf[2] and h.L[i + 2] == inf[3] then return true end
    end
    return false
end
check(h.st.range == nil and drawsInf(), "Gas Consumption 0: the dashboard range is the atlas ∞ before km")
tmd.chg = { kind = "WallConnector", x = 0, y = 0, z = 0, kw = 11.5, target = 90, last = T.hours() - 0.5, added = 0 }
h:update(); h:update(); h:update()
card.player, card.key = nil, ""
card:read()
check(h.msgId == 4 and h.msgSub == "IGUI_MinidoracatTesla_HUD_ChargingSub|--" and card.sAddKm == "+-- km",
    "Gas Consumption 0, charging: the pill and the card say +-- km (" .. tostring(h.msgSub) .. ", " .. tostring(card.sAddKm) .. ")")
tmd.chg = nil
local tpart = T.Battery.part(tesla)
tpart:setContainerContentAmount(7.84) -- 10 %
h:update(); h:update(); h:update()
check(h.msgId == 3 and h.msgSub == "IGUI_MinidoracatTesla_HUD_LowBatterySub|--", "Gas Consumption 0, low battery: -- km left (" .. tostring(h.msgSub) .. ")")
tpart:setContainerContentAmount(0)
h:update(); h:update(); h:update()
check(h.st.range == 0 and not drawsInf(), "Gas Consumption 0, empty pack: 0 km (it cannot start), not ∞")
tpart:setContainerContentAmount(39.2)
SandboxVars.CarGasConsumption = nil
getText, tmd.chg, card.player, card.key = realGT0, savedChg0, savedPlayer0, ""
dash:setVehicle(nil); dash:setVehicle(tesla)
check(h.st.range == range1, "Gas Consumption unset: the range as before (" .. tostring(h.st.range) .. ")")
card:read()
getItemName = savedItemName

-- ---------------------------------------------------------------- units (Units.lua)
-- Imperial is display only: the read model stays km and km/h; the unit words, the digits and the strings change
H.section("units")
do
    local U, A, MI = T.Units, h.A, 0.621371
    local function draws(e) -- the atlas sprite is in the quad list
        for i = 1, h.n, 12 do
            if h.L[i] == e[1] and h.L[i + 1] == e[2] and h.L[i + 2] == e[3] then return true end
        end
        return false
    end
    local function number(set) -- the digits of `set` in the quad list, in draw order
        local s = ""
        for i = 1, h.n, 12 do
            for d = 0, 9 do
                local e = set[d]
                if h.L[i] == e[1] and h.L[i + 1] == e[2] and h.L[i + 2] == e[3] then s = s .. d end
            end
        end
        return s
    end
    local function mi(km) return math.floor(km * MI + 0.5) end
    local function three() h:update(); h:update(); h:update() end
    local unit, speed0, realGT, cardPlayer0 = 1, tesla.speed, getText, card.player
    getText = function(k, a) return a and (k .. "|" .. a) or k end
    getItemName = function(t) return t end
    card.player = nil
    tesla.speed = 70 -- the speed shows with the motor off too (a towed or rolling car)
    three()
    local _, _, w0 = MinidoracatTeslaAPI.hudRect(0)
    local function metric()
        return h.st.kmh == 70 and number(A.big) == "70" and number(A.sm) == tostring(range1) and draws(A.kmh)
            and draws(A.km) and not draws(A.mph) and not draws(A.mi)
    end
    check(metric(), "no option (the harness has no PZAPI): 70 km/h, the range in km")
    U.opt = { getValue = function() return unit end }
    h:update()
    check(metric(), "the option on Metric: the same")
    unit = 2
    h:update()
    check(h.st.kmh == 70 and number(A.big) == "43" and draws(A.mph) and not draws(A.kmh),
        "Imperial, one update later: 70 km/h reads 43 mph (AutoDrive's card at a 70 limit); the read model stays 70 (" .. number(A.big) .. ")")
    check(h.st.range == range1 and number(A.sm) == tostring(mi(range1)) and draws(A.mi) and not draws(A.km),
        "... the range in mi, right of its digits (" .. range1 .. " km -> " .. number(A.sm) .. ")")
    local steady = true
    for i = 1, 20 do -- 43.47 and 43.52 mph: rounding the mph itself would flip 43 / 44
        tesla.speed = i % 2 == 0 and 69.96 or 70.04
        h:update()
        steady = steady and number(A.big) == "43"
    end
    check(steady, "a cruise wobbling around 70 km/h: 43 mph every update")
    tesla.speed = 0.4
    h:update()
    local slow = number(A.big)
    tesla.speed = -30
    h:update()
    check(slow == "0" and number(A.big) == "19", "0.4 km/h reads 0; reversing at 30 km/h reads 19 mph")
    tesla.speed = 0
    three()
    local _, _, w1 = MinidoracatTeslaAPI.hudRect(0)
    check(w1 == w0, "hudRect: the same width in mph (AutoDrive places its HUD by it)")

    -- the pill and the charge card
    unit = 1
    tmd.chg = { kind = "WallConnector", x = 0, y = 0, z = 0, kw = 11.5, target = 90, last = T.hours() - 0.5, added = 0 }
    three()
    card.key = ""
    card:read()
    local km = tonumber(tostring(h.msgSub):match("ChargingSub|(%d+)$"))
    local cardKm = tonumber(card.sAddKm:match("^%+(%d+) km$"))
    check(h.msgId == 4 and (km or 0) > 0 and (cardKm or 0) > 0, "Metric, charging: +N km on the pill and the card ("
        .. tostring(h.msgSub) .. ", " .. card.sAddKm .. ")")
    unit = 2
    h:update()
    card:read() -- its key holds the unit: the strings again with nothing else changed
    check(h.msgSub == "IGUI_MinidoracatTesla_HUD_ChargingSubMi|" .. mi(km or 0),
        "Imperial, one update later: the pill's own key with the miles (" .. tostring(h.msgSub) .. ")")
    check(card.sAddKm == "+" .. mi(cardKm or 0) .. " mi", "... the card's next read: " .. card.sAddKm)
    tmd.chg = nil
    unit = 1
    tpart:setContainerContentAmount(7.84) -- 10 %
    three()
    local left = tonumber(tostring(h.msgSub):match("LowBatterySub|(%d+)$"))
    unit = 2
    h:update()
    check(h.msgId == 3 and left ~= nil and h.msgSub == "IGUI_MinidoracatTesla_HUD_LowBatterySubMi|" .. mi(left or 0),
        "low battery: " .. tostring(left) .. " km left -> " .. tostring(h.msgSub))
    -- no range limit (Gas Consumption 0): the unit words still follow, with no number to convert
    SandboxVars.CarGasConsumption = 0
    dash:setVehicle(nil); dash:setVehicle(tesla)
    three()
    check(h.st.range == nil and draws(A.inf) and draws(A.mi) and not draws(A.km)
        and h.msgSub == "IGUI_MinidoracatTesla_HUD_LowBatterySubMi|--", "no range limit: ∞ before mi, -- mi left")
    tmd.chg = { kind = "WallConnector", x = 0, y = 0, z = 0, kw = 11.5, target = 90, last = T.hours() - 0.5, added = 0 }
    three()
    card.key = ""
    card:read()
    check(h.msgSub == "IGUI_MinidoracatTesla_HUD_ChargingSubMi|--" and card.sAddKm == "+-- mi",
        "no range limit, charging: +-- mi (" .. tostring(h.msgSub) .. ", " .. card.sAddKm .. ")")
    unit = 1
    h:update()
    card:read()
    check(card.sAddKm == "+-- km" and h.msgSub == "IGUI_MinidoracatTesla_HUD_ChargingSub|--"
        and draws(A.km) and not draws(A.mi), "back on Metric with no number to change: every unit word follows")
    tmd.chg = nil
    tpart:setContainerContentAmount(39.2)
    SandboxVars.CarGasConsumption = nil
    dash:setVehicle(nil); dash:setVehicle(tesla)

    -- the Chill badge sits beside the unit word: not moved by the narrower mph, which must not be the wider one
    tmd.chill = true
    unit = 2
    three()
    local chillX = h.chillX
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for _ = 1, 1000 do h:prerender() end
    local kbGrew = collectgarbage("count") - kb0
    collectgarbage("restart")
    check(kbGrew == 0, "Imperial: prerender x1000 allocates nothing (" .. kbGrew .. " KB)")
    unit = 1
    three()
    check(chillX ~= nil and h.chillX == chillX, "the Chill badge: the same place in both units")
    for k = 1, 2 do
        local a = T.HUDAtlas[k]
        check(a.mph[7] <= a.kmh[7], "atlas " .. k .. "x: mph is no wider than km/h (" .. a.mph[7] .. " <= " .. a.kmh[7] .. ")")
    end
    tmd.chill = nil

    U.opt = nil
    tesla.speed, getText, card.player = speed0, realGT, cardPlayer0
    card.key = ""
    card:read()
    getItemName = savedItemName
    three()
    check(h.st.range == range1 and number(A.sm) == tostring(range1) and draws(A.km) and h.st.chill == false,
        "the option gone: as before")
end
-- the driver on the charge card's buttons twice a second for a minute (+, +, -, start/stop), each request through the
-- server's dispatch (Commands.lua CommandRate, the `default` budget the camp key and the rest share): none dropped,
-- and the busiest 10 s keeps half its budget again to spare
cardPlayer.getOnlineID, cardPlayer.getUsername = function() return 9300 end, function() return "driver" end
local CR = T.CommandRate
local press = { function() card:onPlus() end, function() card:onPlus() end, function() card:onMinus() end,
    function() card:onToggle() end }
local dropped0, from, reached, times = CR.dropped.default or 0, #H.clientSent, 0, {}
for i = 0, 119 do
    H.side(true, false)
    press[i % #press + 1]()
    for _ = from + 1, #H.clientSent do times[#times + 1] = i * 500 end
    local got
    got, from = H.serve(from)
    for _, n in pairs(got) do reached = reached + n end
    H.advanceMs(500)
end
H.side(true, false)
local busiest = H.busiest(times, CR.LIMITS.default.ms)
check(#times == 120 and reached == 120 and (CR.dropped.default or 0) == dropped0 and busiest * 1.5 <= CR.LIMITS.default.max,
    "a minute on the charge card, 2 clicks a second (" .. busiest .. " in the busiest 10 s): all " .. reached .. " of "
    .. #times .. " reach the server's handler")
-- the cable rule on the card (Chargers.lua T.mayUseCable, as the server's chargeTarget / chargeStop / unplug): no key
-- and a locked car = target %, stop and unplug greyed, the hover help says why; unlocked or with the key they work
local realItemName = getItemName
getItemName = function(t) return t end -- LuaManager.java:8745-8763 (the charger's name on the card)
local cmd = T.Battery.part(tesla):getModData()
cmd.chg = { kind = "WallConnector", x = 0, y = 0, z = 0, kw = 11.5, target = 90, last = T.hours(), paused = nil }
cardPlayer.getInventory = function()
    return { haveThisKeyId = function(_, id) return cardPlayer.key == id and {} or nil end,
        getFirstTypeEvalArgRecurse = function() return nil end }
end
local cardBtns = { card.btnToggle, card.btnUnplug, card.btnMinus, card.btnPlus }
local function cardState()
    card.key = ""
    card:read()
    local on, tips = 0, {}
    for _, b in ipairs(cardBtns) do
        if b.enable then on = on + 1 end
        tips[b.tipKey] = true
    end
    return on, tips
end
tesla.locked = true
local on, tips = cardState()
check(on == 0 and tips["IGUI_MinidoracatTesla_Deny_CAR_LOCKED"] and next(tips, next(tips)) == nil,
    "card, no key, car locked: all four charging buttons greyed, the help says CAR_LOCKED")
tesla.locked = false
on, tips = cardState()
check(on == 4 and tips["IGUI_MinidoracatTesla_Tip_CardStop"] and tips["IGUI_MinidoracatTesla_Tip_CardUnplug"],
    "card, no key, car unlocked: the buttons work, their own help")
tesla.locked, cardPlayer.key = true, tesla.keyId
on = cardState()
check(on == 4, "card, the key on you, car locked: the buttons work")
-- the charger's owner (T.chargerOwner, the synced `owner`): no key, car locked -> stop (while charging) and unplug,
-- not the target nor resuming
T.Charge = T.Charge or {}
local realChargerAt = T.Charge.chargerAt
T.Charge.chargerAt = function(x, y, z) return x == 0 and y == 0 and z == 0 and { owner = cardPlayer:getUsername() } or nil end
cardPlayer.key = nil
cardState()
check(card.btnToggle.enable and card.btnUnplug.enable and not card.btnMinus.enable and not card.btnPlus.enable
    and card.btnMinus.tipKey == "IGUI_MinidoracatTesla_Deny_CAR_LOCKED" and card.btnUnplug.tipKey == "IGUI_MinidoracatTesla_Tip_CardUnplug",
    "card, the charger's owner, car locked, charging: stop and unplug work, the target % is greyed (CAR_LOCKED)")
cmd.chg.paused = "stopped"
cardState()
check(not card.btnToggle.enable and card.btnUnplug.enable, "card, the charger's owner, stopped: resuming is the target's rule, greyed; unplug works")
cmd.chg.paused = nil
T.Charge.chargerAt = realChargerAt
tesla.locked, cardPlayer.key, cardPlayer.getInventory, cmd.chg = false, nil, nil, nil
card.key = ""
card:read()
getItemName = realItemName
card:close()
check(select(5, MinidoracatTeslaAPI.chargeCardRect(0)) == false, "card closed: visible=false")
getSpecificPlayer = realGetSpecific

-- ---------------------------------------------------------------- radial menu
H.section("radial menu")
local p = H.player({ keys = { [tesla.keyId] = true } })
p.vehicle = tesla
p.getPlayerNum = function() return 0 end
tesla.running = false
ISVehicleMenu.showRadialMenu(p)
-- a slice's text with its second line's breaks taken out (HUDRadial.lua line2 breaks it to the icon ring's 220 px;
-- this harness's getText returns the long keys, cut where they reach it)
local function flat(text) local head, rest = text:match("^([^\n]*)\n(.*)$"); return head and (head .. "|" .. rest:gsub("\n", "")) or text end
local camp, status
for _, s in ipairs(menu.slices) do
    if flat(s.text) == "IGUI_MinidoracatTesla_Radial_CampOn|IGUI_MinidoracatTesla_HUD_CampSub" then camp = s end
    if flat(s.text) == "IGUI_MinidoracatTesla_Radial_ChargeStatus|IGUI_MinidoracatTesla_Tip_ChargeStatus" then status = s end
end
check(camp ~= nil and camp.fn ~= nil and status ~= nil, "radial: camp (enabled) and charging status, each with a what-it-does line")
-- a long second line breaks into lines inside the ring, nothing lost (E2E tesla-ctlang-1031m-ko: Korean ran over icons)
local realGetText = getText
getText = function(k, ...)
    if k == "IGUI_MinidoracatTesla_Tip_ChargeStatus" then return "Charge level, power and time to target, all in one card" end
    return realGetText(k, ...)
end
ISVehicleMenu.showRadialMenu(p) -- closes
ISVehicleMenu.showRadialMenu(p)
getText = realGetText
local tipLines, tipOk = {}, true
for _, s in ipairs(menu.slices) do
    if s.text:find("Radial_ChargeStatus", 1, true) then
        for l in s.text:gmatch("[^\n]+") do tipLines[#tipLines + 1] = l end
    end
end
for i = 2, #tipLines do if getTextManager():MeasureStringX(UIFont.Medium, tipLines[i]) > 220 then tipOk = false end end
check(#tipLines >= 3 and tipOk and table.concat(tipLines, " ", 2) == "Charge level, power and time to target, all in one card",
    "radial: a long second line in lines of at most 220 px, words kept (" .. table.concat(tipLines, "|") .. ")")
-- balanced lines (Core.lua T.wrapText): the greedy "Powers the home in a / blackout" comes out even
check(T.wrapText("Powers the home in a blackout", 220, UIFont.Medium) == "Powers the home\nin a blackout",
    "radial: two lines come out even, not a long line and one word")
-- " · " (U+00B7, the thrusters' whyText join): the space before the dot holds, the one after breaks (8 px a byte, the
-- dot 2 bytes): room up to the dot ends the line before the word ahead of it, never a line starting with the dot
do
    local s = "aa word \194\183 next"
    local l1, rest = T.cutLine(s, 8 * 8, UIFont.Medium) -- "aa word " fits, "aa word ·" does not
    check(l1 == "aa" and rest == "word \194\183 next", "cutLine: the room ends before the dot: the line breaks before its word ("
        .. l1 .. "|" .. rest .. ")")
    l1, rest = T.cutLine(s, 10 * 8, UIFont.Medium)
    check(l1 == "aa word \194\183" and rest == "next", "cutLine: room for the dot: broken after it (" .. l1 .. "|" .. rest .. ")")
end
local sleep = menu.slices[2]
check(sleep.text == "Sleep\nTooltip_BedType" and sleep.fn == ISVehicleMenu.onSleep, "radial: vanilla Sleep slice gets the bed quality line")
check(ISWorldObjectContextMenu.getBedQuality(p, nil) == "badBed", "bed: not camping -> vanilla bad bed")
T.Battery.part(tesla):getModData().camp = { by = "x" }
p.getPrimaryHandItem = function() return nil end
p.getSecondaryHandItem = function() return nil end
tesla.getSeat = function() return 0 end
tesla.getPartForSeatContainer = function() return { getItemContainer = function() return { containsTag = function() return false end } end } end
check(ISWorldObjectContextMenu.getBedQuality(p, nil) == "averageBed", "bed: camping -> average bed (wrapped getBedQuality)")
T.Battery.part(tesla):getModData().camp = nil
ISVehicleMenu.showRadialMenu(p)
check(#menu.slices == 0, "radial: second press closes, nothing re-added")
tesla.running, tesla.speed = true, 30
ISVehicleMenu.showRadialMenu(p)
local grey
for _, s in ipairs(menu.slices) do
    if s.text:find("Radial_CampOn", 1, true) then grey = s end
end
check(grey ~= nil and grey.fn == nil and flat(grey.text):find("|IGUI_MinidoracatTesla_Deny_MOVING", 1, true) ~= nil,
    "radial: camp greyed with the deny reason while driving")

-- key in a bag (Keys.lua bagKeyStarts): vanilla's hotwire slice, either kind, becomes Start Engine in place
local realKeys, bagKey = T.Keys, true
T.Keys = { bagKeyStarts = function(pl, v) return bagKey and pl == p and v == tesla end }
tesla.driver, tesla.running, tesla.speed = p, false, 0
function tesla:isEngineWorking() return true end
local function startSlices()
    local starts, hotwire, at = 0, false, nil
    for i, s in ipairs(menu.slices) do
        if s.command[1] == ISVehicleMenu.onStartEngine then starts, at = starts + 1, i end
        if s.command[1] == ISVehicleMenu.onHotwire or s.text == "ContextMenu_VehicleHotwireSkill" then hotwire = true end
    end
    return starts, hotwire, at
end
for _, c in ipairs({
    { name = "can hotwire", slice = { text = "ContextMenu_VehicleHotwire", fn = ISVehicleMenu.onHotwire } },
    { name = "greyed hotwire (no skill)", slice = { text = "ContextMenu_VehicleHotwireSkill" } },
    { name = "no hotwire slice" },
}) do
    hotwireSlice, menu.open = c.slice, false
    ISVehicleMenu.showRadialMenu(p)
    local starts, hotwire, at = startSlices()
    local s = menu.slices[at or 0]
    check(starts == 1 and not hotwire and s.text == "ContextMenu_VehicleStartEngine" and s.command[2] == p
        and (s.tex or {}).path == "media/ui/vehicles/vehicle_ignitionON.png" and at == (c.slice and 2 or 3),
        "radial, key in a bag, " .. c.name .. ": one Start Engine " .. (c.slice and "in that slot" or "added") .. ", no hotwiring")
end
bagKey, hotwireSlice, menu.open = false, { text = "ContextMenu_VehicleHotwire", fn = ISVehicleMenu.onHotwire }, false
ISVehicleMenu.showRadialMenu(p)
local starts, hotwire = startSlices()
check(starts == 0 and hotwire and menu.slices[2].command[1] == ISVehicleMenu.onHotwire,
    "radial, no key: vanilla hotwiring stays, no Start Engine")
T.Keys, hotwireSlice, tesla.driver, tesla.isEngineWorking = realKeys, nil, nil, nil
menu.open = false

-- Bioweapon Defense Mode (Specs hepa: anyone inside) and Chill (the driver). The official French name stands in for the
-- long ones (fr_fr owner's manual): the title breaks inside the ring like the second line
local FR_ON, FR_OFF = "Activer le mode de défense contre les armes biologiques", "Désactiver le mode de défense contre les armes biologiques"
local textOf = getText
getText = function(k, ...)
    if k == "IGUI_MinidoracatTesla_Radial_BdmOn" then return FR_ON end
    if k == "IGUI_MinidoracatTesla_Radial_BdmOff" then return FR_OFF end
    return textOf(k, ...)
end
local function sliceOf(key)
    for _, s in ipairs(menu.slices) do if s.text:gsub("\n", " "):find(key, 1, true) == 1 then return s end end
end
-- every line inside the ring's 220 px but the harness's untranslated tip key (no space to break at)
local function fits(s, nLines)
    local n = 0
    for l in s.text:gmatch("[^\n]+") do
        n = n + 1
        if not l:find("IGUI_", 1, true) and getTextManager():MeasureStringX(UIFont.Medium, l) > 220 then return false end
    end
    return n >= nLines
end
tesla.driver, tesla.isEngineWorking = nil, nil
ISVehicleMenu.showRadialMenu(p)
local bdmSlice = sliceOf(FR_ON)
check(bdmSlice and bdmSlice.text:gsub("\n", " "):find(FR_ON .. " ", 1, true) == 1 and bdmSlice.text:gsub("\n", ""):find("IGUI_MinidoracatTesla_Tip_Bdm", 1, true) and fits(bdmSlice, 3)
    and bdmSlice.tex.path:find("radial_bdm.png", 1, true) and sliceOf("IGUI_MinidoracatTesla_Radial_Chill") == nil,
    "radial, Model Y passenger: Bioweapon Defense Mode, its long title in lines inside the ring, its line; no Chill (driver only)")
local sent0 = #H.clientSent
bdmSlice.fn(bdmSlice.a1, bdmSlice.a2, bdmSlice.a3)
check(#H.clientSent == sent0 + 1 and H.clientSent[#H.clientSent].command == "bdm"
    and H.clientSent[#H.clientSent].args.vid == tesla:getId(), "radial: the slice sends bdm { vid }")
menu.open = false
tesla.driver, tesla.isEngineWorking = p, function() return false end -- no Start Engine slice in the way
T.Battery.part(tesla):getModData().bdm = true
ISVehicleMenu.showRadialMenu(p)
local chillSlice = sliceOf("IGUI_MinidoracatTesla_Radial_ChillOn")
local offSlice = sliceOf(FR_OFF)
check(offSlice and offSlice.text:gsub("\n", " ") == FR_OFF and fits(offSlice, 2)
    and chillSlice and flat(chillSlice.text) == "IGUI_MinidoracatTesla_Radial_ChillOn|IGUI_MinidoracatTesla_Tip_Chill",
    "radial, driver, BDM on: Turn off (no second line), and Chill with its line")
getText = textOf
chillSlice.fn(chillSlice.a1, chillSlice.a2, chillSlice.a3)
check(H.clientSent[#H.clientSent].command == "chill" and H.clientSent[#H.clientSent].args.vid == tesla:getId(),
    "radial: the Chill slice sends chill { vid }")
menu.open = false
T.Battery.part(tesla):getModData().bdm = nil
local m3car = car({ script = "Base.MinidoracatTesla_Model3", kwh = 30 })
local p3 = H.player({ keys = { [m3car.keyId] = true } })
p3.vehicle, p3.getPlayerNum, m3car.driver = m3car, function() return 0 end, p3
m3car.isEngineWorking = function() return false end
ISVehicleMenu.showRadialMenu(p3)
check(sliceOf("IGUI_MinidoracatTesla_Radial_Bdm") == nil and sliceOf("IGUI_MinidoracatTesla_Radial_ChillOn") ~= nil,
    "radial, Model 3 (no HEPA in its manuals): no Bioweapon Defense Mode slice; Chill for its driver")
menu.open = false
tesla.driver, tesla.isEngineWorking = nil, nil

-- the HUD's Chill badge: shown while md.chill, its text drawn in prerender
dash:setVehicle(tesla)
T.Battery.part(tesla):getModData().chill = true
h:update(); h:update(); h:update()
lastText = nil
h:prerender()
check(h.st.chill == true and h.chillX ~= nil and h.chillText == "IGUI_MinidoracatTesla_HUD_Chill" and lastText == h.chillText,
    "HUD: Chill on -> badge beside km/h, its text drawn")
T.Battery.part(tesla):getModData().chill = nil
h:update(); h:update(); h:update()
check(h.st.chill == false and h.chillX == nil, "HUD: Chill off -> no badge")
dash:setVehicle(nil)
H.side(false, true)
