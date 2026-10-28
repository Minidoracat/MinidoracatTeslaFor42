-- Charging status card: opened from the radial menu (and by other menus via MinidoracatTesla.ChargeCard.open).
-- Reads battery-part modData `chg` (architecture.md §4) and projects kw * (now - last) itself, so it never
-- waits for a packet; asks the server once for a fresh settlement (`chargeInfo`) when opened.
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "MinidoracatTesla/Core"
require "MinidoracatTesla/HUD"

local T = MinidoracatTesla
local HUD = T.HUD
local C = HUD.C
local Card = ISPanelJoypad:derive("MinidoracatTeslaChargeCard")
T.ChargeCard = Card
local cards = {} -- [playerNum]

local W, PAD, GAP = 420, 16, 10
local DAILY_LO, DAILY_HI, TRIP_HI = 50, 90, 100
local MIN_T, MAX_T, STEP_T = 50, 100, 10
local FAR = 12 -- tiles: walking away closes the card
local TITLES = {
    none = "IGUI_MinidoracatTesla_Card_NotPlugged", charging = "IGUI_MinidoracatTesla_Card_Charging",
    full = "IGUI_MinidoracatTesla_Card_Full", nopower = "IGUI_MinidoracatTesla_Card_NoPower",
    stopped = "IGUI_MinidoracatTesla_Card_Stopped",
}

local function hmm(mins)
    local m = mins % 60
    return tostring(math.floor(mins / 60)) .. (m < 10 and ":0" or ":") .. tostring(m)
end

local function fmt1(x)
    local t = math.floor(x * 10 + 0.5)
    return tostring(math.floor(t / 10)) .. "." .. tostring(t % 10)
end

function Card:new(playerNum)
    local o = ISPanelJoypad.new(self, 0, 0, W, 200)
    o.playerNum = playerNum
    o.background = false
    o.anchorLeft, o.anchorTop = false, false
    o.key = ""
    return o
end

local function styleButton(b)
    b.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    b.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0.08 }
    b.borderColor = { r = 1, g = 1, b = 1, a = 0 }
    b.textColor = { r = C.text[1], g = C.text[2], b = C.text[3], a = 1 }
end

function Card:createChildren()
    local function mk(title, fn, tip)
        local b = ISButton:new(0, 0, 40, 40, title, self, fn)
        b:initialise()
        b:instantiate()
        styleButton(b)
        b.tipKey, b.tip = tip, tip -- hover help (HUD.drawTip in render); b.tip = the help while the cable rule allows
        self:addChild(b)
        return b
    end
    self.btnToggle = mk("", Card.onToggle, "IGUI_MinidoracatTesla_Tip_CardStart")
    self.btnUnplug = mk(getText("IGUI_MinidoracatTesla_Card_Unplug"), Card.onUnplug, "IGUI_MinidoracatTesla_Tip_CardUnplug")
    self.btnMinus = mk("-", Card.onMinus, "IGUI_MinidoracatTesla_Tip_CardMinus")
    self.btnPlus = mk("+", Card.onPlus, "IGUI_MinidoracatTesla_Tip_CardPlus")
    self.btnClose = mk(getText("IGUI_MinidoracatTesla_Card_Close"), Card.close, "IGUI_MinidoracatTesla_Tip_CardClose")
    self:insertNewLineOfButtons(self.btnToggle, self.btnUnplug, self.btnMinus, self.btnPlus, self.btnClose)
    self.buttons = { self.btnToggle, self.btnUnplug, self.btnMinus, self.btnPlus, self.btnClose }
end

