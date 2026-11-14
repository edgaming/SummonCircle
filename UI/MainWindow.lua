-- Summon Circle: the window.
--
-- Layout, top to bottom:
--   title + price
--   status bar: OPEN / CLOSED + the leader's on/off toggle
--   banner: what to do now + one big button
--   summoners (leader: gear opens the picker)
--   queue
--   footer: earnings, Advertise (leader only; gear opens ad settings)
--
-- Side panels (summoner picker, ad settings) live in their own files and
-- register with UI.AddPanel.
local ADDON, ns = ...
local UI = ns:Module("UI")
local Wd = ns.Widgets
local c, GREY, GREEN, YELLOW, ORANGE, RED, PURPLE =
  Wd.c, Wd.GREY, Wd.GREEN, Wd.YELLOW, Wd.ORANGE, Wd.RED, Wd.PURPLE

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

UI.W, UI.H = W, H

local f, rows, big, adBtn, adGear, sumGear

---------------------------------------------------------------------------
-- Side panels: { frame, Build(), Refresh(), Allowed() }
-- Allowed() says whether the panel may be open right now (e.g. leader only).
---------------------------------------------------------------------------
UI.panels = {}

function UI.AddPanel(key, panel)
  UI.panels[key] = panel
  UI.panels[#UI.panels + 1] = panel
end

-- Open one panel (closing the others), or close it if it's open.
function UI.TogglePanel(key)
  local p = UI.panels[key]
  if not p or not p.frame then return end
  local show = not p.frame:IsShown()
  for _, other in ipairs(UI.panels) do
    if other.frame then other.frame:Hide() end
  end
  p.frame:SetShown(show)
  UI.Refresh()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function buildRow(i)
  local r = CreateFrame("Frame", nil, f)
  r:SetSize(W - 28, ROW_H)
  r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, Y_ROWS - (i - 1) * ROW_H)
  r.num = Wd.Text(r); r.num:SetPoint("LEFT", 0, 0); r.num:SetWidth(16)
  r.name = Wd.Text(r); r.name:SetPoint("LEFT", 18, 0); r.name:SetWidth(110)
  r.zone = Wd.Text(r); r.zone:SetPoint("LEFT", 130, 0); r.zone:SetWidth(120)
  r.status = Wd.Text(r); r.status:SetPoint("LEFT", 252, 0); r.status:SetWidth(120)
  r.btn = Wd.Button(r, "", 58, 18); r.btn:SetPoint("RIGHT", 0, 0)
  return r
end

local function buildActionButton()
  -- One secure button for every action. For a summon it runs a macro;
  -- for everything else it runs our function in PostClick.
  -- It can cast spells, which makes it "protected": WoW won't let addons
  -- show or hide it (or any window containing it) during combat. So it is
  -- NOT a child of the window: it floats on top of the banner, hides
  -- itself as combat starts, and the window can open/close any time.
  big = CreateFrame("Button", "SummonCircleActionButton", UIParent,
    "SecureActionButtonTemplate,UIPanelButtonTemplate")
  big:SetSize(W - 80, 28)
  big:SetFrameStrata(f:GetFrameStrata())
  big:SetFrameLevel(f:GetFrameLevel() + 20)
  big:Hide()
  big:RegisterForClicks("AnyUp", "AnyDown")
  local function isRealPress(down) return down == GetCVarBool("ActionButtonUseKeyDown") end
  big:SetScript("PreClick", function(self, _, down)
    if isRealPress(down) then ns.Queue.pendingTarget = self.target end
  end)
  big:SetScript("PostClick", function(self, _, down)
    if isRealPress(down) and self.fn then self.fn() end
  end)
end

