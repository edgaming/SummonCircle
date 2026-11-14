-- Summon Circle: the window.
--
-- Layout, top to bottom:
--   title + price
--   banner: what to do now + one big button
--   summoners (leader: gear opens the picker)
--   queue
--   footer: earnings, Advertise (leader only; gear opens ad settings)
local ADDON, ns = ...

local W = 460
local ROWS = 8
local ROW_H = 20
local SUM_LINES = 5

local Y_STATUS = -34
local STATUS_H = 30
local Y_BANNER = Y_STATUS - STATUS_H - 6
local BANNER_H = 74
local Y_SUM = Y_BANNER - BANNER_H - 12
local Y_QUEUE = Y_SUM - 20 - SUM_LINES * 15 - 10
local Y_ROWS = Y_QUEUE - 20
local H = -Y_ROWS + ROWS * ROW_H + 58

local GREY, GREEN, YELLOW, ORANGE, RED, PURPLE =
  "808080", "40ff40", "ffd100", "ff8000", "ff4040", "b070ff"

local function c(hex, text) return "|cff" .. hex .. text .. "|r" end

local f, rows, big, adBtn, adGear, sumGear, sumPanel, adPanel

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------
local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function fs(parent, font, justify)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  s:SetJustifyH(justify or "LEFT")
  return s
end

local function button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22)
  b:SetText(text)
  return b
end

local function gear(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", onClick)
  return b
end

local function checkbox(parent)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb.label = fs(cb, "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.hint = fs(cb, "GameFontDisableSmall")
  cb.hint:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)
  return cb
end

local function section(parent, text, y, x)
  local s = fs(parent, "GameFontNormalSmall")
  s:SetPoint("TOPLEFT", x or 14, y)
  s:SetText(text:upper())
  return s
end

local function sidePanel(title)
  local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
  p:SetSize(290, H)
  p:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
  p:SetBackdrop(BACKDROP)
  p:SetBackdropColor(0.06, 0.02, 0.09, 0.95)
  p:EnableMouse(true)
  p.title = fs(p, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 14, -12)
  p.title:SetText(title)
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  p:Hide()
  return p
end

local function togglePanel(p)
  local show = not p:IsShown()
  sumPanel:Hide(); adPanel:Hide()
  p:SetShown(show)
  ns:Refresh()
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local function buildRow(i)
  local r = CreateFrame("Frame", nil, f)
  r:SetSize(W - 28, ROW_H)
  r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, Y_ROWS - (i - 1) * ROW_H)
  r.num = fs(r); r.num:SetPoint("LEFT", 0, 0); r.num:SetWidth(16)
  r.name = fs(r); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(110)
  r.zone = fs(r); r.zone:SetPoint("LEFT", 130, 0); r.zone:SetWidth(120)
  r.status = fs(r); r.status:SetPoint("LEFT", 252, 0); r.status:SetWidth(120)
  r.btn = button(r, "", 58, 18); r.btn:SetPoint("RIGHT", 0, 0)
  return r
end