-- ---------------------------------------------------------------- open / close
function Card.open(playerNum, vehicle)
    local c = cards[playerNum]
    if not c then
        c = Card:new(playerNum)
        c:initialise()
        c:instantiate()
        cards[playerNum] = c
    end
    c.vehicle = vehicle
    c.vid = vehicle:getId()
    c.player = getSpecificPlayer(playerNum)
    c.pendingTarget = nil
    c.key = ""
    c:read()
    c:layout()
    if not c.inUI then c:addToUIManager(); c.inUI = true end
    c:setVisible(true)
    c:bringToTop()
    if c.state ~= "none" then -- plugged in: the server settles now and syncs the part modData
        T.request(c.player, "chargeInfo", { vid = c.vid })
    end
    if JoypadState.players[playerNum + 1] then setJoypadFocus(playerNum, c) end -- JoyPadSetup.lua:546
    return c
end

function Card:close()
    if self.joyfocus and JoypadState.players[self.playerNum + 1] then setJoypadFocus(self.playerNum, nil) end
    self.joyfocus = nil
    if self.inUI then self:removeFromUIManager(); self.inUI = false end
    self.vehicle = nil
end

function Card:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData)
    self:setISButtonForB(self.btnClose)
    self:layout() -- the B glyph widens the close button (fit below)
    self:setJoypadFocusTopLeft(joypadData)
end

function Card:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
    self:clearJoypadFocus(joypadData)
    self:clearISButtonB() -- ISPanelJoypad.lua:303-306
    if self.inUI then self:layout() end
end

-- ---------------------------------------------------------------- actions (server validates everything)
function Card:target()
    return self.pendingTarget or self.st_target or 90
end

function Card:sendTarget(pct)
    self.pendingTarget = pct
    T.request(self.player, "chargeTarget", { vid = self.vid, pct = pct })
    self.key = ""
end

function Card:onMinus() self:sendTarget(math.max(MIN_T, self:target() - STEP_T)) end
function Card:onPlus() self:sendTarget(math.min(MAX_T, self:target() + STEP_T)) end

function Card:onToggle()
    if self.state == "charging" then
        T.request(self.player, "chargeStop", { vid = self.vid })
    else -- stopped or full: (re)send the target, which resumes (architecture.md §7)
        local t = self:target()
        if self.state == "full" and t < MAX_T then t = t + STEP_T end
        self:sendTarget(t)
    end
end

function Card:onUnplug()
    local Charge = T.Charge
    if Charge and Charge.queueUnplug and self.vehicle then Charge.queueUnplug(self.player, self.vehicle) end
    self:close()
end