function UI.Build()
  f = CreateFrame("Frame", "SummonCircleFrame", UIParent, "BackdropTemplate")
  UI.frame = f
  f:SetSize(W, H)
  f:SetBackdrop(Wd.BACKDROP)
  f:SetBackdropColor(0.06, 0.02, 0.09, 0.92)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    self:StartMoving()
    self:SetScript("OnUpdate", function() UI.PlaceActionButton() end)
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
    local p, _, rp, x, y = self:GetPoint()
    ns.db.ui.pos = { p, rp, x, y }
    UI.PlaceActionButton()
  end)
  -- The action button isn't part of the window, so hide it too.
  f:SetScript("OnHide", function()
    if big and not InCombatLockdown() then big:Hide() end
  end)
  local pos = ns.db.ui.pos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end

  -- Title + price
  f.title = Wd.Text(f, "GameFontNormal"); f.title:SetPoint("TOPLEFT", 14, -12)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() UI.Toggle(false) end)
  f.priceText = Wd.Text(f, "GameFontHighlight", "RIGHT")
  f.priceText:SetPoint("TOPRIGHT", -36, -13)

  -- Status bar: OPEN / CLOSED, colour-coded, with the one on/off toggle.
  local status = CreateFrame("Frame", nil, f, "BackdropTemplate")
  status:SetPoint("TOPLEFT", 10, Y_STATUS)
  status:SetPoint("TOPRIGHT", -10, Y_STATUS)
  status:SetHeight(STATUS_H)
  status:SetBackdrop(Wd.BACKDROP)
  f.status = status
  f.dot = status:CreateTexture(nil, "OVERLAY")
  f.dot:SetSize(10, 10)
  f.dot:SetPoint("LEFT", 12, 0)
  f.statusText = Wd.Text(status, "GameFontHighlight")
  f.statusText:SetPoint("LEFT", f.dot, "RIGHT", 8, 0)
  f.toggle = Wd.Button(status, "Open for business", 150, 22)
  f.toggle:SetPoint("RIGHT", -5, 0)
  f.toggle:SetScript("OnClick", function()
    if ns.Session.IsActive() then ns.Session.Stop() else ns.Session.Start() end
  end)

  -- Banner: what to do now + the big button
  local banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.banner = banner
  banner:SetPoint("TOPLEFT", 10, Y_BANNER)
  banner:SetPoint("TOPRIGHT", -10, Y_BANNER)
  banner:SetHeight(BANNER_H)
  banner:SetBackdrop(Wd.BACKDROP)
  banner:SetBackdropColor(0.18, 0.08, 0.26, 0.9)
  f.bannerText = Wd.Text(banner, "GameFontHighlight", "CENTER")
  f.bannerText:SetPoint("TOPLEFT", 10, -10)
  f.bannerText:SetPoint("TOPRIGHT", -10, -10)
  buildActionButton()
  -- Secondary choice (e.g. "Kick + blacklist") shown beside the big button.
  f.alt = Wd.Button(banner, "", 150, 28)
  f.alt:SetPoint("BOTTOMRIGHT", -20, 10)
  f.alt:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
  f.alt:Hide()

  -- Summoners
  Wd.Section(f, "Summoners", Y_SUM)
  sumGear = Wd.Gear(f, function() UI.TogglePanel("summoners") end)
  sumGear:SetPoint("TOPLEFT", 92, Y_SUM + 2)
  f.summoners = {}
  for i = 1, SUM_LINES do
    local line = Wd.Text(f, "GameFontHighlight")
    line:SetPoint("TOPLEFT", 22, Y_SUM - 18 - (i - 1) * 15)
    line:SetWidth(W - 44)
    f.summoners[i] = line
  end

  -- Queue
  f.queueHdr = Wd.Section(f, "Queue", Y_QUEUE)
  rows = {}
  for i = 1, ROWS do rows[i] = buildRow(i) end
  f.empty = Wd.Text(f, "GameFontDisable"); f.empty:SetPoint("TOPLEFT", 22, Y_ROWS - 2)
  f.more = Wd.Text(f, "GameFontDisableSmall"); f.more:SetPoint("TOPLEFT", 22, Y_ROWS - ROWS * ROW_H - 2)

  -- Footer
  adBtn = Wd.Button(f, "Advertise", 190, 24)
  adBtn:SetPoint("BOTTOMRIGHT", -32, 12)
  adBtn:SetScript("OnClick", function() ns.Advertise.Post() end)
  adGear = Wd.Gear(f, function() UI.TogglePanel("ad") end)
  adGear:SetPoint("LEFT", adBtn, "RIGHT", 6, 0)
  f.earnings = Wd.Text(f, "GameFontHighlightSmall")
  f.earnings:SetPoint("BOTTOMLEFT", 14, 12)
  f.earnings:SetPoint("RIGHT", adBtn, "LEFT", -10, 0)
  f.earnings:SetJustifyV("BOTTOM")

  f.sumGear, f.adBtn, f.adGear = sumGear, adBtn, adGear -- handles for tests
  f:SetShown(ns.db.ui.shown ~= false)

  for _, p in ipairs(UI.panels) do p.frame = p.Build(f, H) end
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
  local ro = ns.Roster.members[e.name]
  local name = ns.Short(e.name)
  if ns.Blacklist.Get(e.name) then name = c(RED, name .. " (blacklisted)") end
  r.num:SetText(i)
  r.name:SetText(name)
  r.zone:SetText(ro and (ro.online and (ro.zone or "") or c(GREY, "offline")) or "")
  r.status:SetText(STATUS[e.status] and STATUS[e.status](e, now) or e.status)

  -- Edge-case actions only; the big button handles the normal flow.
  local label, fn
  if e.status == "ARRIVED" and e.caster == me and now - (e.arrivedAt or now) > ns.db.unpaidTimeout then
    label, fn = "Trade", function() ns.Queue.Trade(e.name) end
  elseif e.status == "INVITED" and ns.Roster.CanInvite() then
    label, fn = "Re-invite", function() ns.Queue.Reinvite(e.name) end
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

