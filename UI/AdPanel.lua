-- Summon Circle: the leader's advertising settings (gear next to Advertise):
-- price, channels to post to, the message, and a live preview.
local ADDON, ns = ...
local UI, Wd = ns.UI, ns.Widgets

local CHAN_ROWS = 7
local panel = {}
local p -- the frame

function panel.Allowed()
  return ns.Roster.IsLeader()
end

local function buildPrice()
  Wd.Section(p, "Price", -38)
  local price = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  price:SetSize(70, 20)
  price:SetPoint("TOPLEFT", 20, -54)
  price:SetAutoFocus(false)
  local function apply(self)
    local copper = ns.ParseMoney(self:GetText())
    if copper and copper > 0 then ns.Session.SetPrice(copper) end
    self:ClearFocus()
    ns.Update()
  end
  price:SetScript("OnEnterPressed", apply)
  price:SetScript("OnEditFocusLost", function(self)
    local copper = ns.ParseMoney(self:GetText())
    if copper and copper > 0 and copper ~= ns.S.price then apply(self) else ns.Update() end
  end)
  price:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.Update() end)
  p.price = price
  local hint = Wd.Text(p, "GameFontDisableSmall")
  hint:SetPoint("LEFT", price, "RIGHT", 10, 0)
  hint:SetText("e.g. 30s, 1g, 1g 50s")
end

local function buildChannels()
  Wd.Section(p, "Post to", -86)
  p.checks = {}
  for i = 1, CHAN_ROWS do
    local cb = Wd.Checkbox(p)
    cb:SetPoint("TOPLEFT", 12, -102 - (i - 1) * 21)
    cb:SetScript("OnClick", function(self)
      ns.Advertise.SetChannel(self.channel, self:GetChecked())
      ns.Update()
    end)
    p.checks[i] = cb
  end
  p.noChan = Wd.Text(p, "GameFontDisable")
  p.noChan:SetPoint("TOPLEFT", 16, -106)
  p.noChan:SetText("You haven't joined any chat channels.")
end

-- Everything below the channel list sits in one frame that moves up or
-- down with the number of channels, so there's never a gap.
local function buildListen(lower)
  Wd.Section(lower, "Listen", 0)
  local read = Wd.Checkbox(lower)
  read:SetPoint("TOPLEFT", 12, -16)
  read.label:SetText("Watch for summon requests")
  read:SetScript("OnClick", function(self)
    ns.db.readRequests = self:GetChecked() and true or false
    ns.Update()
  end)
  p.read = read
  p.readHint = Wd.Text(lower, "GameFontDisableSmall")
  p.readHint:SetPoint("TOPLEFT", 38, -40)
  p.readHint:SetWidth(240)
end

-- A multi-line text block (wraps instead of scrolling sideways), then the preview.
local function buildMessage(lower)
  local y = -70
  Wd.Section(lower, "Message", y)
  local holder = CreateFrame("Frame", nil, lower, "BackdropTemplate")
  holder:SetPoint("TOPLEFT", 14, y - 16)
  holder:SetSize(262, 70)
  holder:SetBackdrop(Wd.BACKDROP)
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
    ns.Update()
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() box:SetFocus() end)
  p.box = box
  local hint = Wd.Text(lower, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 16, y - 92)
  hint:SetText("{city}, {price} and {queue} fill in automatically.")

  Wd.Section(lower, "Preview", y - 114)
  p.preview = Wd.Text(lower, "GameFontHighlightSmall")
  p.preview:SetPoint("TOPLEFT", 16, y - 130)
  p.preview:SetWidth(262)
  p.preview:SetJustifyV("TOP")
end

function panel.Build(anchor, height)
  p = Wd.SidePanel(anchor, "Advertising", height)
  buildPrice()
  buildChannels()
  p.lower = CreateFrame("Frame", nil, p)
  p.lower:SetSize(290, 300)
  buildListen(p.lower)
  buildMessage(p.lower)
  return p
end

function panel.Refresh()
  if not p.price:HasFocus() then p.price:SetText(ns.Money(ns.S.price)) end
  local chans = ns.Advertise.JoinedChannels()
  p.noChan:SetShown(#chans == 0)
  for i, cb in ipairs(p.checks) do
    local ch = chans[i]
    if ch then
      cb.channel = ch.name
      cb.label:SetText(("%d. %s"):format(ch.id, ch.label))
      cb:SetChecked(ns.Advertise.IsChannel(ch.name))
      cb:Show()
    else
      cb:Hide()
    end
  end
  -- The lower half starts right under the last channel.
  local shown = math.max(1, math.min(#chans, CHAN_ROWS))
  p.lower:ClearAllPoints()
  p.lower:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -102 - shown * 21 - 8)

  -- Listening needs at least one ticked channel; until then it's greyed out.
  local any = #ns.Advertise.Channels() > 0
  p.read:SetChecked(any and ns.db.readRequests ~= false)
  p.read:SetEnabled(any)
  p.read.label:SetText(Wd.c(any and "ffffff" or Wd.GREY, "Watch for summon requests"))
  p.readHint:SetText(any and "Players asking for a summon to your city in these channels show up under Requests."
    or "Tick a channel above to watch it for summon requests.")
  if not p.box:HasFocus() then p.box:SetText(ns.db.adText) end
  p.preview:SetText(Wd.c(Wd.YELLOW, ns.Advertise.Text()))
end

UI.AddPanel("ad", panel)