-- ---------------------------------------------------------------- reading (10 Hz, strings only on change)
function Card:read()
    local v = self.vehicle
    local part = v and T.Battery.part(v)
    local chg = part and part:getModData().chg
    local state, pct, kw, addKm, addKwh, mins, target, src = "none", 0, 0, 0, 0, 0, 90, ""
    if part then pct = math.floor(T.Battery.pct(part) + 0.5) end
    if chg then
        local kwh, added, hours, cap = T.Battery.chargeEstimate(part, chg, T.hours())
        pct = math.min(100, math.floor(kwh * 100 / math.max(1, cap) + 0.5)) -- int container cap can exceed the pack's kWh
        local kmk = T.kmPerKwh(v)
        addKm = math.floor(added * kmk + 0.5)
        addKwh = math.floor(added * 10 + 0.5)
        mins = math.floor(hours * 60 + 0.5)
        kw = math.floor((chg.kw or 0) * 10 + 0.5)
        target = chg.target or 90
        src = chg.src or ""
        if chg.paused == "full" then state = "full"
        elseif chg.paused == "nopower" then state = "nopower"
        elseif chg.paused then state = "stopped"
        else state = "charging" end
        self.kind = chg.kind
    end
    if self.pendingTarget == target then self.pendingTarget = nil end
    self.st_target = target
    self.pct = pct
    -- the four charging buttons take the cable rule (Chargers.lua T.mayUseCable), as the server's chargeTarget /
    -- chargeStop and unplug do (Charging.lua): refused = greyed (setEnable, like the toggle with nothing to resume),
    -- the hover help says why
    local deny = nil
    if chg and self.player then
        local ok, why = T.mayUseCable(self.player, v)
        if not ok then deny = why end
    end
    local key = state .. pct .. "/" .. kw .. "/" .. addKm .. "/" .. addKwh .. "/" .. mins .. "/" .. self:target() .. src .. (deny or "")
    if key == self.key then return false end
    self.key = key
    local was = self.state
    self.state = state
    local tgt = tostring(self:target())
    self.sTitle = getText(TITLES[state])
    self.sPct = tostring(pct) .. "%"
    self.sDaily, self.sTrip = getText("IGUI_MinidoracatTesla_Card_Daily"), getText("IGUI_MinidoracatTesla_Card_Trip")
    self.sKw = fmt1(kw / 10) .. " kW"
    self.sKind = self.kind and getItemName("Base.MinidoracatTesla_" .. self.kind) or "" -- LuaManager.java:8745-8763
    self.sAddKm = "+" .. tostring(addKm) .. " km"
    self.sAddKwh = getText("IGUI_MinidoracatTesla_Card_AddedKwh", fmt1(addKwh / 10))
    self.sTime = state == "charging" and hmm(mins) or "--"
    self.sToTarget = getText("IGUI_MinidoracatTesla_Card_ToTarget", tgt)
    self.sTarget = getText("IGUI_MinidoracatTesla_Card_Target", tgt)
    self.sSrc = src == "grid" and getText("IGUI_MinidoracatTesla_Card_SrcGrid")
        or (src == "generator" and getText("IGUI_MinidoracatTesla_Card_SrcGenerator") or nil)
    self.sAlert = (state == "full" and getText("IGUI_MinidoracatTesla_Card_FullHint"))
        or (state == "nopower" and getText("IGUI_MinidoracatTesla_Card_NoPowerHint"))
        or (state == "none" and getText("IGUI_MinidoracatTesla_Card_NotPluggedHint")) or nil
    self.alertColor = state == "full" and C.ok or (state == "nopower" and C.warn or C.text2)
    self.btnToggle:setTitle(getText(state == "charging" and "IGUI_MinidoracatTesla_Card_Stop" or "IGUI_MinidoracatTesla_Card_Start"))
    self.btnToggle.tip = state == "charging" and "IGUI_MinidoracatTesla_Tip_CardStop" or "IGUI_MinidoracatTesla_Tip_CardStart"
    self.btnToggle:setEnable(not deny and (state == "charging" or state == "stopped" or state == "full"))
    for _, b in ipairs({ self.btnUnplug, self.btnMinus, self.btnPlus }) do b:setEnable(not deny) end
    for _, b in ipairs({ self.btnToggle, self.btnUnplug, self.btnMinus, self.btnPlus }) do
        b.tipKey = deny and ("IGUI_MinidoracatTesla_Deny_" .. deny) or b.tip
    end
    return was ~= state
end

function Card:update()
    ISPanelJoypad.update(self)
    local v = self.vehicle
    if not v then return end
    local p = self.player
    if getVehicleById(self.vid) == nil or not p or p:isDead() or (p:getVehicle() ~= v and p:DistTo(v) > FAR) then
        self:close()
        return
    end
    local _, hy, _, _, hv = MinidoracatTeslaAPI.hudRect(self.playerNum)
    if self:read() or hy ~= self.hudY or hv ~= self.hudV then self:layout() end -- HUD grew/shrank: stay above it
end

