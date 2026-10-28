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

-- radial menu: vanilla toggles (ISVehicleMenu.lua:67-76) and adds its own "Sleep" slice (:225)
local menu = { slices = {}, open = false }
function menu:isReallyVisible() return self.open end
function menu:addSlice(text, tex, fn, a1, a2)
    self.slices[#self.slices + 1] = { text = text, fn = fn, a1 = a1, a2 = a2, command = { fn, a1, a2 } }
end
function menu:setSliceText(i, text) self.slices[i].text = text end -- ISRadialMenu.lua:55
function getPlayerRadialMenu() return menu end
ISVehicleMenu = { onSleep = function() end }
ISVehicleMenu.showRadialMenu = function()
    if menu.open then menu.open = false; menu.slices = {}; return end
    menu.slices = {}; menu:addSlice("vanilla"); menu:addSlice("Sleep", nil, ISVehicleMenu.onSleep); menu.open = true
end
H.stub("Vehicles/ISUI/ISVehicleMenu")
ISWorldObjectContextMenu = { getBedQuality = function() return "badBed" end } -- vanilla: any car seat (ISWorldObjectContextMenu.lua:2923-2934)
H.stub("ISUI/ISWorldObjectContextMenu")

require "MinidoracatTesla/ParkModes"
require "MinidoracatTesla/HUD"
require "MinidoracatTesla/HUDRadial"
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
local function partName(id) local k = "IGUI_VehiclePart" .. id; return T.PartNames and T.PartNames[k] or k end
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
    DistTo = function() return 0 end }
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
local camp, status
for _, s in ipairs(menu.slices) do
    if s.text == "IGUI_MinidoracatTesla_Radial_CampOn\nIGUI_MinidoracatTesla_HUD_CampSub" then camp = s end
    if s.text == "IGUI_MinidoracatTesla_Radial_ChargeStatus\nIGUI_MinidoracatTesla_Tip_ChargeStatus" then status = s end
end
check(camp ~= nil and camp.fn ~= nil and status ~= nil, "radial: camp (enabled) and charging status, each with a what-it-does line")
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
check(grey ~= nil and grey.fn == nil and grey.text:find("\nIGUI_MinidoracatTesla_Deny_MOVING", 1, true) ~= nil,
    "radial: camp greyed with the deny reason while driving")
menu.open = false
H.side(false, true)
