-- Summon Circle: small widget helpers and colours shared by every panel.
local ADDON, ns = ...
local Widgets = ns:Module("Widgets")

Widgets.GREY, Widgets.GREEN, Widgets.YELLOW, Widgets.ORANGE, Widgets.RED, Widgets.PURPLE =
  "808080", "40ff40", "ffd100", "ff8000", "ff4040", "b070ff"

-- Colour a string: c(GREEN, "OPEN")
function Widgets.c(hex, text) return "|cff" .. hex .. text .. "|r" end

Widgets.BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Widgets.Text(parent, font, justify)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  s:SetJustifyH(justify or "LEFT")
  return s
end

function Widgets.Button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22)
  b:SetText(text)
  return b
end

function Widgets.Gear(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", onClick)
  return b
end

-- Checkbox with a label and a grey hint after it.
function Widgets.Checkbox(parent)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb.label = Widgets.Text(cb, "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.hint = Widgets.Text(cb, "GameFontDisableSmall")
  cb.hint:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)
  return cb
end

-- A flat text button used as one half of a switch ("QUEUE (4) | REQUESTS (2)").
function Widgets.Tab(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(110, 16)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetScript("OnClick", onClick)
  return b
end

-- Small gold heading: "SUMMONERS"
function Widgets.Section(parent, text, y, x)
  local s = Widgets.Text(parent, "GameFontNormalSmall")
  s:SetPoint("TOPLEFT", x or 14, y)
  s:SetText(text:upper())
  return s
end

-- A settings panel that opens beside `anchor`, same height.
function Widgets.SidePanel(anchor, title, height)
  local p = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
  p:SetSize(290, height)
  p:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
  p:SetBackdrop(Widgets.BACKDROP)
  p:SetBackdropColor(0.06, 0.02, 0.09, 0.95)
  p:EnableMouse(true)
  p.title = Widgets.Text(p, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 14, -12)
  p.title:SetText(title)
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  p:Hide()
  return p
end