-- ---------------------------------------------------------------- layout and drawing
function Card:layout()
    local tm = getTextManager()
    self.tipKey = nil -- re-measure the hover help at the new scale
    local S = tm:getFontHeight(UIFont.Small) / 19
    local pn = self.playerNum
    S = math.min(S, (getPlayerScreenWidth(pn) - 8) / W)
    self.S = S
    self.FH, self.FHM, self.FHL = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.Medium), tm:getFontHeight(UIFont.Large)
    local k = S >= 1.5 and 2 or 1
    self.A = T.HUDAtlas[k]
    self.tex = getTexture(self.A.tex)
    self.f = S / k
    local pad, gap, s8 = math.floor(PAD * S), math.floor(GAP * S), math.floor(8 * S)
    local plugged = self.state ~= "none"
    local bh = math.max(self.FH + math.floor(16 * S), math.floor(36 * S))
    -- ISButton draws a joypad/icon texture left of the title and shifts it by 5 + joypadTextureWH (ISButton.lua:238-245, :451-452)
    local function fit(b)
        local w = tm:MeasureStringX(UIFont.Small, b.title) + math.floor(24 * S)
        if (b.isJoypad and b.joypadTexture) or b.iconTexture then w = w + 5 + b.joypadTextureWH end
        return w
    end
    local toggleW, unplugW, closeW = fit(self.btnToggle), fit(self.btnUnplug), fit(self.btnClose)
    local tw = tm:MeasureStringX(UIFont.Small, self.sTarget or "") + math.floor(12 * S)
    -- the card grows for longer translations instead of letting text or buttons overlap
    local need = math.floor(W * S)
    if plugged then
        need = math.max(need, 2 * pad + toggleW + unplugW + 2 * bh + tw + closeW + 4 * s8)
        local tile = 0
        for _, t in ipairs({ self.sKw, self.sAddKm, self.sTime }) do tile = math.max(tile, tm:MeasureStringX(UIFont.Medium, t)) end
        for _, t in ipairs({ self.sKind, self.sAddKwh, self.sToTarget }) do tile = math.max(tile, tm:MeasureStringX(UIFont.Small, t)) end
        need = math.max(need, 2 * pad + 3 * (tile + math.floor(18 * S)) + 2 * s8)
    end
    if self.sAlert then need = math.max(need, 2 * pad + tm:MeasureStringX(UIFont.Small, self.sAlert) + math.floor(48 * S)) end
    local w = math.min(need, getPlayerScreenWidth(pn) - 8)
    local y = pad
    self.yHead = y
    y = y + math.max(self.FHM, self.FHL) + gap
    self.yBar = y
    y = y + math.floor(10 * S) + math.floor(6 * S)
    self.yRange = y
    y = y + self.FH + gap
    self.yTiles = plugged and y or nil
    if plugged then y = y + self.FHM + self.FH + math.floor(16 * S) + gap end
    self.yAlert = self.sAlert and y or nil
    if self.sAlert then y = y + self.FH + math.floor(14 * S) + gap end
    -- buttons row: [toggle][unplug] ... [-][Target N%][+]  [close]
    for _, b in ipairs(self.buttons) do b:setY(y); b:setHeight(bh) end
    self.btnToggle:setVisible(plugged)
    self.btnUnplug:setVisible(plugged)
    self.btnMinus:setVisible(plugged)
    self.btnPlus:setVisible(plugged)
    self.btnToggle:setX(pad); self.btnToggle:setWidth(toggleW)
    self.btnUnplug:setX(pad + toggleW + s8); self.btnUnplug:setWidth(unplugW)
    self.btnClose:setX(w - pad - closeW); self.btnClose:setWidth(closeW)
    local px = w - pad - closeW - s8 - bh
    self.btnPlus:setX(px); self.btnPlus:setWidth(bh)
    self.xTarget = px - tw
    self.btnMinus:setX(self.xTarget - bh); self.btnMinus:setWidth(bh)
    self.yButtons, self.bh = y, bh
    y = y + bh
    if self.sSrc and plugged then
        y = y + gap
        self.ySrc = y
        y = y + self.FH
    else
        self.ySrc = nil
    end
    y = y + pad
    self:setWidth(w)
    self:setHeight(y)
    -- above the Tesla HUD when it is up, else above the bottom of this player's screen
    local _, hy, _, _, hv = MinidoracatTeslaAPI.hudRect(pn)
    self.hudY, self.hudV = hy, hv
    local bottom = hv and (hy - math.floor(8 * S)) or (getPlayerScreenTop(pn) + getPlayerScreenHeight(pn) - math.floor(130 * S))
    self:setX(getPlayerScreenLeft(pn) + math.floor((getPlayerScreenWidth(pn) - w) / 2))
    self:setY(bottom - y)
