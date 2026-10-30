-- Tesla app on the phone key (design: plan-phone-app-1027, user answers 2026-10-27; looks after the real Tesla app,
-- decisions.md "手機 App 第一版", mock temp/app-style/restyle.html). Opened from the phone key's right-click menu
-- (KeysUI.lua). While open it asks the server for its car every POLL_MS; the server (server/MinidoracatTesla/Remote.lua)
-- answers holders of that phone key only and checks every command again. Players without the app open cost nothing.
-- The car is named by keyId (self.key) in every request.
-- One phone key, several cars (decisions.md "手機 App 第二版"): the car name on the home page opens the car list
-- ("cars" page): every car the phone keys on the player are paired with, then the Teslas VehicleManager lists for this
-- player that no phone here is paired with (MinidoracatTesla.VMLink.cars: last position only; remote buttons dimmed,
-- pressing one says how to add the car). Only the selected car is polled; the list's grey lines come from App.seen,
-- refreshed when the list opens (one appStatusAll per App.BATCH cars, one a LIST_MS).
-- Pages: "home" (name, battery, the car in its paint, four quick icons, a list into the sub pages), "controls" (flash,
-- horn, frunk, liftgate; a Cybertruck's Powershare cell), "location" (arrow, distance, "Show on map", "Navigate to car"
-- with the MiniMap's setNavTarget), "summon", "pick", "security" (Sentry Mode, alerts), "charging", "cars",
-- "powershare" (Cybertruck, plan 4: Powershare, its discharge limit 5-90 %, the bed outlet).
-- "summon" (only with AutoDrive's summon API, App.summonApi; design temp/plan-summon-1027): AutoDrive drives the empty
-- car to the player ("come"), to a point picked on the "pick" page's map ("target"), or straight ahead / back
-- ("dumb"). One tap starts, another stops; the server (Remote.lua ACT.summon) and AutoDrive check everything again.
-- "Show on map" opens the world map on the car and draws a marker after vanilla's map: never saved, gone when the map
-- closes (the app comes back on the location page). While the MiniMap draws that car there itself, its marker
-- (MiniMapBridge.lua) is the marker.
-- Drawing: the dashboard atlas (2x; HUD.spr / HUD.rrect), S scale, HUD.drawTip. Buttons are bare hit areas; the app
-- draws everything. Joypad: the D-pad moves along the page's rows (NAV), A presses, B goes back (home: closes).
-- A page taller than this player's screen scrolls below its header (mouse wheel; joypad focus scrolls itself in).
require "ISUI/ISUIElement"
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISMapDefinitions"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/Keys"
require "MinidoracatTesla/Chargers"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local K = T.Keys
local HUD = T.HUD
local App = ISPanelJoypad:derive("MinidoracatTeslaPhoneApp")
T.PhoneApp = App
T.ClientCommands = T.ClientCommands or {}
App.POLL_MS = 2000
App.TOAST_MS = 4000
App.stats = { polls = 0, states = 0, sent = 0, batches = 0 }
local apps = {} -- [playerNum]

local W, PAD = 340, 20
App.NAV_API = 12 -- MinidoracatMiniMapAPI.navApiVersion with setNavTarget (MiniMap docs/addon-api.md)
App.SUMMON_API = 1 -- MinidoracatAutoDriveAPI.summonApiVersion: summon with its three modes
App.SUMMON_MS = 500 -- the summon view (AutoDrive's canSummon / summonState) is read this often, and after each change
-- the client's last view of each car, by keyId: what the car list's grey lines and the MiniMap marker show.
-- ponytail: one table for all split-screen players (only player 0 gets MiniMap markers); key it by playerNum if
-- split-screen phone keys ever matter.
App.seen, App.seenRev = {}, 0
local P = "IGUI_MinidoracatTesla_App_"
local TIP = "IGUI_MinidoracatTesla_Tip_App"
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function rgb(hex)
    return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255 }
end
-- the real Tesla app's colours (decisions.md): blue only for main actions, no card fills, a 1 px frame on the control
-- tiles. build_atlas.py PAL app* holds the same hex values and asserts their contrast: change both.
local C = { bg = rgb("#161718"), text = rgb("#F3F3F3"), text2 = rgb("#8A8B8B"), weak = rgb("#454546"),
    line = rgb("#2E2F30"), blue = rgb("#3268FE"), ok = HUD.C.ok, warn = HUD.C.warn, white = HUD.C.white,
    pin = rgb("#E0463B") } -- the summon mock's map pin

-- hit areas: id -> { page, server action }; the list rows open the page of their own name. The car list's rows are
-- made on demand (App:pickButton, ids pick1, pick2, ...).
local BTN = {
    close = { "home" }, cars = { "home" }, lock = { "home", "lock" }, qcharge = { "home", "charge" },
    qfrunk = { "home", "frunk" }, qtrunk = { "home", "trunk" }, controls = { "home" }, location = { "home" },
    security = { "home" }, charging = { "home" }, summon = { "home" },
    back = {}, flash = { "controls", "flash" }, horn = { "controls", "horn" }, frunk = { "controls", "frunk" },
    trunk = { "controls", "trunk" }, tonneau = { "controls", "tonneau" }, map = { "location" }, navcar = { "location" },
    sentry = { "security", "sentry" },
    charge = { "charging", "charge" },
    -- Cybertruck (plan 4): the Powershare cell opens its page; Powershare, its discharge limit and the bed outlet
    powershare = { "controls" }, psToggle = { "powershare", "powershare" }, floorDown = { "powershare", "psFloor" },
    floorUp = { "powershare", "psFloor" }, outlet = { "powershare", "outlet" },
    come = { "summon" }, pick = { "summon" }, fwd = { "summon" }, rev = { "summon" }, again = { "summon" },
    finish = { "summon" }, cancel = { "pick" }, go = { "pick" },
}
local BTN_ORDER = { "close", "cars", "lock", "qcharge", "qfrunk", "qtrunk", "controls", "location", "summon", "security",
    "charging", "back", "flash", "horn", "frunk", "trunk", "tonneau", "map", "navcar", "sentry", "charge", "come", "pick",
    "fwd", "rev", "again", "finish", "cancel", "go", "powershare", "psToggle", "floorDown", "floorUp", "outlet" }
-- the joypad's rows per page, top to bottom (buttons not shown are skipped); "cars" is built with its rows
local NAV = {
    home = { { "cars", "close" }, { "lock", "qcharge", "qfrunk", "qtrunk" }, { "controls" }, { "location" }, { "summon" },
        { "security" }, { "charging" } },
    controls = { { "back" }, { "flash", "horn" }, { "frunk", "trunk" }, { "tonneau", "powershare" } },
    location = { { "back" }, { "map" }, { "navcar" } },
    security = { { "back" }, { "sentry" } },
    charging = { { "back" }, { "charge" } },
    cars = { { "back" } },
    summon = { { "back" }, { "come" }, { "pick" }, { "fwd", "rev" }, { "again" }, { "finish" } },
    pick = { { "back" }, { "spot" }, { "cancel", "go" } }, -- spot: the map (D-pad moves the pin)
    powershare = { { "back" }, { "floorDown", "floorUp" }, { "psToggle" }, { "outlet" } },
}
-- the server actions: dimmed but pressable for a car this phone is not paired with (they say how to add it)
local REMOTE = { "lock", "qcharge", "qfrunk", "qtrunk", "flash", "horn", "frunk", "trunk", "tonneau", "sentry", "charge",
    "psToggle", "floorDown", "floorUp", "outlet" }
local QUICK = { "lock", "qcharge", "qfrunk", "qtrunk" }
local LIST = { "controls", "location", "summon", "security", "charging" }
local LIST_ICON = { controls = "i_carfront", location = "i_nav", summon = "i_wheel", security = "i_shield", charging = "i_bolt" }
local TITLE = { controls = "Controls", location = "Location", security = "Security", charging = "ChargingTitle", cars = "Cars",
    summon = "Summon", pick = "SummonPick", powershare = "Powershare" }
-- the summon pages' buttons (drawn as the mock's buttons: blue main, white stop, 1 px frame) and the summon each starts
local SUM_BTNS = { "come", "pick", "fwd", "rev", "again", "finish", "cancel", "go" }
local SUM_ID = { come = "come", target = "pick" } -- a running summon's button (dumb: fwd / rev by dir)
local GRID = { "flash", "horn", "frunk", "trunk", "tonneau", "powershare" }
-- a control cell only for cars whose Specs entry (Core.lua T.Specs) has this field; the page shows self.cells (read)
local GRID_NEED = { tonneau = "tonneau", powershare = "powershare" }
local GRID_ICON = { flash = "i_headlight", horn = "i_horn", frunk = "i_frunk", trunk = "i_trunk", tonneau = "i_tonneau",
    powershare = "i_powershare" }
local LIDS = { "frunk", "trunk", "tonneau" } -- the tonneau has no quick button on the home page
local HEAD = { "close", "back" } -- header buttons (never scroll)
local MAIN = { "map", "charge" } -- the blue main actions

local function txt(key, ...) return getText(P .. key, ...) end

-- the longest head of `s` that fits `maxW` in `font`, with "..." when cut. Kahlua strings index UTF-16 units, so sub
-- never splits a CJK character in game.
local function fitText(s, maxW, font)
    font = font or UIFont.Small
    local tm = getTextManager()
    if tm:MeasureStringX(font, s) <= maxW then return s end
    local n = #s
    while n > 1 and tm:MeasureStringX(font, s:sub(1, n) .. "...") > maxW do n = n - 1 end
    return s:sub(1, n) .. "..."
end
-- `s` in up to n lines of `maxW`: each cut at the last space that fits (CJK: at the last character that fits), the
-- last line ends in "..." if still too long. Returns the lines (layout time only, never per frame).
local function wrapN(s, maxW, n)
    local tm, lines = getTextManager(), {}
    while #lines < n - 1 and tm:MeasureStringX(UIFont.Small, s) > maxW do
        local k = #s
        while k > 1 and tm:MeasureStringX(UIFont.Small, s:sub(1, k)) > maxW do k = k - 1 end
        local sp = k
        while sp > k / 2 and s:sub(sp, sp) ~= " " do sp = sp - 1 end
        if s:sub(sp, sp) == " " then k = sp end
        lines[#lines + 1] = s:sub(1, k)
        s = s:sub(k + 1):gsub("^%s+", "")
    end
    lines[#lines + 1] = fitText(s, maxW)
    return lines
end
-- a toast's text in up to two lines
local function wrap2(s, maxW)
    local l = wrapN(s, maxW, 2)
    return l[1], l[2]
end

-- the car picture in its paint: scripts/blender/skf/convert.py appcar (480x240, references/models.md), file
-- <spec.appCar><paint name>.png (the Model 3 shares six paint names with the Model Y, so its files carry the model)
local carTex = {}
local function carTexture(file)
    local t = carTex[file]
    if not t then
        t = getTexture("media/textures/MinidoracatTesla/HUD/" .. file .. ".png")
        carTex[file] = t
    end
    return t
end
-- colors[skin + 1] of the car's spec (Core.lua: entry i = script skin i-1) and the spec; no skin yet (a record from
-- before the field) or an unknown index: the first paint. A car that is not a Tesla script (nil, a removed model): nil,
-- never another car's paint.
function App.paint(car, skin)
    local spec = car and T.Specs["Base." .. car]
    if not spec then return nil end
    local colors = spec.colors
    return (type(skin) == "number" and colors[skin + 1]) or colors[1], spec
end
-- the official paint names stay as Tesla writes them ("Stealth Grey"), in every language
local function paintLabel(paint) return (paint.name:gsub("(%l)(%u)", "%1 %2")) end
-- "Model Y · Pearl White": the car model (the phone key's mirror, else the app's last view) and, once the app has
-- seen the car, its paint. KeysUI's "Remove from phone" entries use it too.
function App.carLabel(keyId, car)
    local st = keyId and App.seen[keyId]
    car = car or (st and st.car)
    local name = car and getText("IGUI_VehicleName" .. car) or txt("Title")
    local paint = st and st.skin and App.paint(car, st.skin)
    if not paint then return name end
    return name .. getText("IGUI_MinidoracatTesla_Sep") .. paintLabel(paint)
end
-- this car's version of a text key: the Model 3's trunk lid is not a liftgate (Core.lua T.CarPartNames)
local function carKey(script, key) return script and T.partNameKey(script, key) or key end

-- The cars this player's app can show, in order: every car of the phone keys on the player (pairing order), then
-- VehicleManager's Teslas for this player no phone here opens (MinidoracatTesla.VMLink.cars: { oid, keyId, name,
-- script, x, y, z, ageMs }). Entries: { key = keyId, car, oid } or { oid, vm = row, car }. Built on demand only.
function App.cars(playerNum, p)
    local out, byKey = {}, {}
    local list = p:getInventory():getAllTypeRecurse(K.PHONE_KEY)
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        local models = item:hasModData() and item:getModData()[K.PAIRED_CARS]
        for j, id in ipairs(K.pairedIds(item)) do
            if not byKey[id] then
                local e = { key = id, car = type(models) == "table" and models[j] or nil }
                out[#out + 1], byKey[id] = e, e
            end
        end
    end
    local VML = T.VMLink
    local rows = VML and VML.cars and VML.cars(playerNum) or {}
    for _, r in ipairs(rows) do
        local e = r.keyId and byKey[r.keyId]
        if e then e.oid = e.oid or r.oid
        elseif r.oid then out[#out + 1] = { oid = r.oid, vm = r, car = (tostring(r.script):gsub("^Base%.", "")) } end
    end
    return out
end
-- a VehicleManager-only car as the app shows it: its last position, no battery (the server says nothing about it)
local function vmState(e)
    local r = e.vm
    return { car = e.car, vm = true, x = r.x and math.floor(r.x), y = r.y and math.floor(r.y),
        ageH = (r.ageMs or 0) / 3600000 }
end

function App:new(playerNum)
    local o = ISPanelJoypad.new(self, 0, 0, W, 400)
    o.playerNum = playerNum
    o.background = false
    o.anchorLeft, o.anchorTop = false, false
    o.moveWithMouse = true -- drag it by any spot off its buttons and map (ISPanelJoypad.lua:786-816; App:onMouseUp)
    o.page = "home"
    o.scroll, o.scrollMax, o.dy = 0, 0, 0
    o.L, o.n = {}, 0
    o.rowEm, o.rowSub = {}, {}
    -- AutoDrive's canSummon options, reused every read (build-1027 §3: mode, and the picked spot's x, y)
    o.optCome, o.optDumb, o.optPin = { mode = "come" }, { mode = "dumb", dir = 1 }, { mode = "target" }
    return o
end

local function makeButton(self, id, act)
    local b = ISButton:new(0, 0, 40, 40, "", self, App.onButton)
    b:initialise()
    b:instantiate()
    -- a bare hit area: the app draws every button (ISButton's own disabled look is an opaque box, ISButton.lua:416-438)
    b.displayBackground = false
    b.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    b.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0 }
    b.borderColor = { r = 1, g = 1, b = 1, a = 0 }
    b.id, b.act, b.enable, b.lit = id, act, true, true
    self:addChild(b)
    self.b[id] = b
    self.buttons[#self.buttons + 1] = b
    return b
end
function App:createChildren()
    self.b, self.buttons = {}, {}
    for _, id in ipairs(BTN_ORDER) do makeButton(self, id, BTN[id][2]) end
end
-- the car list's i-th row (made the first time a list has that many cars)
function App:pickButton(i)
    return self.b["pick" .. i] or makeButton(self, "pick" .. i, nil)
end

-- where this player last dropped the phone, relative to their part of the screen: a client file per split-screen
-- player (Zomboid/Lua), kept across games and characters. Not the character's modData: in MP the server saves its
-- own copy of the player (GameServer.java:3040, NetworkPlayerManager.java:27), which a client-side write never reaches.
local function posFile(pn) return "MinidoracatTesla_phone" .. tostring(pn) .. ".txt" end
local function readPos(pn)
    local r = getFileReader(posFile(pn), false)
    if not r then return nil end
    local line = r:readLine()
    r:close()
    local x, y = tostring(line or ""):match("^(%-?%d+) (%-?%d+)")
    return x and { x = tonumber(x), y = tonumber(y) } or nil
end
local function writePos(pn, pos)
    local w = getFileWriter(posFile(pn), true, false)
    if not w then return end
    w:write(pos.x .. " " .. pos.y)
    w:close()
end

-- ---------------------------------------------------------------- open / close
-- opts.keyId / opts.oid: the car to show (VehicleManager's menu passes either); none or unknown: the first car.
-- Needs a phone key on the player. Returns the app, or nil.
function App.open(playerNum, opts)
    local p = getSpecificPlayer(playerNum)
    if not p or not p:getInventory():containsTypeRecurse(K.PHONE_KEY) then return nil end
    opts = type(opts) == "table" and opts or {}
    local cars = App.cars(playerNum, p)
    local pick = cars[1]
    for _, e in ipairs(cars) do
        local kid = e.key or (e.vm and e.vm.keyId)
        if (opts.keyId ~= nil and kid == opts.keyId) or (opts.oid ~= nil and e.oid == opts.oid) then pick = e; break end
    end
    if not pick then return nil end
    local a = apps[playerNum]
    if not a then
        a = App:new(playerNum)
        a:initialise()
        a:instantiate()
        apps[playerNum] = a
        a.pos = readPos(playerNum)
    end
    a.player, a.active, a.toast, a.scroll, a.listQ = p, true, nil, 0, nil
    a:select(pick)
    a.page = opts.page or "home"
    a:read()
    a:layout()
    if not a.inUI then a:addToUIManager(); a.inUI = true end
    a:setVisible(true)
    a:bringToTop()
    if JoypadState.players[playerNum + 1] then setJoypadFocus(playerNum, a) end -- JoyPadSetup.lua:546
    T.log("app open key=" .. tostring(a.key) .. " oid=" .. tostring(a.oid))
    return a
end
function App.get(playerNum) return apps[playerNum or 0] end

-- show car `e` (an App.cars entry): its last view at once, then the server's (keyed cars are polled right away)
function App:select(e)
    local same = e.key ~= nil and e.key == self.key
    self.key, self.oid, self.vmEntry = e.key, e.oid, e.vm and e or nil
    self.carHint = e.car -- the phone key's mirror (or VehicleManager's script): the model before the server's record
    if not same then -- another car: forget the old one's state
        self.st = e.key and App.seen[e.key] or (e.vm and vmState(e)) or nil
        self.stAt = getTimestampMs()
        self.alerts, self.alertsWhy, self.distKey = nil, nil, nil
        self.sum, self.pin = nil, nil -- the summon view and the picked spot belong to the old car
        self.stLive, self.sumEndAt = false, nil -- the state above is the client's last copy, not the server's word
    end
    self.nextPoll, self.sig = 0, nil
    if self.key then self:send("appAlerts", {}) end -- the home list's alert count; the security page asks again
end

function App:close()
    local jf = self.joyfocus
    if jf then
        if JoypadState.players[self.playerNum + 1] then setJoypadFocus(self.playerNum, nil) end
        if self.joyfocus then self:onLoseJoypadFocus(jf) end -- focus off even without a pad in the slot
    end
    self.joyfocus = nil
    self:setFocus(nil)
    if self.inUI then self:removeFromUIManager(); self.inUI = false end
    self.key, self.oid, self.vmEntry, self.active, self.listQ = nil, nil, nil, false, nil
    self.moving, self.dragFrom = false, nil -- closed mid-drag (the phone left the inventory): no mouse-up comes
end

function App:onMouseDown(x, y)
    self.dragFrom = { self.x, self.y }
    return ISPanelJoypad.onMouseDown(self, x, y)
end
-- the drop: remembered only when it moved (a click on the background is not a drag), kept on screen by layout
local function dropped(self)
    local from = self.dragFrom
    self.dragFrom = nil
    if not from or (from[1] == self.x and from[2] == self.y) then return end
    local pn = self.playerNum
    self.pos = { x = math.floor(self.x - getPlayerScreenLeft(pn)), y = math.floor(self.y - getPlayerScreenTop(pn)) }
    writePos(pn, self.pos)
    self:layout()
end
function App:onMouseUp(x, y)
    ISPanelJoypad.onMouseUp(self, x, y)
    dropped(self)
end
function App:onMouseUpOutside(x, y)
    ISPanelJoypad.onMouseUpOutside(self, x, y)
    dropped(self)
end

function App:setPage(page)
    local from = self.page
    self.page, self.scroll, self.sig = page, 0, nil
    if page == "security" and self.key then self:send("appAlerts", {}) end
    if page == "cars" then self:openList() end
    self:read()
    self:layout()
    -- joypad: back home lands on the row it came from, a sub page starts on its first control (the list: this car)
    if self.joyfocus then
        self:focusFirst(((page == "home" or page == "summon") and from) or (page == "cars" and self.curPick) or nil)
    end
end

-- the car list: built when it opens; appStatusAll for the other paired cars (their grey lines; the selected car is
-- polled anyway), App.BATCH keys a request and one request per LIST_MS (App:update sends the rest of the round), so
-- any number of paired cars, however often the list opens, stays inside the server's appStatusAll budget
-- (Commands.lua CommandRate). Opening it again while a round is still going out starts no second one: it only adds
-- the cars that round does not have yet (another phone picked up, a car added).
function App:openList()
    local cars = App.cars(self.playerNum, self.player)
    self.carList = cars
    if not self.listQ then self.listQ, self.listI, self.listHas = {}, 1, {} end
    local q, has = self.listQ, self.listHas
    for _, e in ipairs(cars) do
        if e.key and e.key ~= self.key and not has[e.key] then q[#q + 1], has[e.key] = e.key, true end
    end
    if self.listI > #q then self.listQ = nil end -- nothing (left) to ask
    self:sendList()
end
App.BATCH = 16 -- = Remote.lua R.MAX_BATCH (the server answers that many per request)
App.LIST_MS = 1000
function App:sendList()
    local q, now, at = self.listQ, getTimestampMs(), self.listAt or 0
    if not q or (now >= at and now < at + App.LIST_MS) then return end -- now < at: the clock was set back, go on
    local i, keys = self.listI, {}
    for k = i, math.min(#q, i + App.BATCH - 1) do keys[#keys + 1] = q[k] end
    self.listI, self.listAt = i + #keys, now
    if self.listI > #q then self.listQ = nil end
    App.stats.batches = App.stats.batches + 1
    T.request(self.player, "appStatusAll", { keys = keys })
end

-- this page's joypad rows: NAV, except the car list's (built per app by layout)
function App:navRows() return self.page == "cars" and self.navCars or NAV[self.page] end

-- ---------------------------------------------------------------- joypad: own rows (NAV), not ISPanelJoypad's grid
-- the focused control stays in view (layout scrolls to it) until the player scrolls the page by hand
function App:setFocus(b)
    if self.focusB then self.focusB.joypadFocused = false end
    self.focusB, self.freeScroll = b, false
    if not b then return end
    b.joypadFocused = true
    if b.cy >= self.yBody and self.scrollMax > 0 then self:layout() end
end
function App:focusAt(row, col)
    self.fRow, self.fCol = row, col
    self:setFocus(self.b[self:navRows()[row][col]])
end
function App:focusFirst(id)
    local rows = self:navRows()
    for r, row in ipairs(rows) do
        for c, bid in ipairs(row) do
            if bid == id and self.b[bid] and self.b[bid].shown then return self:focusAt(r, c) end
        end
    end
    for i = 2, #rows + 1 do -- the first control under the header, else the header's close / back
        local r = i <= #rows and i or 1
        for c, bid in ipairs(rows[r]) do
            if self.b[bid] and self.b[bid].shown then return self:focusAt(r, c) end
        end
    end
end
-- up / down: the nearest shown button (by centre x) on the next row that has one; past the last one the page scrolls
-- (the Security page's alerts have no buttons). Left / right: along the row.
function App:move(dr, dc)
    local rows, r, c = self:navRows(), self.fRow or 1, self.fCol or 1
    if not self.focusB then return self:focusFirst() end
    if self.focusB == self.b.spot then return self:nudgePin(dc, dr) end -- the map: the D-pad moves the pin
    if dr ~= 0 then
        local cx = self.focusB.cx + self.focusB.cw / 2
        local i = r + dr
        while rows[i] do
            local best, bd
            for j, bid in ipairs(rows[i]) do
                local b = self.b[bid]
                local d = b and b.shown and math.abs(b.cx + b.cw / 2 - cx)
                if d and (not bd or d < bd) then best, bd = j, d end
            end
            if best then return self:focusAt(i, best) end
            i = i + dr
        end
        if self.scrollMax > 0 then self:onMouseWheel(dr) end
        return
    end
    local row, j = rows[r], c + dc
    while row and row[j] do
        if self.b[row[j]] and self.b[row[j]].shown then return self:focusAt(r, j) end
        j = j + dc
    end
end
function App:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self:focusFirst()
end
function App:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self:setFocus(nil)
end
function App:onJoypadDirUp() self:move(-1, 0) end
function App:onJoypadDirDown() self:move(1, 0) end
function App:onJoypadDirLeft() self:move(0, -1) end
function App:onJoypadDirRight() self:move(0, 1) end
function App:onJoypadDown(button)
    if button == Joypad.AButton then
        local b = self.focusB
        if b and b.shown then b:forceClick() end -- the click sound; nothing when disabled (ISButton.lua forceClick)
    elseif button == Joypad.BButton then
        if self.page == "home" then self:close() else self:setPage(self:upPage()) end
    end
end

function App:onMouseWheel(del)
    if self.scrollMax <= 0 then return false end
    self.scroll = self.scroll + del * math.floor(40 * self.S)
    self.freeScroll = true
    self:layout()
    return true
end

-- ---------------------------------------------------------------- actions (the server checks everything)
function App:send(cmd, args)
    args.key = self.key
    T.request(self.player, cmd, args)
end

function App:onButton(b)
    local id = b.id
    if id == "close" then return self:close() end
    if id == "back" then return self:setPage(self:upPage()) end
    if BTN[id] and (BTN[id][1] == "summon" or BTN[id][1] == "pick") then return self:onSummon(id) end
    if TITLE[id] then return self:setPage(id) end
    if id == "map" then return self:onMap() end
    if id == "navcar" then return self:onNavCar() end
    if b.pick then -- a car list row: show that car
        self:select(b.pick)
        return self:setPage("home")
    end
    if b.hint then return self:showToast(txt("JoinHint"), false) end -- not paired with this phone: how to add it
    local st, act, on = self.st or {}, b.act, nil
    if act == "lock" then act = st.locked and "unlock" or "lock"
    elseif act == "sentry" then on = not st.sentry
    elseif act == "frunk" or act == "trunk" or act == "tonneau" then on = not st[act]
    elseif act == "charge" then on = st.chg == "stopped"
    elseif act == "powershare" then on = st.ps == "off"
    elseif act == "outlet" then on = st.outlet ~= true
    elseif act == "psFloor" then -- a 5 % step; the server rounds and clamps it again (Powershare.lua PS.set)
        local f = (st.psFloor or T.PS_FLOOR) + (id == "floorUp" and 5 or -5)
        App.stats.sent = App.stats.sent + 1
        return self:send("appAction", { act = act, pct = math.max(T.PS_FLOOR_MIN, math.min(T.PS_FLOOR_MAX, f)) })
    end
    App.stats.sent = App.stats.sent + 1
    self:send("appAction", { act = act, on = on })
end

-- "Show on map": vanilla world map centred on the car (ISWorldMap.lua:1500), marker drawn by App.drawMapCar
function App:onMap()
    local st = self.st
    if not (st and st.x) or not ISWorldMap.IsAllowed() then return end
    App.mapCar = { x = st.x + 0.5, y = st.y + 0.5, name = self.sName, dist = self.sDist, pn = self.playerNum,
        key = self.key, oid = self.oid, spr = self.carSpr }
    self:close()
    ISWorldMap.ShowWorldMap(App.mapCar.pn, App.mapCar.x, App.mapCar.y, 18)
end

-- "Navigate to car": the MiniMap's route to the car's last known square (setNavTarget, navApiVersion 12). It answers
-- true, "ok" (navigating), true, "prompted" (it asks first: the player has a trip with stops), or false, reason.
function App.navApi()
    local api = MinidoracatMiniMapAPI
    if api and type(api.navApiVersion) == "number" and api.navApiVersion >= App.NAV_API
        and type(api.setNavTarget) == "function" then return api end
    return nil
end
function App:onNavCar()
    local api, st = App.navApi(), self.st
    if not (api and st and st.x) then return end
    local ok, why = api.setNavTarget(self.playerNum, st.x + 0.5, st.y + 0.5, self.sName)
    T.log("app navigate to key=" .. tostring(self.key) .. " " .. tostring(ok) .. " " .. tostring(why))
    if ok and why == "prompted" then return self:showToast(txt("NavPrompted"), true) end
    if ok then return self:showToast(txt("NavSet", self.sName), true) end
    local NAV_WHY = { nearby = "NavNearby", notstopped = "NavStopFirst" }
    self:showToast(txt(NAV_WHY[why] or "NavFailed"), false)
end

function App:showToast(text, ok)
    local S = self.S or 1
    local l1, l2 = wrap2(text, self.width - 2 * math.floor(PAD * S) - math.floor(26 * S))
    self.toast = { text = text, l1 = l1, l2 = l2, ok = ok, untilMs = getTimestampMs() + App.TOAST_MS }
    self.sig = nil
end

-- ---------------------------------------------------------------- server -> client
local function each(key, fn)
    local hit = false
    for _, a in pairs(apps) do
        if a.key ~= nil and a.key == key then fn(a); hit = true end
    end
    return hit
end

-- the app's last view of a car (the list's grey lines, the MiniMap marker): seenRev moves only when the place, the
-- car or its paint changes, so the marker table is not rebuilt every 2 s poll
local function remember(st)
    local key = st.key
    if type(key) ~= "number" then return end
    local old = App.seen[key]
    if st.deny then -- refused (VehicleManager): keep why, forget the place (the list shows the reason, no marker)
        if not (old and old.deny) then App.seenRev = App.seenRev + 1 end
        App.seen[key] = { key = key, deny = st.deny, seenAt = getTimestampMs() }
        return
    end
    st.seenAt = getTimestampMs()
    if not (old and old.x == st.x and old.y == st.y and old.car == st.car and old.skin == st.skin) then
        App.seenRev = App.seenRev + 1
    elseif old.seenAt and st.seenAt - old.seenAt > App.FRESH_MS then
        App.seenRev = App.seenRev + 1 -- faded marker comes back
    end
    App.seen[key] = st
end
App.FRESH_MS = 10 * 60 * 1000 -- the MiniMap marker fades when the app's last look is older (user 2026-10-27)

T.ClientCommands.appState = function(args)
    remember(args)
    each(args.key, function(a)
        App.stats.states = App.stats.states + 1
        a.st = args
        a.stAt = getTimestampMs()
        a.stLive, a.stSeq = true, (a.stSeq or 0) + 1 -- the summon view trusts only these (App:summonRead)
    end)
end

-- the car list's batch (appStatusAll): the other paired cars' last view; an open list redraws its grey lines
T.ClientCommands.appStates = function(args)
    local list = type(args.list) == "table" and args.list or {}
    for _, st in ipairs(list) do remember(st) end
    for _, a in pairs(apps) do
        if a.active and a.page == "cars" then a.sig = nil end
    end
end

-- act "summonEnd" (Remote.lua R.summonEnded): why is AutoDrive's stop code, ARRIVED the good one
T.ClientCommands.appDone = function(args)
    local text, ok
    local ended = args.act == "summonEnd"
    local seen = args.key ~= nil and App.seen[args.key]
    local script = seen and seen.car and "Base." .. seen.car -- lid texts name this car's lid (carKey)
    if ended then
        text, ok = App.summonText(args.why), args.why == "ARRIVED"
    elseif args.why then
        text, ok = T.denyText(args.why), false
    else
        text, ok = getText(carKey(script, "IGUI_MinidoracatTesla_App_Done_" .. tostring(args.act))), true
    end
    local shown = args.key ~= nil and each(args.key, function(a)
        if ended then a:summonEnded(args.why)
        elseif args.act == "summon" then a:summonDone(args) end
        if not args.why and args.on ~= nil then -- what the server did (a lid toggles what is there now)
            text = getText(carKey(script, "IGUI_MinidoracatTesla_App_Done_" .. args.act .. (args.on and "_on" or "_off")))
        end
        a:showToast(text, ok)
    end)
    App.lastDone = args
    T.log("app done " .. tostring(args.act) .. " " .. tostring(args.why or "ok"))
    if not shown then -- no app open (or not a holder): say it over the player's head
        local p = getSpecificPlayer(0)
        if p then
            if ok then HaloTextHelper.addGoodText(p, text) else HaloTextHelper.addBadText(p, text) end
        end
    end
end

T.ClientCommands.appAlerts = function(args)
    each(args.key, function(a)
        local rows = {}
        local list = type(args.list) == "table" and args.list or {}
        local card = T.ParkUI and T.ParkUI.card
        for i = #list, 1, -1 do -- newest first
            local c = card and card(list[i])
            if c then rows[#rows + 1] = { title = c.title, detail = c.detail or "", time = c.time or "", icon = c.icon } end
        end
        a.alerts = rows
        a.alertsWhy = args.deny and T.denyText(args.deny) -- VehicleManager said no: say why instead of "no alerts"
        a.sig = nil
        if a.S then a:read(); a:layout() end -- render reads each row's place: lay them out before the next frame
    end)
end

-- ---------------------------------------------------------------- reading
local function ageText(hours)
    local mins = math.floor(math.max(0, hours) * 60)
    if mins < 2 then return txt("AgeNow") end
    if mins < 60 then return txt("MinsAgo", tostring(mins)) end
    if mins < 48 * 60 then return txt("HoursAgo", tostring(math.floor(mins / 60))) end
    return txt("DaysAgo", tostring(math.floor(mins / 1440)))
end

local function distText(d)
    if d < 1000 then return txt("Meters", tostring(math.floor(d + 0.5))) end
    local t = math.floor(d / 100 + 0.5)
    return txt("Km", tostring(math.floor(t / 10)) .. "." .. tostring(t % 10))
end

-- lit: drawn as usable. A car this phone is not paired with keeps its remote buttons pressable but dim (hint).
local function enable(b, on, isOn, icon, tip)
    b:setEnable(on == true)
    b.borderColor.a = 0
    b.on, b.icon, b.tipKey, b.lit, b.hint = isOn == true, icon, tip, on == true, nil
end

-- ---------------------------------------------------------------- summon (AutoDrive's unmanned mode)
-- AutoDrive's summon API in this game (build-1027 §3), or nil: no Summon row, no summon pages
function App.summonApi()
    local api = MinidoracatAutoDriveAPI
    if type(api) == "table" and (tonumber(api.summonApiVersion) or 0) >= App.SUMMON_API
        and type(api.canSummon) == "function" and type(api.summonState) == "function"
        and type(api.summonReach) == "function" then return api end
    return nil
end
-- a stop code's words: AutoDrive's summonReasonText, else the code
function App.summonText(code)
    local api = App.summonApi()
    local f = api and api.summonReasonText
    local s = type(f) == "function" and f(code) or nil
    return type(s) == "string" and s or tostring(code)
end
-- B / back: the pick page goes back to the summon page, Powershare to the controls, every other page home
function App:upPage()
    if self.page == "pick" then return "summon" end
    return self.page == "powershare" and "controls" or "home"
end

-- this car in the player's game (the server sends its vehicle id over a live link), or nil while not loaded here
function App:summonCar()
    local id = self.st and self.st.link and self.st.vid
    local v = id and getVehicleById(id)
    if v and v:getKeyId() == self.key then return v end
    return nil
end

-- self.sum: this app's summon of its car { phase = "starting" | "driving" | "arrived" | "stopped", mode, x, y, dir,
-- code (AutoDrive's stop code) or why (refused before it started: a Tesla code or a translation key) }; nil = ready
local SUM_START = { come = { mode = "come" }, fwd = { mode = "dumb", dir = 1 }, rev = { mode = "dumb", dir = -1 } }
local function running(sum) return sum ~= nil and (sum.phase == "starting" or sum.phase == "driving") end
function App:onSummon(id)
    local sum = self.sum
    if id == "cancel" then return self:setPage("summon") end
    if id == "finish" then
        self.sum = nil
    elseif id == "go" then
        if running(sum) or not self.pin then return end
        self:summonSend(true, { mode = "target", x = self.pin.x, y = self.pin.y })
        return self:setPage("summon")
    elseif running(sum) then -- the running summon's button reads "Stop" (the others are hidden)
        self:summonSend(false)
    elseif id == "pick" then
        return self:setPage("pick")
    elseif id == "again" then -- an adopted summon (sum.adopted) has no button for this: its x, y or dir are unknown
        self:summonSend(true, sum)
    else
        self:summonSend(true, SUM_START[id])
    end
    self.sumNext, self.sig = 0, nil
end
-- the last summon this game asked for, by keyId: an app opened while it runs takes its x, y and dir from here (the
-- server's state says only the mode). ponytail: one table for all split-screen players, like App.seen.
App.sumReq = {}
function App:summonSend(on, m)
    App.stats.sent = App.stats.sent + 1
    if not on then
        self.sum.stopAsked = true -- a refusal of the stop leaves the summon as it is
        return self:send("appAction", { act = "summon", on = false })
    end
    self:send("appAction", { act = "summon", on = true, mode = m.mode, x = m.x, y = m.y, dir = m.dir })
    self.sum = { phase = "starting", mode = m.mode, x = m.x, y = m.y, dir = m.dir }
    App.sumReq[self.key] = { mode = m.mode, x = m.x, y = m.y, dir = m.dir }
end
-- the server's answer to a press (appDone act = "summon"): on its way (the states after this one show it), refused,
-- or stopped (on = false). A refused stop leaves the summon as it is, unless the server no longer has the car.
function App:summonDone(args)
    local sum = self.sum
    if args.why then
        if sum and sum.stopAsked and args.why ~= "NOT_LOADED" then
            sum.stopAsked = nil -- the toast says why
        else
            sum = sum or { adopted = true } -- (a refusal for a start this app no longer knows: no Try again)
            sum.phase, sum.why, sum.code, sum.stopAsked = "stopped", args.why, nil, nil
            self.sum, self.sumEndAt = sum, getTimestampMs()
        end
    elseif args.on == false then
        self.sum, self.sumEndAt = nil, getTimestampMs()
    elseif sum and running(sum) then
        sum.seq = self.stSeq or 0 -- the server took it: a later state without the summon means it ended unheard
    end
    self.sumNext, self.sig = 0, nil
end
-- the summon ended (appDone act = "summonEnd", or AutoDrive's summonState "ended" if that came first): a pressed stop
-- goes back to ready, anything else is shown with its code until "Done" / "Try again" (not for a summon this app knows
-- nothing of: reopened, the end came before any state)
function App:summonEnded(code)
    self.sumEndAt = getTimestampMs()
    if code == "CANCELLED" then
        self.sum = nil
    else
        local sum = self.sum or { adopted = true }
        sum.phase, sum.code, sum.why, sum.stopAsked = code == "ARRIVED" and "arrived" or "stopped", code, nil, nil
        self.sum = sum
    end
    self.sumNext, self.sig = 0, nil
end

-- the picked spot: the middle of a ground square (AutoDrive's target is at z = 0)
function App:setPin(x, y)
    self.pin = self.pin or {}
    self.pin.x, self.pin.y = math.floor(x) + 0.5, math.floor(y) + 0.5
    self.sumNext, self.sig = 0, nil
end
-- joypad on the map: the D-pad moves the pin 2 tiles (the first press starts at the player)
function App:nudgePin(dx, dy)
    local pin = self.pin
    local x, y = pin and pin.x or self.player:getX(), pin and pin.y or self.player:getY()
    self:setPin(x + 2 * dx, y + 2 * dy)
end

-- The summon view, every App.SUMMON_MS while the home, summon or pick page shows (sooner after a press or an answer):
-- the phase, the texts, which buttons work. Phases come from this app's presses and the server's answers; AutoDrive's
-- summonState says when the car is on its way (its "starting" is server-side only) and how far it is; the server's
-- state (st.summon) shows a summon this app did not see start (reopened) or someone else's.
function App:summonRead(api)
    local p, st, pn, sep = self.player, self.st, self.playerNum, getText("IGUI_MinidoracatTesla_Sep")
    local v = self:summonCar()
    local ss = api.summonState(pn) -- this player's own summon, whatever car
    local sum0 = self.sum
    if not v and ss and ss.vid and (ss.phase ~= "ended" or sum0 and (running(sum0) or sum0.code ~= nil)) then
        -- AutoDrive's word that this player is summoning a loaded car with this key: shows the summon and its Stop
        -- with no link (past Bluetooth with the grid down, TRACK taken back; the server takes the stop), and where it
        -- ended until Done. Not for an old result (AutoDrive keeps it all session) nor a refused start (no code): a
        -- live place is for a link or this app's summon only.
        local car = getVehicleById(ss.vid)
        if car and car:getKeyId() == self.key then v = car end
    end
    local vid = v and v:getId() or nil -- only a car with this key (vehicle ids are reused)
    local mine = ss and vid and ss.vid == vid
    -- only a state the server sent since the app opened (stLive): App.seen's copy can be a summon long over
    local srv = self.stLive and st.link and st.summon or nil
    local sum = self.sum
    -- (AutoDrive's word only before this app saw any summon end: its "driving" lags a stop just pressed)
    if not sum and ((srv and srv.mine and (self.stAt or 0) > (self.sumEndAt or 0))
        or (mine and ss.phase == "driving" and not self.sumEndAt)) then
        -- running when the app opened: x, y, dir from this game's last request for the car, else none (no retry)
        local mode, req = srv and srv.mode or ss and ss.mode, App.sumReq[self.key]
        sum = { phase = "starting", mode = mode, seq = self.stSeq }
        if req and req.mode == mode then sum.x, sum.y, sum.dir = req.x, req.y, req.dir else sum.adopted = true end
        self.sum = sum
    elseif sum and running(sum) and sum.seq and self.stLive and st.link and not (st.summon and st.summon.mine)
        and self.stSeq > sum.seq then
        sum = nil -- ended while nobody heard it (the app was closed, or the summonEnd was lost): ready
        self.sum, self.sumEndAt = nil, getTimestampMs()
    end
    if mine and sum then
        if sum.phase == "starting" and (ss.phase == "driving" or ss.phase == "stopping") then
            sum.phase = "driving"
        elseif sum.phase == "driving" and ss.phase == "ended" and ss.code then
            self:summonEnded(ss.code)
            sum = self.sum
        end
    end
    local cx, cy
    if v then cx, cy = v:getX(), v:getY()
    elseif self.hasPos and not self.vmOnly then cx, cy = st.x + 0.5, st.y + 0.5 end
    self.sumCarX, self.sumCarY = cx, cy
    local R = tonumber(api.summonReach(pn)) or 0
    -- grid down: the phone talks to the car over Bluetooth only, so the ring and the spot stay within it too
    if not self.grid then R = math.min(R, K.btRange()) end
    self.sumR = R
    local d, ci = 0, 1
    if cx then d, ci = K.bearing(p:getX(), p:getY(), cx, cy) end
    local where = cx and (d < 3 and txt("Here") or txt("DirDist", txt("Dir_" .. DIRS[ci]), distText(d))) or nil
    local phase = sum and sum.phase or "ready"
    local s1, s2, note, why = nil, "", txt("SummonNote"), nil
    self.sumCome, self.sumDumb, self.pinOk, self.sPickNote = false, false, false, txt("SummonPickHint")
    if phase == "ready" then
        if not (self.rec and st.link and not self.vmOnly) then
            why = self.sSub2 or self.sSub -- can't reach the car / not on this phone / no record yet
        elseif srv and not srv.mine then
            why = getText("UI_MinidoracatAutoDrive_SummonBusy") -- someone else's summon of this car
        elseif not v then
            -- the server has it, this game has not: past what this game keeps loaded, so past summonReach (AutoDrive's
            -- canSummon skips the car checks without a car)
            why = getText("UI_MinidoracatAutoDrive_SummonTooFar")
        else
            local ok, w = api.canSummon(pn, v, self.optCome)
            self.sumCome = ok == true
            why = not self.sumCome and w and getText(w) or nil
            ok, w = api.canSummon(pn, v, self.optDumb)
            self.sumDumb = ok == true
            why = why or (not self.sumDumb and w and getText(w)) or nil
            local pin = self.pin
            if pin and self.sumCome then
                self.optPin.x, self.optPin.y = pin.x, pin.y
                ok, w = api.canSummon(pn, v, self.optPin)
                local pd, pci = K.bearing(p:getX(), p:getY(), pin.x, pin.y)
                if ok == true and pd > R then ok, w = false, "UI_MinidoracatAutoDrive_SummonTooFar" end -- past Bluetooth
                self.pinOk = ok == true
                self.sPickNote = self.pinOk and txt("SummonSpotAt", txt("DirDist", txt("Dir_" .. DIRS[pci]), distText(pd)))
                    or (w and getText(w)) or ""
            end
        end
        if not self.sumCome then self.sPickNote = why or "" end -- the pick page says why too
        s1 = where and txt("SummonCarAt", where) or self.sSub or ""
        s2 = R > 0 and txt("SummonRange", tostring(R)) or ""
        note = why or note
    elseif phase == "starting" then
        s1, s2 = txt("SummonStarting"), txt("SummonChecking")
    elseif phase == "driving" then
        s1 = sum.mode == "target" and txt("SummonToSpot") or sum.mode ~= "dumb" and txt("SummonComing")
            or sum.dir == -1 and txt("SummonRevNow") or sum.dir == 1 and txt("SummonFwdNow") or txt("Driving")
        local dist = ss and ss.vid == vid and tonumber(ss.dist) or d
        local kmh = v and math.floor(math.abs(v:getCurrentSpeedKmHour()) + 0.5) or 0
        s2 = distText(dist) .. sep .. txt("SummonKmh", tostring(kmh))
    elseif phase == "arrived" then
        s1 = txt("SummonArrived")
        s2 = where and (d < 3 and where or txt("SummonParkedAt", where)) or ""
        if v and not v:isEngineRunning() then s2 = s2 .. sep .. txt("SummonEngineOff") end
        note = nil
    elseif sum.why then -- refused before it started: the reason in full under the buttons
        s1, s2, note = txt("SummonRefused"), where and txt("SummonCarAt", where) or "", T.denyText(sum.why)
    else
        s1, s2, note = txt("SummonStopped", App.summonText(sum.code)), where and txt("SummonCarAt", where) or "", nil
    end
    self.sumPhase, self.sSumState, self.sSumSub, self.sSumNote, self.sumWhy = phase, s1, s2, note, why
    -- the running summon's button (it reads "Stop")
    self.sumRun = running(sum) and (sum.mode == "dumb" and (sum.dir == -1 and "rev" or "fwd") or SUM_ID[sum.mode] or "come") or nil
    -- the home list's row: what the car is doing, else whether it can come (and how far it is)
    if phase ~= "ready" then
        self.rowEm.summon, self.rowSub.summon = s1, ""
    else
        self.rowEm.summon = nil
        self.rowSub.summon = why or (txt("SummonReady") .. (where and (sep .. where) or ""))
    end
    return phase .. "/" .. s1 .. "/" .. s2 .. "/" .. tostring(note) .. "/" .. tostring(self.sumCome) .. tostring(self.sumDumb)
        .. tostring(self.pinOk) .. "/" .. self.sPickNote
end

-- the radar's dots (summon page): the car from the player, north up like the world map, inside the circle. Every
-- update while the page shows (numbers only).
function App:radarPlace()
    local p, r, R = self.player, self.radR, self.sumR or 0
    local cx, cy = self.sumCarX, self.sumCarY
    local v = self:summonCar()
    if v then cx, cy = v:getX(), v:getY() end
    if not (r and cx and p) then self.radCarX = nil; return end
    local dx, dy = cx - p:getX(), cy - p:getY()
    local k = R > 0 and r / R or 0
    local px, py = dx * k, dy * k
    local len = math.sqrt(px * px + py * py)
    if len > r then px, py = px * r / len, py * r / len end -- outside the range: on its edge
    self.radCarX, self.radCarY = self.radCX + px, self.radCY + py
    local pin = self.sum and self.sum.mode == "target" and self.sum.x and self.sum or nil
    if pin then
        self.radPinX, self.radPinY = self.radCX + (pin.x - p:getX()) * k, self.radCY + (pin.y - p:getY()) * k
    else
        self.radPinX = nil
    end
end

-- strings and button states only when something shown changes (10 Hz update; no allocation otherwise)
function App:read()
    local st, p = self.st, self.player
    local gt = getGameTime()
    local hh, mm = gt:getHour(), gt:getMinutes()
    local now = getTimestampMs()
    if self.toast and now >= self.toast.untilMs then self.toast, self.sig = nil, nil end
    -- position: every update (the player walks); a new tile or direction redoes the strings that show it
    if st and st.x and p then
        local d, ci, ang = K.bearing(p:getX(), p:getY(), st.x + 0.5, st.y + 0.5)
        self.arrowAngle = ang
        local dk = math.floor(d + 0.5) * 8 + ci
        if dk ~= self.distKey then
            self.distKey = dk
            if self.page == "home" or self.page == "location" then self.sig = nil end -- the pages that show it
            self.sDist = distText(d)
            self.sDir = d < 3 and txt("Here") or txt("Dir_" .. DIRS[ci])
            self.sDirDist = d < 3 and self.sDir or txt("DirDist", self.sDir, self.sDist)
        end
    end
    local alertsN = self.alerts and #self.alerts or -1
    local sig = self.page .. hh .. ":" .. mm .. "/" .. tostring(self.toast and self.toast.text) .. "/" .. alertsN .. "/"
        .. tostring(self.stAt) .. "/" .. tostring(self.alertsWhy) .. (self.page == "cars" and ("/" .. App.seenRev) or "")
    if sig == self.sig then return self:summonTick(now, false) end
    self.sig = sig
    self.sTime = string.format("%02d:%02d", hh, mm)
    local link = st and st.link
    -- status bar: the phone's network (grid up), else Bluetooth while it reaches the car, else no service
    self.grid = st ~= nil and st.grid == true
    self.sNet = self.grid and txt("Net") or (link == "bt" and txt("Bt") or txt("NoService"))
    local rec = st and st.pct ~= nil and not st.deny
    self.rec = rec
    local vmOnly = st ~= nil and st.vm == true -- VehicleManager's car, not on this phone: its last position only
    self.vmOnly = vmOnly
    local hasPos = st ~= nil and st.x ~= nil and not st.deny
    self.hasPos = hasPos
    local ageH = st and (st.ageH or (T.hours() - (st.h or 0))) or 0
    local car = st and st.car or self.carHint -- no record yet (never seen live, or denied): the mirror's model
    self.sName = car and getText("IGUI_VehicleName" .. car) or txt("Title")
    local paint, spec = App.paint(car, st and st.skin)
    self.script = spec and "Base." .. car
    self.paintName, self.model = paint and paint.name, spec and spec.model
    self.carSpr = spec and "car_" .. spec.model -- top view glyph on the summon radar and the maps
    self.carTex = paint and carTexture(spec.appCar .. paint.name)
    local grid = {} -- the controls page's cells for this car (GRID_NEED)
    for _, id in ipairs(GRID) do
        local need = GRID_NEED[id]
        if not need or (spec and spec[need]) then grid[#grid + 1] = id end
    end
    self.cells = grid
    local sep = getText("IGUI_MinidoracatTesla_Sep")
    if not st then
        self.sSub = txt("Connecting")
    elseif st.deny then
        self.sSub = T.denyText(st.deny)
    elseif vmOnly then
        self.sSub = txt("LastSeen", ageText(ageH)) -- VehicleManager's position; the line below says why no controls
    elseif not rec then
        self.sSub = txt("NoRecord")
    elseif link then
        self.sSub = (st.drive and txt("Driving") or txt("Parked")) .. sep .. (st.locked and txt("Locked") or txt("Unlocked"))
    else
        self.sSub = txt("LastSeen", ageText(ageH))
    end
    -- why the controls are grey
    self.sSub2 = vmOnly and txt("NotPaired") or (rec and not link and txt("FootOff")) or nil
    -- no km: no range limit (Gas Consumption 0, Remote.lua record); the game fonts have no ∞
    self.sBat = rec and (txt("Km", st.km and tostring(st.km) or "--") .. sep .. tostring(st.pct) .. "%") or ""
    self.pct = rec and st.pct or 0
    self.sWhen = hasPos and (link and txt("JustNow") or ageText(ageH)) or ""
    self.sTitle = TITLE[self.page] and txt(TITLE[self.page]) or ""
    -- the home list: a grey line under each title, the state that is on in white first (the mock's <em>)
    local em, sub = self.rowEm, self.rowSub
    sub.controls = getText(carKey(self.script, P .. "ControlsSub"))
    em.location, sub.location = nil, hasPos and self.sDirDist and (self.sDirDist .. sep .. self.sWhen) or ""
    local alerts = self.alertsWhy or (self.alerts and (#self.alerts > 0 and txt("AlertCount", tostring(#self.alerts)) or txt("NoAlerts")))
    if rec and st.sentry then em.security, sub.security = txt("Done_sentry_on"), alerts and (sep .. alerts) or ""
    elseif rec then em.security, sub.security = nil, txt("Done_sentry_off") .. (alerts and (sep .. alerts) or "")
    else em.security, sub.security = nil, vmOnly and txt("NotPaired") or alerts or "" end
    local chg = rec and st.chg
    self.chg = chg
    local state = chg == "charging" and txt("ChargingNow") or chg == "full" and txt("ChargeFull", tostring(st.target or 90))
        or chg == "nopower" and txt("ChargeNoPower") or chg == "stopped" and txt("ChargeStopped") or (rec and txt("NotPlugged"))
    self.sKw = chg == "charging" and st.kw and txt("Kw", tostring(st.kw)) or nil -- stopped / full: no power flows
    self.sEta = chg == "charging" and st.mins and txt("ToTarget", tostring(st.target or 90), tostring(st.mins)) or nil
    self.sChgState = state or self.sSub
    if chg == "charging" then
        em.charging, sub.charging = state, sep .. txt("Kw", tostring(st.kw or 0)) .. (self.sEta and (sep .. self.sEta) or "")
    else
        em.charging, sub.charging = nil, state or ""
    end
    -- buttons
    local b = self.b
    local live = rec and link ~= nil
    local locked = rec and st.locked == true
    enable(b.lock, live, locked, locked and "i_lockfill" or "i_unlock",
        carKey(self.script, TIP .. (locked and "Unlock" or "Lock")))
    local plugged = chg == "charging" or chg == "stopped"
    local chgTip = chg == "charging" and (TIP .. "ChargeStop") or chg and (TIP .. "ChargeStart") or (P .. "NotPlugged")
    enable(b.qcharge, live and plugged, chg == "charging", "i_bolt", chgTip)
    enable(b.charge, live, chg == "charging", nil, chgTip)
    self.sChargeBtn = chg == "charging" and txt("ChargeStop") or txt("ChargeStart")
    for _, id in ipairs(LIDS) do
        local open = rec and st[id] == true
        local tip = carKey(self.script, TIP .. id:sub(1, 1):upper() .. id:sub(2))
        if b["q" .. id] then enable(b["q" .. id], live, open, GRID_ICON[id], tip) end
        enable(b[id], live, open, GRID_ICON[id], tip)
        b[id].sub = open and txt("Opened") or txt("TapOpen")
    end
    enable(b.flash, live, false, GRID_ICON.flash, TIP .. "Flash")
    b.flash.sub = txt("FlashSub")
    enable(b.horn, live, false, GRID_ICON.horn, TIP .. "Horn")
    b.horn.sub = txt("HornSub")
    local sentry = rec and st.sentry == true
    enable(b.sentry, live, sentry, nil, TIP .. (sentry and "SentryOff" or "SentryOn"))
    -- Powershare (Cybertruck, plan 4's four states) and the bed outlet, from the record (Remote.lua R.remember)
    local ps = rec and st.ps or "off"
    local floor = rec and st.psFloor or T.PS_FLOOR
    self.ps, self.psFloor, self.psOn = ps, floor, ps ~= "off"
    if ps == "backup" then
        local h = st.psH
        local left = h and (h >= 48 and txt("PsDays", tostring(math.floor(h / 24 + 0.5))) or txt("PsHours", tostring(h)))
        self.sPsState = txt("PsBackup", tostring(st.psKw or 0))
        self.sPsSub = left and txt("PsBackupSub", left) or txt("PsBackupSub", "--")
    else
        self.sPsState = txt("Ps_" .. ps)
        self.sPsSub = ps == "armed" and txt(st.psWall and "PsArmedSub" or "PsArmedNoWall")
            or ps == "stopped" and (st.psStop == "spot" and txt("PsStoppedSpot") or txt("PsStoppedSub", tostring(floor)))
            or txt("PsOffSub")
    end
    self.sPsFloor, self.sPsPct = txt("PsFloor", tostring(floor)), txt("PsCharge", tostring(rec and st.pct or 0))
    enable(b.powershare, rec, ps == "backup", GRID_ICON.powershare, TIP .. "Powershare")
    b.powershare.sub = txt("PsCell_" .. ps)
    enable(b.psToggle, live, self.psOn, nil, TIP .. (self.psOn and "PsOff" or "PsOn"))
    self.sPsBtn = txt(self.psOn and "PsTurnOff" or "PsTurnOn")
    enable(b.floorDown, live and floor > T.PS_FLOOR_MIN, false, nil, TIP .. "PsFloorDown")
    enable(b.floorUp, live and floor < T.PS_FLOOR_MAX, false, nil, TIP .. "PsFloorUp")
    local outletOn = rec and st.outlet == true
    self.hasOutlet = spec ~= nil and spec.bedOutlet ~= nil
    enable(b.outlet, live, outletOn, nil, TIP .. (outletOn and "OutletOff" or "OutletOn"))
    self.sOutletSub = outletOn and txt(st.outletWhy and ("OutletWhy_" .. st.outletWhy) or "OutletLive") or txt("OutletOffSub")
    enable(b.map, hasPos, false, nil, TIP .. "Map")
    enable(b.navcar, hasPos, false, nil, TIP .. "NavCar")
    enable(b.close, true, false, "i_close", TIP .. "Close")
    enable(b.back, true, false, "i_back", TIP .. "Back")
    enable(b.cars, true, false, "i_chevdown", TIP .. "Cars")
    for _, id in ipairs(LIST) do enable(b[id], true, false, LIST_ICON[id], nil) end
    if vmOnly then -- dim, but a press says how to add this car to the phone
        for _, id in ipairs(REMOTE) do
            b[id]:setEnable(true)
            b[id].hint = true
        end
    end
    self:summonTick(now, true) -- after this pass: the summon view reads its record, link and reasons
    return true
end

-- the summon view on the pages that show it: AutoDrive is read every App.SUMMON_MS, or right after a full read; the
-- radar's dots every update. True when what it shows changed (a layout, not another full read).
function App:summonTick(now, force)
    local api = App.summonApi()
    self.sumApi = api ~= nil
    local pg = self.page
    if not (api and (pg == "home" or pg == "summon" or pg == "pick")) then return false end
    local changed = false
    if force or now >= (self.sumNext or 0) then
        self.sumNext = now + App.SUMMON_MS
        local ss = self:summonRead(api)
        changed = ss ~= self.sumSig
        self.sumSig = ss
    end
    if pg == "summon" then self:radarPlace() end
    return changed
end

-- every POLL_MS while open: the selected car only. A paired car asks the server; VehicleManager's car re-reads its
-- last position from VMLink (gone from its list, e.g. a share taken back: the app moves to the first car left).
function App:update()
    ISPanelJoypad.update(self)
    if not self.active then return end
    local p = self.player
    local now = getTimestampMs()
    if now >= self.nextPoll then
        self.nextPoll = now + App.POLL_MS
        -- the phone left the inventory, or the player is gone: close (nothing to poll for)
        if not p or p:isDead() or (self.key and not K.phoneKeyFor(p, self.key))
            or not p:getInventory():containsTypeRecurse(K.PHONE_KEY) then return self:close() end
        App.stats.polls = App.stats.polls + 1
        if self.key then
            self:send("appStatus", {})
        elseif self.vmEntry then
            local cars = App.cars(self.playerNum, p)
            local found = cars[1] -- gone from the list: the first car left
            for _, e in ipairs(cars) do
                if e.oid == self.oid then found = e; break end
            end
            if not found then return self:close() end
            if found.vm and found.oid == self.oid then
                self.vmEntry, self.st, self.stAt = found, vmState(found), now
            else
                self:select(found) -- now paired with a phone here, or another car
            end
        end
    end
    if self.listQ then self:sendList() end
    if self:read() then self:layout() end
end

-- a car list row's grey line: "78% · north 320 m" over a live link, "41% · last seen 2 hours ago" from the record,
-- "VehicleManager · north 320 m · 5 min ago" for its car (App.seen; layout only)
function App:carLine(e)
    local sep, p = getText("IGUI_MinidoracatTesla_Sep"), self.player
    local function where(x, y)
        if not (x and p) then return nil end
        local d, ci = K.bearing(p:getX(), p:getY(), x + 0.5, y + 0.5)
        return d < 3 and txt("Here") or txt("DirDist", txt("Dir_" .. DIRS[ci]), distText(d))
    end
    if e.vm then
        local w = where(e.vm.x and math.floor(e.vm.x), e.vm.y and math.floor(e.vm.y))
        return txt("VmTag") .. (w and (sep .. w) or "") .. sep .. ageText((e.vm.ageMs or 0) / 3600000)
    end
    local st = App.seen[e.key]
    if not st then return txt("Loading") end
    if st.deny then return T.denyText(st.deny) end
    if st.pct == nil then return txt("NoRecord") end
    local w = st.link and where(st.x, st.y)
    return tostring(st.pct) .. "%" .. sep .. (w or txt("LastSeen", ageText(T.hours() - (st.h or 0))))
end

-- ---------------------------------------------------------------- layout (design units x S; y below the header
-- is in page coordinates, drawn and placed minus self.dy)
function App:layout()
    local tm = getTextManager()
    self.tipKey = nil
    local pn = self.playerNum
    local S = math.min(tm:getFontHeight(UIFont.Small) / 19, (getPlayerScreenWidth(pn) - 8) / W)
    self.S = S
    local FH, FHM, FHL = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Large)
    self.FH, self.FHM, self.FHL = FH, FHM, FHL
    self.A = T.HUDAtlas[2] -- 2x at every S: the 24-unit icons and the wordmark stay sharp at S = 1
    self.tex = getTexture(self.A.tex)
    self.f = S / 2
    self.arrowTex = getTexture("media/textures/MinidoracatTesla/HUD/app_arrow" .. (S >= 1.5 and 2 or 1) .. "x.png")
    self.ringTex = getTexture("media/textures/MinidoracatTesla/HUD/app_ring.png") -- the summon range (build_atlas.py)
    local function u(n) return math.floor(n * S + 0.5) end
    local sw, sh = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)
    local w = math.min(math.floor(W * S), sw - 8)
    local pad = math.floor(PAD * S)
    self.pad = pad
    for _, b in ipairs(self.buttons) do b.shown = false end
    local function place(id, x, y, bw, bh)
        local b = self.b[id]
        b.shown, b.cx, b.cy, b.cw, b.ch = true, math.floor(x), math.floor(y), math.floor(bw), math.floor(bh)
        return b
    end
    local page = self.page
    local y = u(12)
    self.yBar = y
    y = y + FH + u(14)
    if page == "home" then
        local cs = u(28)
        self.yName = y
        place("close", w - pad - cs + u(6), y + math.floor((FHL - cs) / 2), cs, cs)
        -- the car name + a down chevron: the car list (the real app's vehicle switcher)
        local chev = u(22)
        self.sHead = fitText(self.sName, w - 2 * pad - cs - chev, UIFont.Large)
        local nw = tm:MeasureStringX(UIFont.Large, self.sHead)
        self.xChev = pad + nw + u(4)
        place("cars", pad - u(4), y - u(2), nw + u(8) + chev, FHL + u(4))
        y = y + FHL + u(4)
    else
        local bs = u(32)
        place("back", pad - u(8), y, bs, bs)
        self.xTitle = pad - u(8) + bs + u(4)
        self.yName = y + math.floor((bs - FHM) / 2)
        self.sHead = fitText(self.sTitle, w - pad - self.xTitle, UIFont.Medium)
        y = y + bs + u(12)
    end
    self.yBody = y
    local cw -- the car picture's width
    local tw = w - 2 * pad
    if page == "home" then
        self.yBat = y
        self.sBatFit = fitText(self.sBat, tw - u(30))
        y = y + FH + u(2)
        self.ySub, self.sSubFit = y, fitText(self.sSub, tw)
        y = y + FH
        self.sSub2Fit = self.sSub2 and fitText(self.sSub2, tw)
        if self.sSub2 then self.ySub2 = y; y = y + FH end
        cw = math.floor(w * 0.68)
        y = y + u(12)
        self.yCar = y
        y = y + math.floor(cw / 2) + u(8)
        local slot, qw, qh = tw / 4, u(48), u(40)
        for i, id in ipairs(QUICK) do place(id, pad + (i - 0.5) * slot - qw / 2, y, qw, qh) end
        y = y + qh + u(10)
        local rh = math.max(FHM + u(2) + FH, u(36)) + u(20)
        local rx = pad + u(40)
        local rw = w - rx - pad - u(22)
        for _, id in ipairs(LIST) do
            if id ~= "summon" or self.sumApi then -- no AutoDrive summon API: no Summon row
                local b = place(id, pad / 2, y, w - pad, rh) -- inset: the focus ring stays inside the phone
                b.sTitle = fitText(txt(TITLE[id]), rw, UIFont.Medium)
                local e = self.rowEm[id]
                b.sEm = e and fitText(e, rw) or nil
                b.emW = b.sEm and tm:MeasureStringX(UIFont.Small, b.sEm) or 0
                b.sSub = fitText(self.rowSub[id] or "", rw - b.emW)
                y = y + rh
            end
        end
        y = y + u(8)
        self.yLine = y
        y = y + 1 + u(16)
        local A = self.A
        local wm, trim = self.model and A["wm_" .. self.model], self.model and A["trim_" .. self.model]
        self.yWm = y
        y = y + (wm and math.floor(wm[4] * self.f) or 0) + u(8)
        self.yTrim = y
        y = y + (trim and math.floor(trim[4] * self.f) or 0) + u(6)
    elseif page == "controls" then
        cw = math.floor(w * 0.56)
        y = y + u(4)
        self.yCar = y
        y = y + math.floor(cw / 2) + u(16)
        local gap = u(12)
        local cellW = math.floor((tw - gap) / 2)
        local cellH = u(14) + u(22) + u(8) + FH + u(2) + FH + u(12)
        local grid = self.cells or GRID
        for i, id in ipairs(grid) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local b = place(id, pad + col * (cellW + gap), y + row * (cellH + gap), cellW, cellH)
            b.sTitle = fitText(getText(carKey(self.script, P .. id:sub(1, 1):upper() .. id:sub(2))), cellW - u(28))
            b.sSubFit = fitText(b.sub, cellW - u(28))
        end
        local rows = math.ceil(#grid / 2)
        y = y + rows * cellH + (rows - 1) * gap + u(16)
    elseif page == "location" then
        if self.hasPos and self.sDist then
            self.yArrow = y + u(28)
            y = y + u(56) + u(14)
            self.yDist, self.sDistFit = y, fitText(self.sDist, tw, UIFont.Large)
            y = y + FHL + u(2)
            self.yDir, self.sDirFit = y, fitText(self.sDir, tw)
            y = y + FH + u(2)
            self.yWhen, self.sWhenFit = y, fitText(txt("Location") .. getText("IGUI_MinidoracatTesla_Sep") .. self.sWhen, tw)
            y = y + FH + u(18)
        else
            self.yArrow = nil
            self.yMsg, self.sMsg = y, fitText(self.sSub, tw)
            y = y + FH + u(18)
        end
        if ISWorldMap.IsAllowed() then
            local b = place("map", pad, y, tw, u(40))
            b.sTitle = fitText(txt("Map"), tw - u(16))
            y = y + u(40) + u(14)
        end
        if App.navApi() then -- only with a MiniMap that has setNavTarget
            local b = place("navcar", pad, y, tw, u(40))
            b.sTitle = fitText(txt("NavCar"), tw - u(16))
            y = y + u(40) + u(14)
        end
    elseif page == "security" then
        local rh = math.max(FHM + u(2) + FH, u(36)) + u(20)
        local b = place("sentry", pad / 2, y, w - pad, rh)
        local rw = tw - u(52)
        b.sTitle = fitText(txt("SentryMode"), rw, UIFont.Medium)
        b.sSub = fitText(self.rec and txt(self.b.sentry.on and "Done_sentry_on" or "Done_sentry_off") or self.sSub, rw)
        y = y + rh + u(10)
        self.yAlertsHead, self.sAlertsHead = y, fitText(txt("AlertsTitle"), tw)
        y = y + FH + u(10)
        local rows = self.alerts
        local ah = 2 * FH + u(14)
        if rows and #rows > 0 then
            local ax = u(28)
            for _, r in ipairs(rows) do
                r.y = y
                r.sTime = r.time
                r.sTitle = fitText(r.title, tw - ax - tm:MeasureStringX(UIFont.Small, r.time) - u(8))
                r.sDetail = fitText(r.detail, tw - ax)
                y = y + ah
            end
        else
            self.yAlertsMsg = y
            local msg = self.alertsWhy or (self.vmOnly and txt("NotPaired")) or (rows and txt("NoAlerts")) or txt("Loading")
            self.sAlertsMsg = fitText(msg, tw)
            y = y + FH + u(10)
        end
        y = y + u(6)
    elseif page == "charging" then
        self.yState, self.sStateFit = y, fitText(self.sChgState, tw, UIFont.Large)
        y = y + FHL + u(6)
        self.yBat, self.sBatFit = y, fitText(self.sBat, tw - u(30))
        y = y + FH + u(12)
        self.yKw, self.sKwFit = self.sKw and y, self.sKw and fitText(self.sKw, tw)
        if self.sKw then y = y + FH + u(4) end
        self.yEta, self.sEtaFit = self.sEta and y, self.sEta and fitText(self.sEta, tw)
        if self.sEta then y = y + FH + u(4) end
        y = y + u(14)
        if self.chg == "charging" or self.chg == "stopped" then
            local b = place("charge", pad, y, tw, u(40))
            b.sTitle = fitText(self.sChargeBtn, tw - u(16))
            y = y + u(40) + u(14)
        end
    elseif page == "powershare" then
        -- plan 4's mock: the state (large), why, the charge bar with the discharge limit's mark, the two numbers; then
        -- the limit's -/+ (5 %), the switch, and the bed outlet's row (a toggle, like Sentry Mode)
        -- the state keeps its kW: Medium when Large cuts it (CatLang's German "Versorgt das Haus · 0.24 kW" ran past
        -- Large on a server, the kW lost: E2E tesla-ctlayout-1031f-de); render draws it in the same font
        self.psFont = tm:MeasureStringX(UIFont.Large, self.sPsState) <= tw and UIFont.Large or UIFont.Medium
        self.yPsState, self.sPsStateFit = y, fitText(self.sPsState, tw, self.psFont)
        y = y + (self.psFont == UIFont.Large and FHL or FHM) + u(4)
        self.yPsSub = y
        self.sPsSubs = wrapN(self.sPsSub, tw, 3) -- the why (stopped: the limit, no spot) runs long in some languages
        y = y + FH * #self.sPsSubs + u(14)
        self.yPsBar = y
        y = y + u(8) + u(8)
        self.yPsLbl = y
        self.sPsFloorFit, self.sPsPctFit = fitText(self.sPsFloor, math.floor(tw / 2)), fitText(self.sPsPct, math.floor(tw / 2))
        y = y + FH + u(12)
        local bw, bh = u(48), u(32)
        place("floorDown", pad, y, bw, bh).sTitle = "-"
        place("floorUp", w - pad - bw, y, bw, bh).sTitle = "+"
        self.yPsAdj, self.sPsAdj = y + math.floor((bh - FH) / 2), fitText(txt("PsFloorAdjust"), tw - 2 * bw - u(16))
        y = y + bh + u(14)
        local b = place("psToggle", pad, y, tw, u(40))
        b.sTitle = fitText(self.sPsBtn, tw - u(16))
        y = y + u(40) + u(16)
        if self.hasOutlet then
            local rw = tw - u(52)
            -- the how-to sentence: 44 characters in Japanese, 99 in German; four lines leave room for a wider
            -- multiplayer font (CatLang draws German about 1.5 times as wide as zomboidSmall)
            local subs = wrapN(self.sOutletSub, rw, 4)
            local rh = math.max(FHM + u(2) + FH * #subs, u(36)) + u(20)
            local ob = place("outlet", pad / 2, y, w - pad, rh)
            ob.sTitle = fitText(txt("Outlet"), rw, UIFont.Medium)
            ob.sSubs = subs
            y = y + rh + u(10)
        end
    elseif page == "summon" or page == "pick" then
        -- the mock's buttons: style "main" (blue), "stop" (white), "frame" (1 px line); lit = usable
        local bh, gap = u(40), u(8)
        local function sbtn(id, x, by, bw, label, style, on, tip)
            local b = place(id, x, by, bw, bh)
            b.sTitle, b.style, b.lit, b.tipKey = fitText(label, bw - u(16)), style, on == true, tip
            b:setEnable(on == true)
            b.borderColor.a = 0
        end
        local half = math.floor((tw - gap) / 2)
        local run, phase = self.sumRun, self.sumPhase or "ready"
        if page == "summon" then
            local D = math.min(tw, u(180))
            self.radR = math.floor(D / 2)
            self.radCX, self.radCY = math.floor(w / 2), y + u(4) + self.radR
            y = y + u(4) + D + u(12)
            self.ySumState, self.sSumStateFit = y, fitText(self.sSumState or "", tw, UIFont.Medium)
            y = y + FHM + u(2)
            self.ySumSub, self.sSumSubFit = y, fitText(self.sSumSub or "", tw)
            y = y + FH + u(8)
            local stop = txt("SummonStop")
            if run then -- one button: the running summon's, as "Stop"
                sbtn(run, pad, y, tw, stop, "stop", true, TIP .. "SummonStop")
                y = y + bh + gap
            elseif phase == "arrived" then
                sbtn("finish", pad, y, tw, txt("SummonDone"), "main", true, nil)
                y = y + bh + gap
            elseif phase == "stopped" then
                local sum = self.sum or { adopted = true } -- (layout between a clear and the next read)
                if not sum.adopted then -- try again: the same summon (an adopted one lacks its x, y or dir)
                    local tip = sum.mode == "target" and "SummonGo" or sum.mode == "dumb"
                        and (sum.dir == -1 and "SummonRev" or "SummonFwd") or "SummonCome"
                    sbtn("again", pad, y, tw, txt("SummonAgain"), "main", true, TIP .. tip)
                    y = y + bh + gap
                end
                sbtn("finish", pad, y, tw, txt("SummonDone"), sum.adopted and "main" or "frame", true, nil)
                y = y + bh + gap
            else
                sbtn("come", pad, y, tw, txt("SummonCome"), "main", self.sumCome, TIP .. "SummonCome")
                y = y + bh + gap
                if ISWorldMap.IsAllowed() then -- same rule as "Show on map" (sandbox Map.AllowWorldMap)
                    sbtn("pick", pad, y, tw, txt("SummonPick"), "frame", self.sumCome, TIP .. "SummonPick")
                    y = y + bh + gap
                end
                sbtn("fwd", pad, y, half, txt("SummonFwd"), "frame", self.sumDumb, TIP .. "SummonFwd")
                sbtn("rev", pad + half + gap, y, half, txt("SummonRev"), "frame", self.sumDumb, TIP .. "SummonRev")
                y = y + bh + gap
            end
            self.ySumNote = y + u(2)
            self.sSumNote1, self.sSumNote2 = nil, nil
            if self.sSumNote then self.sSumNote1, self.sSumNote2 = wrap2(self.sSumNote, tw) end
            y = y + u(2) + (self.sSumNote1 and FH * (self.sSumNote2 and 2 or 1) or 0) + u(8)
        else
            local mh = math.floor(tw * 0.8)
            self:pickMap()
            place("spot", pad, y, tw, mh)
            y = y + mh + u(8)
            self.yPickNote = y
            self.sPickNote1, self.sPickNote2 = wrap2(self.sPickNote or "", tw)
            y = y + 2 * FH + u(8)
            sbtn("cancel", pad, y, half, txt("SummonCancel"), "frame", true, nil)
            sbtn("go", pad + half + gap, y, half, txt("SummonGo"), "main", self.pinOk and not run, TIP .. "SummonGo")
            y = y + bh + u(8)
        end
    elseif page == "cars" then
        -- one row per car (App.cars order); the joypad's rows follow them
        local rows = { { "back" } } -- this app's own rows (split screen: each player's list is its own length)
        self.navCars = rows
        local rh = math.max(FHM + u(2) + FH, u(36)) + u(20)
        local rw = tw - u(30) -- room for the current car's check mark
        self.curPick = nil
        for i, e in ipairs(self.carList or {}) do
            local b = self:pickButton(i)
            place(b.id, pad / 2, y, w - pad, rh)
            b.pick = e
            b.cur = (e.key ~= nil and e.key == self.key) or (e.key == nil and e.oid == self.oid)
            if b.cur then self.curPick = b.id end
            b.sTitle = fitText(App.carLabel(e.key, e.car), rw, UIFont.Medium)
            b.sSub = fitText(self:carLine(e), rw)
            rows[#rows + 1] = { b.id }
            y = y + rh
        end
        y = y + u(10)
        self.yHint = y
        self.sHint1, self.sHint2 = wrap2(txt("AddCarHint"), tw)
        y = y + FH * (self.sHint2 and 2 or 1) + u(12)
    end
    if cw then self.carX, self.carW, self.carH = math.floor((w - cw) / 2), cw, math.floor(cw / 2) end
    -- the toast sits at the bottom, outside the scrolled part
    local toastH = self.toast and (FH * (self.toast.l2 and 2 or 1) + u(16)) or 0
    local bottom = u(12)
    local h = math.min(y + toastH + bottom, sh - 8)
    self.yBodyEnd = h - toastH - bottom
    self.yToast = self.toast and (self.yBodyEnd + u(8)) or nil
    self.scrollMax = math.max(0, y - self.yBodyEnd)
    local fb = self.focusB -- the focused control in view (a toast shortens the body, a page grows)
    if fb and fb.shown and fb.cy >= self.yBody and not self.freeScroll then
        if fb.cy - self.scroll < self.yBody then self.scroll = fb.cy - self.yBody end
        if fb.cy + fb.ch - self.scroll > self.yBodyEnd then self.scroll = fb.cy + fb.ch - self.yBodyEnd end
    end
    self.scroll = math.max(0, math.min(self.scroll, self.scrollMax))
    self.dy = self.scroll
    for _, b in ipairs(self.buttons) do
        local show = b.shown
        if show then
            local by = b.cy >= self.yBody and b.cy - self.dy or b.cy
            b:setX(b.cx); b:setY(by); b:setWidth(b.cw); b:setHeight(b.ch)
            -- only when wholly inside the visible body: the stencil clips drawing, not clicks (UIElement.java:1875-1889)
            show = b.cy < self.yBody or (by >= self.yBody and by + b.ch <= self.yBodyEnd)
        end
        b:setVisible(show)
    end
    self:setWidth(w)
    self:setHeight(h)
    -- where the player dropped it (App:onMouseUp), else the right half of this player's screen, centred vertically
    -- like a phone held up; either way inside their screen (resolution or split screen changed, a taller page).
    -- Not while being dragged: a poll's layout would snap it back.
    if not self.moving then
        local p = self.pos
        local x, y = p and p.x or (sw - w - u(40)), p and p.y or math.floor((sh - h) / 2)
        self:setX(getPlayerScreenLeft(pn) + math.max(4, math.min(sw - w - 4, x)))
        self:setY(getPlayerScreenTop(pn) + math.max(4, math.min(sh - h - 4, y)))
    end
    -- the joypad's control went away (a summon ended: its Stop is gone): the page's first control instead
    if self.joyfocus and self.focusB and not self.focusB.shown then self:focusFirst() end
end

Events.OnResolutionChange.Add(function()
    for _, a in pairs(apps) do
        if a.active then a:layout() end
    end
end)

-- ---------------------------------------------------------------- drawing
local function flush(self)
    local jo, tex, L = self.javaObject, self.tex, self.L
    for i = 1, self.n, 12 do
        jo:DrawSubTextureRGBA(tex, L[i], L[i + 1], L[i + 2], L[i + 3], L[i + 4], L[i + 5], L[i + 6], L[i + 7],
            L[i + 8], L[i + 9], L[i + 10], L[i + 11])
    end
    self.n = 0
end

-- a t-px rounded frame (no card fill: the inside is the phone's background again)
local function frame(self, x, y, w, h, r, t, c, a)
    HUD.rrect(self, x, y, w, h, r, c, a)
    HUD.rrect(self, x + t, y + t, w - 2 * t, h - 2 * t, math.max(0, r - t), C.bg, 1)
end
local function focusRing(self, b)
    local S = self.S
    local g = math.floor(3 * S)
    frame(self, b.x - g, b.y - g, b.width + 2 * g, b.height + 2 * g, 8 * S, math.max(1, math.floor(2 * S)), C.text, 1)
end
-- an 18-unit atlas icon scaled to `size` units, centred on (cx, cy)
local function icon(self, name, cx, cy, size, c, a)
    local S = self.S
    HUD.spr(self, self.A[name], cx - size * S / 2, cy - size * S / 2, c, a, size / 18)
end
local function batteryBar(self, x, y)
    local S = self.S
    local bw, bh = math.floor(22 * S), math.max(2, math.floor(9 * S))
    local by = y + math.floor((self.FH - bh) / 2)
    HUD.rrect(self, x, by, bw, bh, 2 * S, C.weak, 1)
    HUD.rrect(self, x, by, math.max(2 * S, bw * self.pct / 100), bh, 2 * S, self.pct < 20 and C.warn or C.text2, 1)
end
-- a row's on / off switch at its right end (Sentry Mode, the bed outlet)
local function switchKnob(self, b, o)
    local S, pad = self.S, self.pad
    local tw, th = math.floor(40 * S), math.floor(22 * S)
    local tx, ty = self.width - pad - tw, b.cy - o + math.floor((b.ch - th) / 2)
    local a = b.lit and 1 or 0.4
    HUD.rrect(self, tx, ty, tw, th, th / 2, b.on and C.blue or C.weak, a)
    local k = th - math.floor(4 * S)
    HUD.rrect(self, b.on and (tx + tw - k - 2 * S) or (tx + 2 * S), ty + 2 * S, k, k, k / 2, b.on and C.white or C.text2, a)
end
local PS_ADJ = { "floorDown", "floorUp" } -- the Powershare page's discharge limit -/+

function App:prerender()
    if not self.S then return end
    self.n = 0
    local S, w, A, o, pad = self.S, self.width, self.A, self.dy, self.pad
    HUD.rrect(self, 0, 0, w, self.height, 24 * S, C.bg, 0.98)
    if self.grid then -- signal bars
        local bx = w - pad - math.floor(16 * S)
        local by = self.yBar + (self.FH - 12 * S) / 2
        for i = 0, 3 do
            local hh = (4 + i * 2.7) * S
            HUD.rect(self, bx + i * 4.3 * S, by + 12 * S - hh, 3 * S, hh, C.text, 1)
        end
    end
    for _, id in ipairs(HEAD) do
        local b = self.b[id]
        if b:isVisible() then
            if b.joypadFocused then focusRing(self, b) end
            icon(self, b.icon, b.x + b.width / 2, b.y + b.height / 2, 20, id == "close" and C.text2 or C.text, 1)
        end
    end
    local nb = self.b.cars -- the home header: car name + down chevron (the car list)
    if nb:isVisible() then
        if nb.joypadFocused then focusRing(self, nb) end
        icon(self, "i_chevdown", self.xChev + 9 * S, self.yName + self.FHL / 2, 18, C.text2, 1)
    end
    flush(self)
    local clip = self.scrollMax > 0
    if clip then self:setStencilRect(0, self.yBody, w, self.yBodyEnd - self.yBody) end
    local page = self.page
    for _, b in ipairs(self.buttons) do
        if b.joypadFocused and b:isVisible() and b.cy >= self.yBody then focusRing(self, b) end
    end
    if page == "home" then
        if self.rec then batteryBar(self, pad, self.yBat - o) end
        for _, id in ipairs(QUICK) do
            local b = self.b[id]
            local c = not b.lit and C.weak or (b.on and C.text or C.text2)
            icon(self, b.icon, b.x + b.width / 2, b.y + b.height / 2, 24, c, 1)
        end
        for _, id in ipairs(LIST) do
            local b = self.b[id]
            if b.shown then
                local cy = b.cy - o + b.ch / 2
                icon(self, b.icon, pad + 10 * S, cy, 20, C.text2, 1)
                icon(self, "i_chev", w - pad - 8 * S, cy, 16, C.weak, 1)
            end
        end
        HUD.rect(self, pad, self.yLine - o, w - 2 * pad, 1, C.line, 1)
        local wm, trim = self.model and A["wm_" .. self.model], self.model and A["trim_" .. self.model]
        if wm then HUD.spr(self, wm, pad, self.yWm - o, C.text, 1) end
        if trim then HUD.spr(self, trim, pad, self.yTrim - o, C.text2, 1) end
    elseif page == "controls" then
        for _, id in ipairs(self.cells or GRID) do
            local b = self.b[id]
            local by = b.cy - o
            frame(self, b.cx, by, b.cw, b.ch, 6 * S, 1, b.on and b.lit and C.text or C.line, 1)
            icon(self, b.icon, b.cx + 14 * S + 11 * S, by + 14 * S + 11 * S, 22, b.lit and C.text or C.weak, 1)
        end
    elseif page == "security" then
        switchKnob(self, self.b.sentry, o)
    elseif page == "charging" then
        if self.rec then batteryBar(self, pad, self.yBat - o) end
    elseif page == "powershare" then
        local by, bh, tw = self.yPsBar - o, math.max(3, math.floor(8 * S)), w - 2 * pad
        HUD.rrect(self, pad, by, tw, bh, bh / 2, C.weak, 1)
        HUD.rrect(self, pad, by, math.max(bh, tw * self.pct / 100), bh, bh / 2, self.ps == "backup" and C.ok or C.text2, 1)
        local mw = math.max(2, math.floor(2 * S)) -- the discharge limit's mark
        HUD.rect(self, pad + math.floor(tw * self.psFloor / 100) - mw / 2, by - math.floor(3 * S), mw, bh + math.floor(6 * S), C.warn, 1)
        for _, id in ipairs(PS_ADJ) do
            local fb = self.b[id]
            if fb.shown then frame(self, fb.cx, fb.cy - o, fb.cw, fb.ch, 6 * S, 1, fb.lit and C.text2 or C.line, 1) end
        end
        local tb = self.b.psToggle -- off: the blue main action (mock "開啟"); on: a frame (mock "gr")
        if self.psOn then frame(self, tb.cx, tb.cy - o, tb.cw, tb.ch, 6 * S, 1, tb.lit and C.text2 or C.line, 1)
        else HUD.rrect(self, tb.cx, tb.cy - o, tb.cw, tb.ch, 6 * S, C.blue, tb.lit and 1 or 0.4) end
        if self.b.outlet.shown then switchKnob(self, self.b.outlet, o) end
    elseif page == "location" then
        local b = self.b.navcar -- the second action: a frame, not blue
        if b.shown then frame(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, 1, b.lit and C.text2 or C.line, 1) end
    elseif page == "summon" or page == "pick" then
        for _, id in ipairs(SUM_BTNS) do
            local b = self.b[id]
            if b.shown and BTN[id][1] == page then
                if b.style == "main" then HUD.rrect(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, C.blue, b.lit and 1 or 0.4)
                elseif b.style == "stop" then HUD.rrect(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, C.text, 1)
                else frame(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, 1, C.line, 1) end
            end
        end
        if page == "summon" and self.radR then
            -- the range: the ring texture (over the background, so the batch so far goes first), then the dots
            flush(self)
            local r, cx, cy = self.radR, self.radCX, self.radCY - o
            local rc = (self.sumR or 0) > 0 and C.blue or C.weak
            self:drawTextureScaled(self.ringTex, cx - r, cy - r, 2 * r, 2 * r, 1, rc[1], rc[2], rc[3])
            if self.radPinX then icon(self, "i_pin", self.radPinX, self.radPinY - o - 8 * S, 18, C.pin, 1) end
            if self.radCarX then -- the car: a disc with the dashboard's top view (the pick map's car marker)
                local x, y = self.radCarX, self.radCarY - o
                local dim = self.sumPhase == "ready" and not self.sumCome
                HUD.rrect(self, x - 12 * S, y - 12 * S, 24 * S, 24 * S, 12 * S, C.text, 1)
                HUD.rrect(self, x - 10 * S, y - 10 * S, 20 * S, 20 * S, 10 * S, dim and C.weak or C.blue, 1)
                local car, k = self.carSpr and A[self.carSpr], 0.1 -- 300 x 170 at 2x: 15 x 8.5 units
                if car then HUD.spr(self, car, x - car[3] * self.f * k / 2, y - car[4] * self.f * k / 2, C.white, 1, k) end
            end
            HUD.rrect(self, cx - 7 * S, cy - 7 * S, 14 * S, 14 * S, 7 * S, C.text, 1) -- the player
            HUD.rrect(self, cx - 5 * S, cy - 5 * S, 10 * S, 10 * S, 5 * S, C.blue, 1)
        end
    elseif page == "cars" then
        local i = 1
        local b = self.b.pick1
        while b and b.shown do
            if b.cur then icon(self, "i_check", w - pad - 10 * S, b.cy - o + b.ch / 2, 18, C.text, 1) end
            i = i + 1
            b = self.b["pick" .. i]
        end
    end
    for _, id in ipairs(MAIN) do -- the main actions: blue
        local b = self.b[id]
        if b.shown and BTN[id][1] == page then HUD.rrect(self, b.cx, b.cy - o, b.cw, b.ch, 6 * S, C.blue, b.enable and 1 or 0.4) end
    end
    flush(self)
    if self.carW and (page == "home" or page == "controls") and self.carTex then
        self.javaObject:DrawTextureScaled(self.carTex, self.carX, self.yCar - o, self.carW, self.carH, (self.rec or self.vmOnly) and 1 or 0.5)
    end
    if clip then self:clearStencilRect() end
    if self.yToast then
        local t = self.toast
        icon(self, t.ok and "i_check" or "i_warn", pad + 9 * S, self.yToast + (t.l2 and self.FH or self.FH / 2), 18, t.ok and C.ok or C.warn, 1)
        flush(self)
    end
end

function App:render()
    if not self.S then return end
    local S, w, o, pad = self.S, self.width, self.dy, self.pad
    local jo, c, c2, cw = self.javaObject, C.text, C.text2, C.weak
    local Sm = UIFont.Small
    jo:DrawText(Sm, self.sTime, pad, self.yBar, c[1], c[2], c[3], 1)
    self:drawTextRight(self.sNet, w - pad - (self.grid and math.floor(22 * S) or 0), self.yBar, c[1], c[2], c[3], 1, Sm)
    local page = self.page
    if page == "home" then
        jo:DrawText(UIFont.Large, self.sHead, pad, self.yName, c[1], c[2], c[3], 1)
    else
        jo:DrawText(UIFont.Medium, self.sHead, self.xTitle, self.yName, c[1], c[2], c[3], 1)
    end
    local clip = self.scrollMax > 0
    if clip then self:setStencilRect(0, self.yBody, w, self.yBodyEnd - self.yBody) end
    if page == "home" then
        jo:DrawText(Sm, self.sBatFit, pad + math.floor(30 * S), self.yBat - o, c2[1], c2[2], c2[3], 1)
        jo:DrawText(Sm, self.sSubFit, pad, self.ySub - o, c2[1], c2[2], c2[3], 1)
        if self.sSub2Fit then jo:DrawText(Sm, self.sSub2Fit, pad, self.ySub2 - o, c2[1], c2[2], c2[3], 1) end
        local rx = pad + math.floor(40 * S)
        for _, id in ipairs(LIST) do
            local b = self.b[id]
            if b.shown then
                local ty = b.cy - o + math.floor((b.ch - self.FHM - math.floor(2 * S) - self.FH) / 2)
                jo:DrawText(UIFont.Medium, b.sTitle, rx, ty, c[1], c[2], c[3], 1)
                local sy = ty + self.FHM + math.floor(2 * S)
                if b.sEm then jo:DrawText(Sm, b.sEm, rx, sy, c[1], c[2], c[3], 1) end
                jo:DrawText(Sm, b.sSub, rx + b.emW, sy, c2[1], c2[2], c2[3], 1)
            end
        end
    elseif page == "controls" then
        for _, id in ipairs(self.cells or GRID) do
            local b = self.b[id]
            local tx, ty = b.cx + math.floor(14 * S), b.cy - o + math.floor(44 * S)
            local tc = b.lit and c or cw
            jo:DrawText(Sm, b.sTitle, tx, ty, tc[1], tc[2], tc[3], 1)
            local sc = b.lit and c2 or cw
            jo:DrawText(Sm, b.sSubFit, tx, ty + self.FH + math.floor(2 * S), sc[1], sc[2], sc[3], 1)
        end
    elseif page == "location" then
        if self.yArrow then
            jo:DrawTextureAngle(self.arrowTex, w / 2, self.yArrow - o, self.arrowAngle or 0, c[1], c[2], c[3], 1)
            self:drawTextCentre(self.sDistFit, w / 2, self.yDist - o, c[1], c[2], c[3], 1, UIFont.Large)
            self:drawTextCentre(self.sDirFit, w / 2, self.yDir - o, c2[1], c2[2], c2[3], 1, Sm)
            self:drawTextCentre(self.sWhenFit, w / 2, self.yWhen - o, c2[1], c2[2], c2[3], 1, Sm)
        else
            self:drawTextCentre(self.sMsg, w / 2, self.yMsg - o, c2[1], c2[2], c2[3], 1, Sm)
        end
        local b = self.b.navcar
        if b.shown then
            self:drawTextCentre(b.sTitle, b.cx + b.cw / 2, b.cy - o + (b.ch - self.FH) / 2, c[1], c[2], c[3], b.lit and 1 or 0.5, Sm)
        end
    elseif page == "security" then
        local b = self.b.sentry
        local ty = b.cy - o + math.floor((b.ch - self.FHM - math.floor(2 * S) - self.FH) / 2)
        jo:DrawText(UIFont.Medium, b.sTitle, pad, ty, c[1], c[2], c[3], 1)
        jo:DrawText(Sm, b.sSub, pad, ty + self.FHM + math.floor(2 * S), c2[1], c2[2], c2[3], 1)
        jo:DrawText(Sm, self.sAlertsHead, pad, self.yAlertsHead - o, c2[1], c2[2], c2[3], 1)
        local rows = self.alerts
        if rows and #rows > 0 then
            local ax = pad + math.floor(28 * S)
            for _, r in ipairs(rows) do
                local ry = r.y - o + math.floor(7 * S)
                if r.icon then self:drawTextureScaled(r.icon, pad, ry, 18 * S, 18 * S, 1, 1, 1, 1) end
                jo:DrawText(Sm, r.sTitle, ax, ry, c[1], c[2], c[3], 1)
                self:drawTextRight(r.sTime, w - pad, ry, c2[1], c2[2], c2[3], 1, Sm)
                jo:DrawText(Sm, r.sDetail, ax, ry + self.FH, c2[1], c2[2], c2[3], 1)
            end
        else
            jo:DrawText(Sm, self.sAlertsMsg, pad, self.yAlertsMsg - o, c2[1], c2[2], c2[3], 1)
        end
    elseif page == "powershare" then
        local ps = self.ps
        local tc = (ps == "armed" or ps == "backup") and C.ok or (ps == "stopped" and C.warn or c)
        jo:DrawText(self.psFont, self.sPsStateFit, pad, self.yPsState - o, tc[1], tc[2], tc[3], 1)
        for i = 1, #self.sPsSubs do
            jo:DrawText(Sm, self.sPsSubs[i], pad, self.yPsSub + (i - 1) * self.FH - o, c2[1], c2[2], c2[3], 1)
        end
        jo:DrawText(Sm, self.sPsFloorFit, pad, self.yPsLbl - o, c2[1], c2[2], c2[3], 1)
        self:drawTextRight(self.sPsPctFit, w - pad, self.yPsLbl - o, c2[1], c2[2], c2[3], 1, Sm)
        self:drawTextCentre(self.sPsAdj, w / 2, self.yPsAdj - o, c2[1], c2[2], c2[3], 1, Sm)
        for _, id in ipairs(PS_ADJ) do
            local fb = self.b[id]
            if fb.shown then
                self:drawTextCentre(fb.sTitle, fb.cx + fb.cw / 2, fb.cy - o + (fb.ch - self.FHM) / 2, c[1], c[2], c[3],
                    fb.lit and 1 or 0.4, UIFont.Medium)
            end
        end
        local tb = self.b.psToggle
        local bc = self.psOn and c or C.white
        self:drawTextCentre(tb.sTitle, tb.cx + tb.cw / 2, tb.cy - o + (tb.ch - self.FH) / 2, bc[1], bc[2], bc[3],
            tb.lit and 1 or 0.5, Sm)
        local ob = self.b.outlet
        if ob.shown then
            local subs = ob.sSubs
            local ty = ob.cy - o + math.floor((ob.ch - self.FHM - math.floor(2 * S) - self.FH * #subs) / 2)
            jo:DrawText(UIFont.Medium, ob.sTitle, pad, ty, c[1], c[2], c[3], 1)
            local sy = ty + self.FHM + math.floor(2 * S)
            for i = 1, #subs do jo:DrawText(Sm, subs[i], pad, sy + (i - 1) * self.FH, c2[1], c2[2], c2[3], 1) end
        end
    elseif page == "charging" then
        jo:DrawText(UIFont.Large, self.sStateFit, pad, self.yState - o, c[1], c[2], c[3], 1)
        jo:DrawText(Sm, self.sBatFit, pad + math.floor(30 * S), self.yBat - o, c2[1], c2[2], c2[3], 1)
        if self.sKwFit then jo:DrawText(Sm, self.sKwFit, pad, self.yKw - o, c[1], c[2], c[3], 1) end
        if self.sEtaFit then jo:DrawText(Sm, self.sEtaFit, pad, self.yEta - o, c2[1], c2[2], c2[3], 1) end
    elseif page == "summon" or page == "pick" then
        local n1, n2, ny
        if page == "summon" then
            self:drawTextCentre(self.sSumStateFit, w / 2, self.ySumState - o, c[1], c[2], c[3], 1, UIFont.Medium)
            self:drawTextCentre(self.sSumSubFit, w / 2, self.ySumSub - o, c2[1], c2[2], c2[3], 1, Sm)
            n1, n2, ny = self.sSumNote1, self.sSumNote2, self.ySumNote
        else
            n1, n2, ny = self.sPickNote1, self.sPickNote2, self.yPickNote
        end
        if n1 then jo:DrawText(Sm, n1, pad, ny - o, c2[1], c2[2], c2[3], 1) end
        if n2 then jo:DrawText(Sm, n2, pad, ny - o + self.FH, c2[1], c2[2], c2[3], 1) end
        for _, id in ipairs(SUM_BTNS) do
            local b = self.b[id]
            if b.shown and BTN[id][1] == page then
                local tc = b.style == "main" and C.white or b.style == "stop" and C.bg or (b.lit and c or cw)
                local a = (b.style == "main" and not b.lit) and 0.5 or 1
                self:drawTextCentre(b.sTitle, b.cx + b.cw / 2, b.cy - o + (b.ch - self.FH) / 2, tc[1], tc[2], tc[3], a, Sm)
            end
        end
    elseif page == "cars" then
        local i, rx = 1, pad
        local b = self.b.pick1
        while b and b.shown do
            local ty = b.cy - o + math.floor((b.ch - self.FHM - math.floor(2 * S) - self.FH) / 2)
            jo:DrawText(UIFont.Medium, b.sTitle, rx, ty, c[1], c[2], c[3], 1)
            jo:DrawText(Sm, b.sSub, rx, ty + self.FHM + math.floor(2 * S), c2[1], c2[2], c2[3], 1)
            i = i + 1
            b = self.b["pick" .. i]
        end
        jo:DrawText(Sm, self.sHint1, pad, self.yHint - o, c2[1], c2[2], c2[3], 1)
        if self.sHint2 then jo:DrawText(Sm, self.sHint2, pad, self.yHint - o + self.FH, c2[1], c2[2], c2[3], 1) end
    end
    for _, id in ipairs(MAIN) do
        local b = self.b[id]
        if b.shown and BTN[id][1] == page then
            self:drawTextCentre(b.sTitle, b.cx + b.cw / 2, b.cy - o + (b.ch - self.FH) / 2, 1, 1, 1, b.enable and 1 or 0.5, Sm)
        end
    end
    if clip then self:clearStencilRect() end
    if self.yToast then
        local t = self.toast
        local tc = t.ok and c or C.warn
        local tx = pad + math.floor(26 * S)
        jo:DrawText(Sm, t.l1, tx, self.yToast, tc[1], tc[2], tc[3], 1)
        if t.l2 then jo:DrawText(Sm, t.l2, tx, self.yToast + self.FH, tc[1], tc[2], tc[3], 1) end
    end
    -- hover help: the button under the mouse, or the joypad-focused one
    for _, b in ipairs(self.buttons) do
        if b:isVisible() and b.tipKey and (b.joypadFocused or b:isMouseOver()) then
            HUD.drawTip(self, b.tipKey, b.x, b.y, b.width, b.height)
            break
        end
    end
end

-- ---------------------------------------------------------------- the pick page's map
-- A vanilla UIWorldMap built like the mini map's (ISMiniMap.lua ISMiniMapInner:instantiate, InitPlayer: the same
-- worldmap.xml data, default style, what the player has seen), held on the player with the summon range filling its
-- height. It is the "spot" control: a click drops the pin; joypad: the D-pad moves it (App:move), A goes on to "Go".
-- Over it: the range ring (AutoDrive's summonReach; grid down, no more than Bluetooth's Keys.btRange), the car, the pin
-- and the player. Made the first time the page opens.
local PickMap = ISUIElement:derive("MinidoracatTeslaPickMap")
App.PickMap = PickMap
local EARTH_M = 40075016.68557849 -- MapProjection.zoomAtMetersPerPixel (zoom = log2(EARTH_M / (metres per pixel * px)))
function PickMap:instantiate()
    local jo = UIWorldMap.new(self)
    self.javaObject = jo
    local api = jo:getAPIv3()
    self.mapAPI = api
    api:setMapItem(MapItem.getSingleton())
    api:setMaxZoom(21)
    jo:setX(self.x); jo:setY(self.y); jo:setWidth(self.width); jo:setHeight(self.height)
    jo:setAnchorLeft(true); jo:setAnchorTop(true)
    local dirs = getLotDirectories()
    for i = 1, dirs:size() do
        local dir = "media/maps/" .. dirs:get(i - 1)
        if fileExists(dir .. "/worldmap.xml") then api:addData(dir .. "/worldmap.xml") end
        api:endDirectoryData()
        api:addImages(dir)
    end
    api:setBoundsFromWorld()
    api:setBoolean("HideUnvisited", true)
    api:setBoolean("Players", false) -- the app draws the player
    api:setBoolean("Symbols", false)
    api:setBoolean("MiniMapSymbols", false)
    api:setBoolean("ImagePyramid", false)
    -- top-down (the renderer's default is isometric, WorldMapRenderer.java:145, 185-193): the range is then a circle
    -- and the D-pad moves the pin along the world's axes, like the radar (vanilla ISMap.lua:39 does the same)
    api:setBoolean("Isometric", false)
    MapUtils.initDefaultStyleV1(self)
end
-- the player in the middle, 2.3 x the range top to bottom. The zoom for a height of 2m tiles is log2(EARTH_M / 2m)
-- whatever the pixel height (UIWorldMapV3.setDisplayedArea), so it holds before the first frame sizes the map.
function PickMap:prerender()
    local app = self.app
    local p = app.player
    if not p then return end
    local m = math.max(16, app.sumR or 0) * 1.15
    self.mapAPI:centerOn(p:getX(), p:getY())
    self.mapAPI:setZoom(math.log(EARTH_M / (2 * m)) / math.log(2))
end
local function disc(jo, tex, e, x, y, d, c)
    jo:DrawSubTextureRGBA(tex, e[1], e[2], e[3], e[4], x - d / 2, y - d / 2, d, d, c[1], c[2], c[3], 1)
end
function PickMap:render()
    local app = self.app
    local api, p, A, tex = self.mapAPI, app.player, app.A, app.tex
    if not (p and A) then return end
    local jo, S = self.javaObject, app.S
    local px, py = p:getX(), p:getY()
    local ux, uy = api:worldToUIX(px, py), api:worldToUIY(px, py)
    local R = app.sumR or 0
    if R > 0 then
        local r = math.abs(api:worldToUIX(px + R, py) - ux)
        local b = C.blue
        self:drawTextureScaled(app.ringTex, ux - r, uy - r, 2 * r, 2 * r, 1, b[1], b[2], b[3])
    end
    local e = A.round
    local cx, cy = app.sumCarX, app.sumCarY
    if cx then -- the car: a blue disc with the dashboard's top view, as the "Show on map" marker
        local x, y = api:worldToUIX(cx, cy), api:worldToUIY(cx, cy)
        if x >= 0 and y >= 0 and x <= self.width and y <= self.height then
            disc(jo, tex, e, x, y, 22 * S, C.white)
            disc(jo, tex, e, x, y, 18 * S, C.blue)
            local car = app.carSpr and A[app.carSpr]
            if car then
                jo:DrawSubTextureRGBA(tex, car[1], car[2], car[3], car[4], x - 7 * S, y - 4 * S, 14 * S, 8 * S, 1, 1, 1, 1)
            end
        end
    end
    local pin = app.pin
    if pin then
        local x, y = api:worldToUIX(pin.x, pin.y), api:worldToUIY(pin.x, pin.y)
        local i = A.i_pin
        local c = app.pinOk and C.pin or C.text2
        jo:DrawSubTextureRGBA(tex, i[1], i[2], i[3], i[4], x - 11 * S, y - 22 * S, 22 * S, 22 * S, c[1], c[2], c[3], 1)
    end
    disc(jo, tex, e, ux, uy, 14 * S, C.white) -- the player
    disc(jo, tex, e, ux, uy, 10 * S, C.blue)
end
function PickMap:onMouseDown() return true end
function PickMap:onMouseUp(x, y)
    self.app:setPin(self.mapAPI:uiToWorldX(x, y), self.mapAPI:uiToWorldY(x, y))
    return true
end
function PickMap:onMouseWheel() return false end -- the page scrolls (the zoom follows the range)
function PickMap:forceClick() -- joypad A on the map: on to "Go here"
    local app = self.app
    if app.b.go.shown then app:focusAt(3, 2) end
end
function App:pickMap()
    local m = self.b.spot
    if m then return m end
    m = PickMap:new(0, 0, 100, 100)
    m.app, m.id = self, "spot"
    m:initialise()
    m:instantiate()
    self:addChild(m)
    m:setVisible(false)
    self.b.spot = m
    self.buttons[#self.buttons + 1] = m
    return m
end

-- ---------------------------------------------------------------- world map marker (temporary, never saved)
-- Drawn after vanilla's map (ISWorldMap.lua:384) with the dashboard atlas; worldToUIX/Y as vanilla's print media
-- markers (:478-479). Cleared when the map closes; the app comes back then. Left out only while the MiniMap draws
-- this car on this map itself (MiniMapBridge.drawsWorld: player 0, its world map layers on, a marker for this car).
function App.drawMapCar(map, m)
    local api = map.mapAPI
    if not api then return end
    local x, y = api:worldToUIX(m.x, m.y), api:worldToUIY(m.x, m.y)
    local A = T.HUDAtlas[1]
    local tex = getTexture(A.tex)
    local e = A.round
    local jo = map.javaObject
    jo:DrawSubTextureRGBA(tex, e[1], e[2], e[3], e[4], x - 15, y - 15, 30, 30, 1, 1, 1, 1)
    local b = C.blue
    jo:DrawSubTextureRGBA(tex, e[1], e[2], e[3], e[4], x - 13, y - 13, 26, 26, b[1], b[2], b[3], 1)
    local car = m.spr and A[m.spr] -- the dashboard's top view of this car, small, as the car glyph
    if car then jo:DrawSubTextureRGBA(tex, car[1], car[2], car[3], car[4], x - 10, y - 6, 20, 11, 1, 1, 1, 1) end
    local tm = getTextManager()
    local tw = math.max(tm:MeasureStringX(UIFont.Medium, m.name or ""), tm:MeasureStringX(UIFont.Small, m.dist or ""))
    local fm, fs = tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Small)
    map:drawRect(x + 18, y - fm, tw + 12, fm + fs + 4, 0.85, 1, 1, 1)
    map:drawText(m.name or "", x + 24, y - fm + 1, 0.12, 0.13, 0.15, 1, UIFont.Medium)
    map:drawText(m.dist or "", x + 24, y + 2, 0.29, 0.32, 0.36, 1, UIFont.Small)
    App.mapDrawn = (App.mapDrawn or 0) + 1
end

local mapRender, mapClose = ISWorldMap.render, ISWorldMap.close
function ISWorldMap:render(...)
    local r = mapRender(self, ...)
    local m = App.mapCar
    local bridge = T.MiniMapBridge
    if m and not (bridge and bridge.drawsWorld(m.pn, m.key)) then App.drawMapCar(self, m) end
    return r
end
function ISWorldMap:close(...)
    local m = App.mapCar
    App.mapCar = nil
    local r = mapClose(self, ...)
    if m then App.open(m.pn, { keyId = m.key, oid = m.oid, page = "location" }) end -- back to the page that opened the map
    return r
end

return App
