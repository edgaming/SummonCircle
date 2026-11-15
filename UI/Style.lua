-- Summon Circle: the style guide, in code (design doc 06).
--
-- Every colour has one job:
--   purple  "you are here": the selected tab, the active list, a picked row
--   gold    "look at this, something's new": a pulsing glow, a yellow label
--           (gold headings and button text are just WoW's own look)
--   band    hover, everywhere: a faint flat light band
--   status  green good, yellow attention, orange low, red problem, grey off
--
-- Buttons: red WoW buttons only for a screen's main action; actions on a
-- row are light text buttons. Icon buttons (the gears) keep the game's
-- own icon highlight.
--
-- Widgets get their colours and treatments from here, never their own
-- numbers, so a new screen can't drift without changing the guide.
local ADDON, ns = ...
local Style = ns:Module("Style")

-- Text colours, as hex for |cff...|r strings.
Style.hex = {
  WHITE = "ffffff", GREY = "808080",
  GREEN = "40ff40", YELLOW = "ffd100", ORANGE = "ff8000", RED = "ff4040",
  PURPLE = "b070ff",
}

-- Selected: the accent line/edge, and the band behind a picked row.
Style.ACCENT = { 0.69, 0.44, 1, 1 }
Style.SELECTED_BAND = { 0.30, 0.14, 0.42, 0.45 }
-- Hover: a faint flat band.
Style.HOVER = { 1, 1, 1, 0.07 }
-- New: gold.
Style.NEW = { 1, 0.82, 0 }

local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"

-- Hover band on a button (shown by the game while the mouse is over it).
function Style.Hover(button)
  local band = button:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints()
  band:SetColorTexture(unpack(Style.HOVER))
  button:SetHighlightTexture(band)
  return band
end

-- Selected: a band behind the whole frame (hidden until selected).
function Style.SelectedBand(frame)
  local t = frame:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(unpack(Style.SELECTED_BAND))
  t:Hide()
  return t
end

-- Selected: a thin accent line along one side ("LEFT" or "BOTTOM").
function Style.AccentLine(frame, side, size)
  local t = frame:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(unpack(Style.ACCENT))
  if side == "LEFT" then
    t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(2)
  else
    t:SetSize(size or 90, 2); t:SetPoint("BOTTOM", 0, 0)
  end
  t:Hide()
  return t
end

-- A soft glow (hidden until shown). kind = "selected" (purple) or "new" (gold).
function Style.Glow(frame, kind, layer)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(GLOW)
  t:SetBlendMode("ADD")
  if kind == "new" then
    t:SetVertexColor(Style.NEW[1], Style.NEW[2], Style.NEW[3], 1)
  else
    t:SetVertexColor(Style.ACCENT[1], Style.ACCENT[2], Style.ACCENT[3], 0.6)
  end
  t:Hide()
  return t
end

-- Make a glow breathe in and out (for "new").
function Style.Pulse(glow)
  local ag = glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(0.15)
  fade:SetToAlpha(0.9)
  fade:SetDuration(0.9)
  fade:SetSmoothing("IN_OUT")
  return ag
end

-- Shard counts and similar: green 20+, yellow 10+, orange 1+, red none.
function Style.CountColor(n)
  return n >= 20 and Style.hex.GREEN or n >= 10 and Style.hex.YELLOW
    or n >= 1 and Style.hex.ORANGE or Style.hex.RED
end