end

-- immediate-mode drawing with the HUD helpers (the card is open rarely; no quad cache needed)
local function flush(self)
    local jo, tex, L = self.javaObject, self.tex, self.L
    for i = 1, self.n, 12 do
        jo:DrawSubTextureRGBA(tex, L[i], L[i + 1], L[i + 2], L[i + 3], L[i + 4], L[i + 5], L[i + 6], L[i + 7],
            L[i + 8], L[i + 9], L[i + 10], L[i + 11])
    end
    self.n = 0
end

function Card:prerender()
    if not self.S then return end
    self.L = self.L or {}
    self.n = 0
    local S, w, h = self.S, self.width, self.height
    local pad = math.floor(PAD * S)
    HUD.rrect(self, 0, 0, w, h, 24 * S, C.bg, 0.96)
    -- progress bar with target marker
    local bx, bw, by, bhh = pad, w - 2 * pad, self.yBar, math.floor(10 * S)
    HUD.rrect(self, bx, by, bw, bhh, bhh / 2, C.track, 1)
    local fill = math.floor(bw * self.pct / 100)
    if fill >= bhh then HUD.rrect(self, bx, by, fill, bhh, bhh / 2, self.state == "charging" and C.ok or C.text2, 1) end
    local tx = bx + bw * self:target() / 100
    HUD.rect(self, tx - S, by - 4 * S, 2 * S, bhh + 8 * S, C.text, 1)
    -- daily / trip brackets
    local ry = self.yRange
    local x1, x2, x3 = bx + bw * DAILY_LO / 100, bx + bw * DAILY_HI / 100, bx + bw * TRIP_HI / 100
    HUD.rect(self, x1, ry, x2 - x1 - 2 * S, math.max(1, S), C.text3, 1)
    HUD.rect(self, x2 + 2 * S, ry, x3 - x2 - 2 * S, math.max(1, S), C.text3, 1)
    -- stat tiles
    if self.yTiles then
        local tw = math.floor((w - 2 * pad - 2 * 8 * S) / 3)
        local th = self.FHM + self.FH + math.floor(16 * S)
        for i = 0, 2 do HUD.rrect(self, pad + i * (tw + 8 * S), self.yTiles, tw, th, 9 * S, C.surface, 1) end
        self.tileW = tw
    end
    if self.yAlert then
        HUD.rrect(self, pad, self.yAlert, w - 2 * pad, self.FH + math.floor(14 * S), 9 * S, C.surface, 1)
        HUD.spr(self, self.state == "full" and self.A.i_check or self.A.i_warn, pad + 10 * S, self.yAlert + (self.FH + 14 * S - 18 * S) / 2, self.alertColor, 1)
    end
    -- button backgrounds (rounded) and joypad focus ring
    local bs = self.buttons
    for i = 1, #bs do
        local b = bs[i]
        if b:isVisible() then
            local primary = b == self.btnUnplug and self.state == "full"
            if b.joypadFocused then -- 2 px white ring with a bg gap, like the mock's .focus
                HUD.rrect(self, b.x - 4 * S, b.y - 4 * S, b.width + 8 * S, b.height + 8 * S, 13 * S, C.text, 1)
                HUD.rrect(self, b.x - 2 * S, b.y - 2 * S, b.width + 4 * S, b.height + 4 * S, 11 * S, C.bg, 1)
            end
            HUD.rrect(self, b.x, b.y, b.width, b.height, 10 * S, primary and C.accentFill or C.surface, b.enable and 1 or 0.5)
        end
    end
    flush(self)
