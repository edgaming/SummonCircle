-- Summon Circle: the leader's summoner picker (gear next to SUMMONERS).
local ADDON, ns = ...
local UI, Wd = ns.UI, ns.Widgets

local PICK_ROWS = 12
local panel = {}
local p -- the frame

function panel.Allowed()
  return ns.Roster.IsLeader() and IsInGroup()
end

function panel.Build(anchor, height)
  p = Wd.SidePanel(anchor, "Summoners", height)
  local sub = Wd.Text(p, "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 14, -34)
  sub:SetWidth(262)
  sub:SetText("Tick everyone summoning with you. Ticking someone also gives them assist so they can invite customers.")
  p.empty = Wd.Text(p, "GameFontDisable")
  p.empty:SetPoint("TOPLEFT", 14, -82)
  p.empty:SetWidth(262)
  p.checks = {}
  for i = 1, PICK_ROWS do
    local cb = Wd.Checkbox(p)
    cb:SetPoint("TOPLEFT", 12, -76 - (i - 1) * 24)
    cb:SetScript("OnClick", function(self)
      ns.Session.SetSummoner(self.name, self:GetChecked())
    end)
    p.checks[i] = cb
  end
  return p
end

function panel.Refresh()
  local me = ns.Me()
  local people = ns.Session.Candidates()

  if not IsInGroup() then
    p.empty:SetText("Invite the other summoners to your group, then tick them here.")
    p.empty:Show()
    for _, cb in ipairs(p.checks) do cb:Hide() end
    return
  end
  p.empty:Hide()

  for i, cb in ipairs(p.checks) do
    local name = people[i]
    if name then
      cb.name = name
      cb.label:SetText(ns.Short(name))
      cb:SetChecked(ns.Session.IsSummoner(name))
      if name == me then
        cb:Disable()
        cb.hint:SetText("you (leader)")
      else
        cb:Enable()
        cb.hint:SetText(ns.Roster.HasAddon(name) and "" or Wd.c(Wd.ORANGE, "needs the addon"))
      end
      cb:Show()
    else
      cb:Hide()
    end
  end
end

UI.AddPanel("summoners", panel)
