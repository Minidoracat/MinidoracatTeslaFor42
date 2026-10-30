-- Sentry / Camp client side: outside right-click menu on a Tesla, owner notifications (toast stack),
-- offline inbox pull on game start. Display only; every state change goes through server commands.
require "MinidoracatTesla/Core"
require "MinidoracatTesla/ParkModes"
require "ISUI/ISPanel"

local T = MinidoracatTesla
local S, C = T.Sentry, T.Camp
T.ClientCommands = T.ClientCommands or {}
local UI = {}
T.ParkUI = UI

-- ------------------------------------------------------------------ outside right-click menu
local function onSentry(player, vehicle, cmd)
    T.request(player, cmd, { vid = vehicle:getId() })
end

local function tip(option, text, blocked)
    local tt = ISWorldObjectContextMenu.addToolTip()
    tt.description = text
    option.toolTip = tt
    if blocked then option.notAvailable = true end
end

local denyText = T.denyText

function UI.fillMenu(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    -- same pick as vanilla ISVehicleMenu.OnFillWorldObjectContextMenu (ISVehicleMenu.lua:49)
    local vehicle = IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not vehicle or not T.isTesla(vehicle) then return end
    local part = T.Battery.part(vehicle)
    if not part then return end
    local s = part:getModData().sentry
    if s then
        local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_SentryOff"), player, onSentry, vehicle, "sentryDisarm")
        local ok, why = S.canDisarm(player, vehicle)
        local hours = math.floor(getGameTime():getWorldAgeHours() - (tonumber(s.since) or tonumber(s.at) or 0))
        tip(opt, ok and getText("Tooltip_MinidoracatTesla_SentryOnFor", tostring(hours > 0 and hours or 0)) or denyText(why), not ok)
    else
        local opt = context:addOption(getText("ContextMenu_MinidoracatTesla_SentryOn"), player, onSentry, vehicle, "sentryArm")
        local ok, why = S.canArm(player, vehicle)
        local pct = math.floor(T.Battery.pct(part))
        tip(opt, ok and getText("Tooltip_MinidoracatTesla_Battery", tostring(pct)) or denyText(why), not ok)
    end
    -- camp is switched from the seat (V radial menu); shown here greyed so players know where it is
    local camp = context:addOption(getText("ContextMenu_MinidoracatTesla_CampOn"), nil, nil)
    tip(camp, denyText("NOT_INSIDE"), true)
end
Events.OnFillWorldObjectContextMenu.Add(UI.fillMenu)

-- ------------------------------------------------------------------ toast stack
-- One top-level panel while there is something to show; removed when the queue empties.
-- Text and widths are computed when a toast is queued, render only draws cached values.
UI.SHOW_MS = 8000
UI.MAX_VISIBLE = 3
local FONT_T, FONT_D = UIFont.Medium, UIFont.Small
local PAD, ICON, GAP, MIN_W = 10, 18, 6, 360

local queue = {}
local panel = nil

local Toast = ISPanel:derive("MinidoracatTeslaToast")

function Toast:new()
    local o = ISPanel.new(self, 0, 70, MIN_W, 10)
    o:noBackground()
    o.wantMouseEvents = false -- display only: never eat clicks (family pitfalls.md "純顯示的置頂面板")
    o.cards = {}
    return o
end

function Toast:onRightMouseDown() return false end
function Toast:onRightMouseUp() return false end

function Toast:layout()
    local w, h = MIN_W, 0
    for i = 1, #self.cards do
        local c = self.cards[i]
        if c.w > w then w = c.w end
        h = h + c.h + GAP
    end
    self:setWidth(w)
    self:setHeight(h > 0 and h - GAP or 1)
    self:setX(math.floor((getCore():getScreenWidth() - w) / 2))
end

function Toast:update()
    local now = getTimestampMs()
    local changed = false
    for i = #self.cards, 1, -1 do
        if now >= self.cards[i].untilMs then
            table.remove(self.cards, i)
            changed = true
        end
    end
    while #self.cards < UI.MAX_VISIBLE and #queue > 0 do
        local c = table.remove(queue, 1)
        c.untilMs = now + UI.SHOW_MS
        self.cards[#self.cards + 1] = c
        changed = true
    end
    if #self.cards == 0 then
        self:removeFromUIManager()
        panel = nil
        return
    end
    if changed then self:layout() end
end

function Toast:render()
    local y = 0
    local w = self.width
    for i = 1, #self.cards do
        local c = self.cards[i]
        self:drawRect(0, y, w, c.h, 0.92, 0.09, 0.10, 0.11)
        self:drawRectBorder(0, y, w, c.h, 0.6, 0.30, 0.32, 0.35)
        if c.icon then self:drawTextureScaled(c.icon, PAD, y + PAD, ICON, ICON, 1, 1, 1, 1) end
        local tx = PAD + ICON + 8
        self:drawText(c.title, tx, y + PAD - 2, 1, 1, 1, 1, FONT_T)
        if c.time then
            self:drawTextRight(c.time, w - PAD, y + PAD, 0.68, 0.71, 0.75, 1, FONT_D)
        end
        if c.detail then
            self:drawText(c.detail, tx, y + PAD + c.titleH, 0.68, 0.71, 0.75, 1, FONT_D)
        end
        y = y + c.h + GAP
    end
end

local icons = {}
local function icon(name)
    if icons[name] == nil then icons[name] = getTexture("media/ui/MinidoracatTesla/" .. name .. ".png") or false end
    return icons[name] or nil
end

local TITLE = {
    touch = { door = "IGUI_MinidoracatTesla_Sentry_TouchDoor", unlock = "IGUI_MinidoracatTesla_Sentry_TouchUnlock" },
    ["break"] = { window = "IGUI_MinidoracatTesla_Sentry_BreakWindow", hotwire = "IGUI_MinidoracatTesla_Sentry_BreakHotwire",
        part = "IGUI_MinidoracatTesla_Sentry_BreakPart" },
    lowBattery = { sentry = "IGUI_MinidoracatTesla_Sentry_LowBattery", camp = "IGUI_MinidoracatTesla_Camp_LowBattery",
        powershare = "IGUI_MinidoracatTesla_Powershare_LowBattery" }, -- powershare: %1 = its discharge limit
}

-- Build a card from a server event record (Inbox.entry): { kind, what, part, by, car, hh, mm, pct }.
function UI.card(e)
    local tm = getTextManager()
    local keys = TITLE[e.kind]
    local key = keys and keys[e.what]
    if not key then return nil end
    local bits = {}
    if e.car and e.car ~= "" then bits[#bits + 1] = getText("IGUI_VehicleName" .. e.car) end
    if e.part then
        local pk = "IGUI_VehiclePart" .. e.part
        -- events are always a Tesla's (Core.lua T.partNameKey; e.car = the script name without "Base.")
        local pn = getTextOrNull(T.partNameKey("Base." .. tostring(e.car), pk) or pk)
        if pn then bits[#bits + 1] = pn end
    end
    -- a bare % in a getText argument crashes formatted() (verify_mod check 4); names are player-chosen. by = false: an
    -- intruder with no verified account (Inbox.entry), so no name to trust
    if e.by then bits[#bits + 1] = getText("IGUI_MinidoracatTesla_Sentry_ByPlayer", (tostring(e.by):gsub("%%", "")))
    elseif e.by == false then bits[#bits + 1] = getText("IGUI_MinidoracatTesla_Sentry_ByUnverified") end
    if e.kind == "touch" then bits[#bits + 1] = getText("IGUI_MinidoracatTesla_Sentry_Flashed") end
    local c = {
        title = getText(key, tostring(e.pct or 20)), -- camp lowBattery: %1 = the sandbox limit (records before it: 20)
        detail = #bits > 0 and table.concat(bits, getText("IGUI_MinidoracatTesla_Sep")) or nil,
        time = tonumber(e.hh) and string.format("%02d:%02d", e.hh, tonumber(e.mm) or 0) or nil,
        icon = icon(e.what == "camp" and "toast_camp"
            or ((e.kind == "touch" or e.what == "powershare") and "toast_sentry_touch" or "toast_sentry_break")),
    }
    c.titleH = tm:getFontHeight(FONT_T)
    c.h = PAD * 2 + c.titleH + (c.detail and tm:getFontHeight(FONT_D) or 0)
    local tw = PAD + ICON + 8 + tm:MeasureStringX(FONT_T, c.title) + 16 + (c.time and tm:MeasureStringX(FONT_D, c.time) or 0) + PAD
    local dw = c.detail and (PAD + ICON + 8 + tm:MeasureStringX(FONT_D, c.detail) + PAD) or 0
    c.w = math.max(tw, dw)
    return c
end

function UI.push(c)
    if not c then return end
    queue[#queue + 1] = c
    if not panel then
        panel = Toast:new()
        panel:initialise()
        panel:addToUIManager()
    end
    UI.shown = (UI.shown or 0) + 1
    T.log("toast " .. tostring(c.title))
end

-- ------------------------------------------------------------------ server -> client
T.ClientCommands.alert = function(args)
    UI.last = args
    UI.push(UI.card(args))
end

T.ClientCommands.inbox = function(args)
    local list = args and args.list
    if type(list) ~= "table" then return end
    local n = #list
    UI.lastInbox = list
    T.log("inbox received " .. n)
    UI.push({ title = getText("IGUI_MinidoracatTesla_Inbox_Title", tostring(n)), titleH = getTextManager():getFontHeight(FONT_T),
        h = PAD * 2 + getTextManager():getFontHeight(FONT_T), icon = icon("toast_sentry_touch"),
        w = PAD + ICON + 8 + getTextManager():MeasureStringX(FONT_T, getText("IGUI_MinidoracatTesla_Inbox_Title", tostring(n))) + PAD })
    for i = n, 1, -1 do UI.push(UI.card(list[i])) end -- newest first
end

-- Offline events are delivered once per login (no reliable server-side join event, GameClient.java:336-364).
-- Not from OnGameStart itself: it fires in IngameState.enter (IngameState.java:766) before UpdateStuff sets
-- GameClient.ingame (:568), and sendClientCommand without ingame goes to the local SinglePlayerClient
-- (LuaManager.java:8940-8947), never reaching the server. The first OnTick comes right after UpdateStuff (:1559-1563).
local function pullInbox()
    Events.OnTick.Remove(pullInbox)
    local p = getSpecificPlayer(0)
    if p then T.request(p, "inboxPull") end
end
Events.OnGameStart.Add(function() Events.OnTick.Add(pullInbox) end)