local function buildMain()
  f = CreateFrame("Frame", "SummonCircleFrame", UIParent, "BackdropTemplate")
  f:SetSize(W, H)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.06, 0.02, 0.09, 0.92)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.ui.pos = { p, rp, x, y }
  end)
  local pos = ns.db.ui.pos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end

  -- Title + price
  f.title = fs(f, "GameFontNormal"); f.title:SetPoint("TOPLEFT", 14, -12)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() ns:ToggleUI(false) end)

  f.priceText = fs(f, "GameFontHighlight", "RIGHT")
  f.priceText:SetPoint("TOPRIGHT", -36, -13)

  -- Status bar: OPEN / CLOSED, colour-coded, with the one on/off toggle.
  local status = CreateFrame("Frame", nil, f, "BackdropTemplate")
  status:SetPoint("TOPLEFT", 10, Y_STATUS)
  status:SetPoint("TOPRIGHT", -10, Y_STATUS)
  status:SetHeight(STATUS_H)
  status:SetBackdrop(BACKDROP)
  f.status = status
  f.dot = status:CreateTexture(nil, "OVERLAY")
  f.dot:SetSize(10, 10)
  f.dot:SetPoint("LEFT", 12, 0)
  f.statusText = fs(status, "GameFontHighlight")
  f.statusText:SetPoint("LEFT", f.dot, "RIGHT", 8, 0)
  f.toggle = button(status, "Open for business", 150, 22)
  f.toggle:SetPoint("RIGHT", -5, 0)
  f.toggle:SetScript("OnClick", function()
    if ns:IsActive() then ns:StopSession() else ns:StartSession() end
  end)

  -- Banner: what to do now + the big button
  local banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.banner = banner
  banner:SetPoint("TOPLEFT", 10, Y_BANNER)
  banner:SetPoint("TOPRIGHT", -10, Y_BANNER)
  banner:SetHeight(BANNER_H)
  banner:SetBackdrop(BACKDROP)
  banner:SetBackdropColor(0.18, 0.08, 0.26, 0.9)
  f.bannerText = fs(banner, "GameFontHighlight", "CENTER")
  f.bannerText:SetPoint("TOPLEFT", 10, -10)
  f.bannerText:SetPoint("TOPRIGHT", -10, -10)

  -- One secure button for every action. For a summon it runs a macro;
  -- for everything else it runs our function in PostClick.
  big = CreateFrame("Button", "SummonCircleActionButton", banner,
    "SecureActionButtonTemplate,UIPanelButtonTemplate")
  big:SetSize(W - 80, 28)
  big:SetPoint("BOTTOM", 0, 10)
  -- Secondary choice (e.g. "Kick + blacklist") shown beside the big button.
  f.alt = button(banner, "", 150, 28)
  f.alt:SetPoint("BOTTOMRIGHT", -20, 10)
  f.alt:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
  f.alt:Hide()
  big:RegisterForClicks("AnyUp", "AnyDown")
  local function isRealPress(down) return down == GetCVarBool("ActionButtonUseKeyDown") end
  big:SetScript("PreClick", function(self, _, down)
    if isRealPress(down) then ns.pendingTarget = self.target end
  end)
  big:SetScript("PostClick", function(self, _, down)
    if isRealPress(down) and self.fn then self.fn() end
  end)

  -- Summoners
  section(f, "Summoners", Y_SUM)
  sumGear = gear(f, function() togglePanel(sumPanel) end)
  sumGear:SetPoint("TOPLEFT", 92, Y_SUM + 2)
  f.summoners = {}
  for i = 1, SUM_LINES do
    local line = fs(f, "GameFontHighlight")
    line:SetPoint("TOPLEFT", 22, Y_SUM - 18 - (i - 1) * 15)
    line:SetWidth(W - 44)
    f.summoners[i] = line
  end

  -- Queue
  f.queueHdr = section(f, "Queue", Y_QUEUE)
  rows = {}
  for i = 1, ROWS do rows[i] = buildRow(i) end
  f.empty = fs(f, "GameFontDisable"); f.empty:SetPoint("TOPLEFT", 22, Y_ROWS - 2)
  f.more = fs(f, "GameFontDisableSmall"); f.more:SetPoint("TOPLEFT", 22, Y_ROWS - ROWS * ROW_H - 2)

  -- Footer
  adBtn = button(f, "Advertise", 190, 24)
  adBtn:SetPoint("BOTTOMRIGHT", -32, 12)
  adBtn:SetScript("OnClick", function() ns:Advertise() end)
  adGear = gear(f, function() togglePanel(adPanel) end)
  adGear:SetPoint("LEFT", adBtn, "RIGHT", 6, 0)
  f.earnings = fs(f, "GameFontHighlightSmall")
  f.earnings:SetPoint("BOTTOMLEFT", 14, 12)
  f.earnings:SetPoint("RIGHT", adBtn, "LEFT", -10, 0)
  f.earnings:SetJustifyV("BOTTOM")

  f:SetShown(ns.db.ui.shown ~= false)
end

---------------------------------------------------------------------------
-- Leader: summoner picker
---------------------------------------------------------------------------
local PICK_ROWS = 12

