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

-- A text switch: labels side by side; the active one is underlined, and
-- hovering lights a label up. Switch(parent, segmentWidth, { "a", "b" }, onSelect)
--   sw:SetActive("a")            underline that label
--   sw:SetLabel("b", text)       set a label's text (colour it with c())
--   sw:SetPulse("b", true)       a soft glow breathes behind that label
--   sw.segments.a.text           the label's font string
function Widgets.Switch(parent, segWidth, keys, onSelect)
  local sw = CreateFrame("Frame", nil, parent)
  sw:SetSize(segWidth * #keys, 20)
  sw.segments = {}
  for i, key in ipairs(keys) do
    local seg = CreateFrame("Button", nil, sw)
    seg:SetSize(segWidth, 20)
    seg:SetPoint("LEFT", sw, "LEFT", (i - 1) * segWidth, 0)
    seg:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    seg.text = Widgets.Text(seg, "GameFontNormalSmall", "CENTER")
    seg.text:SetPoint("CENTER", 0, 1)
    seg.underline = seg:CreateTexture(nil, "ARTWORK")
    seg.underline:SetColorTexture(0.69, 0.44, 1, 1)
    seg.underline:SetSize(segWidth - 20, 2)
    seg.underline:SetPoint("BOTTOM", 0, 0)
    seg.underline:Hide()
    -- "Something new here": a soft glow that breathes in and out.
    seg.glow = seg:CreateTexture(nil, "BACKGROUND")
    seg.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    seg.glow:SetBlendMode("ADD")
    seg.glow:SetVertexColor(1, 0.82, 0, 1)
    seg.glow:SetSize(segWidth + 10, 34)
    seg.glow:SetPoint("CENTER", 0, 1)
    seg.glow:Hide()
    seg.pulse = seg.glow:CreateAnimationGroup()
    seg.pulse:SetLooping("BOUNCE")
    local fade = seg.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.15)
    fade:SetToAlpha(0.9)
    fade:SetDuration(0.9)
    fade:SetSmoothing("IN_OUT")
    seg:SetScript("OnClick", function() onSelect(key) end)
    sw.segments[key] = seg
  end
  function sw:SetActive(active)
    for key, seg in pairs(self.segments) do seg.underline:SetShown(key == active) end
  end
  function sw:SetPulse(key, on)
    local seg = self.segments[key]
    if on and not seg.pulse:IsPlaying() then
      seg.glow:Show(); seg.pulse:Play()
    elseif not on and seg.pulse:IsPlaying() then
      seg.pulse:Stop(); seg.glow:Hide()
    end
  end
  function sw:SetLabel(key, text)
    self.segments[key].text:SetText(text)
  end
  return sw
end

-- A standard WoW tab that hangs below a window. We only borrow the tab's
-- artwork: none of Blizzard's tab functions run, so tabs never change
-- shape or shift their text. Every tab keeps the unselected look; the
-- selected one keeps the tab's own hover glow lit and has white text.
--   tab:SetSelected(true|false)
function Widgets.WindowTab(parent, name, label, onClick)
  local t = CreateFrame("Button", name, parent, "PanelTabButtonTemplate")
  t:SetText(label)
  t:SetSize(115, 32)
  t:SetPushedTextOffset(0, 0) -- no "pressed in" text shift
  -- The template's own scripts select/deselect and resize the tab; ours
  -- only switches pages.
  t:SetScript("OnShow", nil)
  t:SetScript("OnEvent", nil)
  t:SetScript("OnClick", onClick)
  local fs = t:GetFontString()
  if fs then
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", 0, 2)
  end
  function t:SetSelected(on)
    if self.selected == on then return end
    self.selected = on
    if on then self:LockHighlight() else self:UnlockHighlight() end
    local text = self:GetFontString()
    if text then
      if on then text:SetTextColor(1, 1, 1) else text:SetTextColor(1, 0.82, 0) end
    end
  end
  return t
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
