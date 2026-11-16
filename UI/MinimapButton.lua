-- Summon Circle: ways to open the window besides /sc.
--   - a minimap button (drag it around the minimap's edge; button-collector
--     addons pick it up too)
--   - the game's addon menu on the minimap (addon compartment), via the .toc
-- Click either to show or hide the window. /sc minimap hides or shows the button.
local ADDON, ns = ...
local UI = ns.UI
local Mini = ns:Module("Minimap")

local ICON = "Interface\\AddOns\\SummonCircle\\Media\\icon"
local btn

-- One line on how the shop is doing, for the tooltip.
local function statusLine()
  if not ns.S then return nil end
  if not ns.Session.IsActive() then return "|cffff4040CLOSED|r" end
  return ("|cff40ff40OPEN|r  ·  %d in queue"):format(#ns.Queue.Waiting())
end

function Mini.Tooltip(owner)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine("Summon Circle", 0.58, 0.51, 0.79)
  local s = statusLine()
  if s then GameTooltip:AddLine(s) end
  GameTooltip:AddLine("Click to open or close.", 0.7, 0.7, 0.7)
  if owner == btn then GameTooltip:AddLine("Drag to move it around the minimap.", 0.7, 0.7, 0.7) end
  GameTooltip:Show()
end

local function place()
  local angle = math.rad(ns.db.minimap.angle or 225)
  local r = (Minimap:GetWidth() / 2) + 5
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- While dragging: follow the cursor around the minimap's edge.
local function follow()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  place()
end

function Mini.Build()
  if btn or not Minimap then return end
  ns.db.minimap = ns.db.minimap or {}
  btn = CreateFrame("Button", "SummonCircleMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  -- The standard round minimap-button look.
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  btn:SetScript("OnClick", function() UI.Toggle() end)
  btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", follow) end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  btn:SetScript("OnEnter", Mini.Tooltip)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  place()
  btn:SetShown(not ns.db.minimap.hide)
  Mini.button = btn
end

function Mini.SetShown(show)
  ns.db.minimap = ns.db.minimap or {}
  ns.db.minimap.hide = not show or nil
  if btn then btn:SetShown(show) end
end

-- The game's addon menu calls these (named in the .toc).
function SummonCircle_OnCompartmentClick() UI.Toggle() end
function SummonCircle_OnCompartmentEnter(_, frame) Mini.Tooltip(frame) end
function SummonCircle_OnCompartmentLeave() if GameTooltip then GameTooltip:Hide() end end

ns.On("PLAYER_LOGIN", function() Mini.Build() end)