local function buildSummonerPanel()
  sumPanel = sidePanel("Summoners")
  local sub = fs(sumPanel, "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 14, -34)
  sub:SetWidth(262)
  sub:SetText("Tick everyone summoning with you. Ticking someone also gives them assist so they can invite customers.")
  sumPanel.empty = fs(sumPanel, "GameFontDisable")
  sumPanel.empty:SetPoint("TOPLEFT", 14, -82)
  sumPanel.empty:SetWidth(262)
  sumPanel.checks = {}
  for i = 1, PICK_ROWS do
    local cb = checkbox(sumPanel)
    cb:SetPoint("TOPLEFT", 12, -76 - (i - 1) * 24)
    cb:SetScript("OnClick", function(self)
      ns:SetSummoner(self.name, self:GetChecked())
    end)
    sumPanel.checks[i] = cb
  end
end

local function refreshSummonerPanel()
  if not sumPanel:IsShown() then return end
  local me = ns.Me()
  local people = ns:SummonerCandidates()

  if not IsInGroup() then
    sumPanel.empty:SetText("Invite the other summoners to your group, then tick them here.")
    sumPanel.empty:Show()
    for _, cb in ipairs(sumPanel.checks) do cb:Hide() end
    return
  end
  sumPanel.empty:Hide()

  for i, cb in ipairs(sumPanel.checks) do
    local name = people[i]
    if name then
      cb.name = name
      cb.label:SetText(ns.Short(name))
      cb:SetChecked(ns:IsSummoner(name))
      if name == me then
        cb:Disable()
        cb.hint:SetText("you (leader)")
      else
        cb:Enable()
        cb.hint:SetText(ns:HasAddon(name) and "" or c(ORANGE, "needs the addon"))
      end
      cb:Show()
    else
      cb:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Leader: advertising settings
---------------------------------------------------------------------------
local CHAN_ROWS = 7

local function buildAdPanel()
  adPanel = sidePanel("Advertising")

  -- Price
  section(adPanel, "Price", -38)
  local price = CreateFrame("EditBox", nil, adPanel, "InputBoxTemplate")
  price:SetSize(70, 20)
  price:SetPoint("TOPLEFT", 20, -54)
  price:SetAutoFocus(false)
  local function applyPrice(self)
    local copper = ns.ParseMoney(self:GetText())
    if copper and copper > 0 then
      ns.db.price = copper
      ns:Do("PRICE", { price = copper })
    end
    self:ClearFocus()
    ns:Refresh()
  end
  price:SetScript("OnEnterPressed", applyPrice)
  price:SetScript("OnEditFocusLost", function(self)
    local copper = ns.ParseMoney(self:GetText())
    if copper and copper > 0 and copper ~= ns.S.price then applyPrice(self) else ns:Refresh() end
  end)
  price:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns:Refresh() end)
  adPanel.price = price
  local priceHint = fs(adPanel, "GameFontDisableSmall")
  priceHint:SetPoint("LEFT", price, "RIGHT", 10, 0)
  priceHint:SetText("e.g. 30s, 1g, 1g 50s")

  -- Channels
  section(adPanel, "Post to", -86)
  adPanel.checks = {}
  for i = 1, CHAN_ROWS do
    local cb = checkbox(adPanel)
    cb:SetPoint("TOPLEFT", 12, -102 - (i - 1) * 22)
    cb:SetScript("OnClick", function(self)
      ns:SetAdChannel(self.channel, self:GetChecked())
      ns:Refresh()
    end)
    adPanel.checks[i] = cb
  end
  adPanel.noChan = fs(adPanel, "GameFontDisable")
  adPanel.noChan:SetPoint("TOPLEFT", 16, -106)
  adPanel.noChan:SetText("You haven't joined any chat channels.")

  -- Message: a multi-line text block (wraps instead of scrolling sideways)
  local y = -102 - CHAN_ROWS * 22 - 10
  section(adPanel, "Message", y)
  local holder = CreateFrame("Frame", nil, adPanel, "BackdropTemplate")
  holder:SetPoint("TOPLEFT", 14, y - 16)
  holder:SetSize(262, 70)
  holder:SetBackdrop(BACKDROP)
  holder:SetBackdropColor(0, 0, 0, 0.6)
  local box = CreateFrame("EditBox", nil, holder)
  box:SetMultiLine(true)
  box:SetFontObject(ChatFontNormal)
  box:SetPoint("TOPLEFT", 8, -7)
  box:SetPoint("BOTTOMRIGHT", -8, 7)
  box:SetAutoFocus(false)
  box:SetMaxLetters(200)
  box:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local text = self:GetText()
    local flat = text:gsub("[\r\n]", " ") -- chat messages are one line
    if flat ~= text then self:SetText(flat) end
    ns.db.adText = flat
    ns:Refresh()
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() box:SetFocus() end)
  adPanel.box = box
  local hint = fs(adPanel, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 16, y - 92)
  hint:SetText("{city}, {price} and {queue} fill in automatically.")

  -- Preview
  section(adPanel, "Preview", y - 114)
  adPanel.preview = fs(adPanel, "GameFontHighlightSmall")
  adPanel.preview:SetPoint("TOPLEFT", 16, y - 130)
  adPanel.preview:SetWidth(262)
  adPanel.preview:SetJustifyV("TOP")
