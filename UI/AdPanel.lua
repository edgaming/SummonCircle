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
    cb:SetPoint("TOPLEFT", 12, -102 - (i - 1) * 22)
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

-- A multi-line text block (wraps instead of scrolling sideways), then the preview.
local function buildMessage()
  local y = -102 - CHAN_ROWS * 22 - 10
  Wd.Section(p, "Message", y)
  local holder = CreateFrame("Frame", nil, p, "BackdropTemplate")
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
  local hint = Wd.Text(p, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 16, y - 92)
  hint:SetText("{city}, {price} and {queue} fill in automatically.")

  Wd.Section(p, "Preview", y - 114)
  p.preview = Wd.Text(p, "GameFontHighlightSmall")
  p.preview:SetPoint("TOPLEFT", 16, y - 130)
  p.preview:SetWidth(262)
  p.preview:SetJustifyV("TOP")
end

function panel.Build(anchor, height)
  p = Wd.SidePanel(anchor, "Advertising", height)
  buildPrice()
  buildChannels()
  buildMessage()
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
      cb.label:SetText(("%d. %s"):format(ch.id, ch.name))
      cb:SetChecked(ns.Advertise.IsChannel(ch.name))
      cb:Show()
    else
      cb:Hide()
    end
  end
  if not p.box:HasFocus() then p.box:SetText(ns.db.adText) end
  p.preview:SetText(Wd.c(Wd.YELLOW, ns.Advertise.Text()))
end

UI.AddPanel("ad", panel)