local function refreshStatus(active, leader)
  local host = ns.Short(ns.Roster.GroupLeaderName() or ns.Sync.AuthorityName())
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
end

local function refreshBanner()
  local a = ns.Advisor.NextAction()
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
    big.withAlt = a.alt ~= nil
    big:SetSize(a.alt and (W - 240) or (W - 80), 28)
    UI.PlaceActionButton()
    if a.label then big:SetText(a.label); big:Show() else big:Hide() end
  elseif a.label then
    f.bannerText:SetText(a.text .. "\n" .. c(GREY, "Available after combat."))
  end
end

local function refreshSummoners(list, me)
  local nextUp = ns.Rotation.NextUp()
  for i = 1, SUM_LINES do
    local line, n = f.summoners[i], list[i]
    if n then
      local shards = ns.Rotation.ShardsOf(n)
      local col = shards >= 20 and GREEN or shards >= 10 and YELLOW or shards >= 1 and ORANGE or RED
      local count = c(col, ("%d shard%s"):format(shards, shards == 1 and "" or "s"))
      local reason = ns.Rotation.SkipReason(n)
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
end

local function refreshQueue(now, me)
  local queue = ns.Queue.Sorted()
  f.queueHdr:SetText(("QUEUE (%d)"):format(#queue))
  for i = 1, ROWS do
    if queue[i] then refreshRow(rows[i], i, queue[i], now, me) else rows[i]:Hide() end
  end
  f.empty:SetText(#queue == 0 and "Nobody in line." or "")
  f.more:SetText(#queue > ROWS and ("+%d more"):format(#queue - ROWS) or "")
end

local function refreshFooter(list, now, leader, active)
  adBtn:SetShown(leader and active)
  adGear:SetShown(leader)
  if leader then
    local label, enabled = ns.Advertise.ButtonState()
    adBtn:SetText(label)
    adBtn:SetEnabled(enabled)
  end
  local earned, _, perHour = ns.Ledger.Summary(list, now)
  if #earned > 0 then
    local bits = {}
    for _, e in ipairs(earned) do bits[#bits + 1] = ("%s %s"):format(ns.Short(e.name), ns.Money(e.copper)) end
    f.earnings:SetText(("Earned: %s\n%s"):format(table.concat(bits, ", "),
      c(YELLOW, ns.Money(perHour) .. "/hr")))
  else
    f.earnings:SetText(c(GREY, "Earned: nothing yet"))
  end
end

function UI.Refresh()
  if not f or not f:IsShown() or not ns.S then return end
  local me, now = ns.Me(), GetServerTime()
  local leader, active = ns.Roster.IsLeader(), ns.Session.IsActive()

  f.title:SetText("Summon Circle  " .. c(GREY, GetRealZoneText() or ""))
  f.priceText:SetText(c(GREY, "Price ") .. ns.Money(ns.S.price))
  refreshStatus(active, leader)
  refreshBanner()

  sumGear:SetShown(leader and IsInGroup())
  local list = ns.Session.ActiveSummoners()
  refreshSummoners(list, me)
  refreshQueue(now, me)
  refreshFooter(list, now, leader, active)

  for _, p in ipairs(UI.panels) do
    if p.frame then
      if not p.Allowed() then p.frame:Hide() end
      if p.frame:IsShown() then p.Refresh() end
    end
  end
end

ns.Listen("UPDATE", UI.Refresh)

-- Put the floating action button over the banner (out of combat only).
function UI.PlaceActionButton()
  if not f or not big or InCombatLockdown() then return end
  local left, bottom = f.banner:GetLeft(), f.banner:GetBottom()
  if not left or not bottom then return end
  local s = f.banner:GetEffectiveScale() / UIParent:GetEffectiveScale()
  big:ClearAllPoints()
  if big.withAlt then
    big:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (left + 20) * s, (bottom + 10) * s)
  else
    big:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (left + f.banner:GetWidth() / 2) * s, (bottom + 10) * s)
  end
end

-- Entering combat: last moment we may hide the protected button.
ns.On("PLAYER_REGEN_DISABLED", function() if big then big:Hide() end end)
ns.On("PLAYER_REGEN_ENABLED", function() UI.Refresh() end)

function UI.Toggle(show)
  if not f then
    return ns.Print("The window failed to load. Look for a red error line above and screenshot it.")
  end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
  ns.db.ui.shown = show
  UI.Refresh()
end

-- Built after every other file has loaded, so all panels have registered.
ns.On("PLAYER_LOGIN", function()
  UI.Build()
  UI.Refresh()
end)