end

local function refreshAdPanel()
  if not adPanel:IsShown() then return end
  if not adPanel.price:HasFocus() then adPanel.price:SetText(ns.Money(ns.S.price)) end
  local chans = ns:JoinedChannels()
  adPanel.noChan:SetShown(#chans == 0)
  for i, cb in ipairs(adPanel.checks) do
    local ch = chans[i]
    if ch then
      cb.channel = ch.name
      cb.label:SetText(("%d. %s"):format(ch.id, ch.name))
      cb:SetChecked(ns:IsAdChannel(ch.name))
      cb:Show()
    else
      cb:Hide()
    end
  end
  if not adPanel.box:HasFocus() then adPanel.box:SetText(ns.db.adText) end
  adPanel.preview:SetText(c(YELLOW, ns:AdText()))
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local STATUS = {
  INVITED = function() return c(GREY, "invited") end,
  GROUP = function() return "waiting" end,
  SUMMONING = function(e, now)
    return c(PURPLE, ("%s summoning %s"):format(ns.Short(e.caster), ns.Clock(now - (e.castAt or now))))
  end,
  ARRIVED = function(e, now)
    local waited = now - (e.arrivedAt or now)
    if waited > ns.db.unpaidTimeout then return c(RED, "unpaid, owes " .. ns.Short(e.caster)) end
    return c(YELLOW, ("owes %s %s"):format(ns.Short(e.caster), ns.Clock(waited)))
  end,
  PAID = function(e) return c(GREEN, "paid " .. ns.Money(e.paid)) end,
}

local function refreshRow(r, i, e, now, me)
  local ro = ns.roster[e.name]
  local name = ns.Short(e.name)
  if ns:IsBlacklisted(e.name) then name = c(RED, name .. " (blacklisted)") end
  r.num:SetText(i)
  r.name:SetText(name)
  r.zone:SetText(ro and (ro.online and (ro.zone or "") or c(GREY, "offline")) or "")
  r.status:SetText(STATUS[e.status] and STATUS[e.status](e, now) or e.status)

  -- Edge-case actions only; the big button handles the normal flow.
  local label, fn
  if e.status == "ARRIVED" and e.caster == me and now - (e.arrivedAt or now) > ns.db.unpaidTimeout then
    label, fn = "Trade", function() ns:Trade(e.name) end
  elseif e.status == "INVITED" and ns:CanInvite() then
    label, fn = "Re-invite", function() ns:Reinvite(e.name) end
  end
  if label then
    r.btn:SetText(label)
    r.btn:SetScript("OnClick", fn)
    r.btn:Show()
  else
    r.btn:Hide()
  end
  r:Show()
end

function ns:Refresh()
  if not f or not f:IsShown() or not ns.S then return end
  local S, me, now = ns.S, ns.Me(), GetServerTime()
  local leader = self:IsLeader()

  -- Title + price (only the leader edits the price)
  local active = self:IsActive()
  f.title:SetText("Summon Circle  " .. c(GREY, GetRealZoneText() or ""))

  -- Status bar
  local host = ns.Short(self:AuthorityName())
  if active then
    f.status:SetBackdropColor(0.05, 0.30, 0.10, 0.95)
    f.status:SetBackdropBorderColor(0.25, 1, 0.35, 1)
    f.dot:SetColorTexture(0.25, 1, 0.35, 1)
    f.statusText:SetText(c(GREEN, "OPEN") .. "   " .. (leader and "Taking customers"
      or (host .. " is taking customers")))
  else
    f.status:SetBackdropColor(0.25, 0.06, 0.06, 0.95)
    f.status:SetBackdropBorderColor(0.6, 0.25, 0.25, 1)
    f.dot:SetColorTexture(1, 0.3, 0.3, 1)
    f.statusText:SetText(c(RED, "CLOSED") .. "   " .. (leader and "Not taking customers"
      or ("Waiting for " .. host .. " to open")))
  end
  f.toggle:SetShown(leader)
  f.toggle:SetText(active and "Close shop" or "Open for business")

  -- What-to-do box: dimmed while closed, green-edged while open
  f.banner:SetAlpha(active and 1 or 0.45)
  if active then
    f.banner:SetBackdropBorderColor(0.25, 1, 0.35, 1)
  else
    f.banner:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  end
  f.priceText:SetText(c(GREY, "Price ") .. ns.Money(S.price))

  -- Banner + big button
  local a = self:NextAction()
  f.bannerText:SetText(a.text)
  f.alt.fn = a.alt and a.alt.fn
  if a.alt then f.alt:SetText(a.alt.label); f.alt:Show() else f.alt:Hide() end
  if not InCombatLockdown() then
    if a.summon then
      big:SetAttribute("type", "macro")
      big:SetAttribute("macrotext", "/target " .. a.summon.unit .. "\n/cast " .. ns.SummonName())
      big.target, big.fn = a.summon.name, nil
    else
      big:SetAttribute("type", nil)
      big:SetAttribute("macrotext", nil)
      big.target, big.fn = nil, a.fn
    end
    big:ClearAllPoints()
    if a.alt then
      big:SetSize(W - 80 - 160, 28)
      big:SetPoint("BOTTOMLEFT", 20, 10)
    else
      big:SetSize(W - 80, 28)
      big:SetPoint("BOTTOM", 0, 10)
    end
    if a.label then big:SetText(a.label); big:Show() else big:Hide() end
  end

  -- Summoners
  sumGear:SetShown(leader and IsInGroup())
  local list = self:ActiveSummoners()
  local nextUp = self:NextUp()
  for i = 1, SUM_LINES do
    local line, n = f.summoners[i], list[i]
    if n then
      local shards = self:ShardsOf(n)
      local col = shards >= 20 and GREEN or shards >= 10 and YELLOW or shards >= 1 and ORANGE or RED
      local count = c(col, ("%d shard%s"):format(shards, shards == 1 and "" or "s"))
      local reason = self:LockReason(n)
      local name = ns.Short(n) .. (n == me and " (you)" or "")
      if reason then
        line:SetText(("%s  (%s)  %s"):format(c(GREY, name), count, c(GREY, reason)))
      elseif n == nextUp then
        line:SetText(("%s  (%s)  %s"):format(c(GREEN, name), count, c(GREEN, "next up")))
      else
        line:SetText(("%s  (%s)"):format(name, count))
      end
      line:Show()
    elseif i == 1 then
      line:SetText(c(GREY, "None yet. The leader picks summoners with the gear icon."))
      line:Show()
    else
      line:Hide()
    end
  end

  -- Queue
  local queue = self:SortedQueue()
  f.queueHdr:SetText(("QUEUE (%d)"):format(#queue))
  for i = 1, ROWS do
    if queue[i] then refreshRow(rows[i], i, queue[i], now, me) else rows[i]:Hide() end
  end
  f.empty:SetText(#queue == 0 and "Nobody in line." or "")
  f.more:SetText(#queue > ROWS and ("+%d more"):format(#queue - ROWS) or "")

  -- Footer: Advertise is leader-only
  adBtn:SetShown(leader and active)
  adGear:SetShown(leader)
  if leader then
    local label, enabled = self:AdButtonState()
    adBtn:SetText(label)
    adBtn:SetEnabled(enabled)
  else
    adPanel:Hide()
  end
  if not leader or not IsInGroup() then sumPanel:Hide() end

  local total, bits = 0, {}
  for _, n in ipairs(list) do
    local L = S.ledger[n]
    if L and L.copper > 0 then
      total = total + L.copper
      bits[#bits + 1] = ("%s %s"):format(ns.Short(n), ns.Money(L.copper))
    end
  end
  local hours = math.max((now - (S.sessionStart or now)) / 3600, 1 / 60)
  if #bits > 0 then
    f.earnings:SetText(("Earned: %s\n%s"):format(table.concat(bits, ", "),
      c(YELLOW, ns.Money(total / hours) .. "/hr")))
  else
    f.earnings:SetText(c(GREY, "Earned: nothing yet"))
  end

  refreshSummonerPanel()
  refreshAdPanel()
end

function ns:ToggleUI(show)
  if not f then
    return ns.Print("The window failed to load. Look for a red error line above and screenshot it.")
  end
  if InCombatLockdown() then return ns.Print("Can't open or close the window in combat.") end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
  ns.db.ui.shown = show
  self:Refresh()
end

ns:On("PLAYER_LOGIN", function()
  buildMain()
  buildSummonerPanel()
  buildAdPanel()
  ns:Refresh()
end)