end

function Card:render()
    if not self.S then return end
    local S, w = self.S, self.width
    local pad = math.floor(PAD * S)
    local jo, c, c2 = self.javaObject, C.text, C.text2
    jo:DrawText(UIFont.Medium, self.sTitle, pad, self.yHead + (math.max(self.FHM, self.FHL) - self.FHM) / 2, c[1], c[2], c[3], 1)
    self:drawTextRight(self.sPct, w - pad, self.yHead, c[1], c[2], c[3], self.state == "nopower" and 0.6 or 1, UIFont.Large)
    -- bracket labels
    local bx, bw = pad, w - 2 * pad
    local ry = self.yRange + math.floor(2 * S)
    self:drawTextCentre(self.sDaily, bx + bw * (DAILY_LO + DAILY_HI) / 200, ry, c2[1], c2[2], c2[3], 1, UIFont.Small)
    self:drawTextRight(self.sTrip, bx + bw, ry, c2[1], c2[2], c2[3], 1, UIFont.Small)
    if self.yTiles then
        local tw = self.tileW
        local ty, ty2 = self.yTiles + math.floor(7 * S), self.yTiles + math.floor(7 * S) + self.FHM
        local step = tw + 8 * S
        local tx = pad + math.floor(9 * S)
        jo:DrawText(UIFont.Medium, self.sKw, tx, ty, c[1], c[2], c[3], 1)
        jo:DrawText(UIFont.Small, self.sKind, tx, ty2, c2[1], c2[2], c2[3], 1)
        jo:DrawText(UIFont.Medium, self.sAddKm, tx + step, ty, c[1], c[2], c[3], 1)
        jo:DrawText(UIFont.Small, self.sAddKwh, tx + step, ty2, c2[1], c2[2], c2[3], 1)
        jo:DrawText(UIFont.Medium, self.sTime, tx + 2 * step, ty, c[1], c[2], c[3], 1)
        jo:DrawText(UIFont.Small, self.sToTarget, tx + 2 * step, ty2, c2[1], c2[2], c2[3], 1)
    end
    if self.yAlert then
        jo:DrawText(UIFont.Small, self.sAlert, pad + math.floor(36 * S), self.yAlert + math.floor(7 * S), c[1], c[2], c[3], 1)
    end
    if self.btnMinus:isVisible() then
        self:drawTextCentre(self.sTarget, self.xTarget + (self.btnPlus.x - self.xTarget) / 2, self.yButtons + (self.bh - self.FH) / 2, c[1], c[2], c[3], 1, UIFont.Small)
    end
    if self.ySrc then jo:DrawText(UIFont.Small, self.sSrc, pad, self.ySrc, c2[1], c2[2], c2[3], 1) end
    -- hover help: the button under the mouse, or the joypad-focused one
    local bs = self.buttons
    for i = 1, #bs do
        local b = bs[i]
        if b:isVisible() and (b.joypadFocused or b:isMouseOver()) then
            HUD.drawTip(self, b.tipKey, b.x, b.y, b.width, b.height)
            break
        end
    end
end

Events.OnResolutionChange.Add(function()
    for _, c in pairs(cards) do
        if c.vehicle then c:layout() end
    end
end)

-- ---------------------------------------------------------------- public API for other mods (AutoDrive FSD card)
-- Contract: references/hud.md "chargeCardRect". Same coordinates and cost rules as hudRect: where the card is drawn now.
MinidoracatTeslaAPI = MinidoracatTeslaAPI or {}
function MinidoracatTeslaAPI.chargeCardRect(playerNum)
    local c = cards[playerNum or 0]
    if not c or not c.vehicle or not c.inUI then return 0, 0, 0, 0, false end
    return c.x, c.y, c.width, c.height, c:isVisible()
end

return Card
