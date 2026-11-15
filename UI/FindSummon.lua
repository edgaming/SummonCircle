-- Summon Circle: the Find a Summon page (design doc 04). For everyone who
-- isn't a warlock this page *is* the addon; warlocks get it as a tab.
--
-- One row per open circle on your faction. Price and wait line up on the
-- right so circles are easy to compare. Click a row, then Get summoned.
--
--   Undercity                                              30(s)
--   Ash Lock's circle · 3 summoners                      4 waiting
local ADDON, ns = ...
local UI, Wd, Style = ns.UI, ns.Widgets, ns.Style
local c, GREY, GREEN, YELLOW, ORANGE = Wd.c, Wd.GREY, Wd.GREEN, Wd.YELLOW, Wd.ORANGE

local ROWS = 8
local ROW_H = 44
local Y_TOP = -60

local page = { key = "summon", label = "Find a Summon" }
local p -- the frame

page.selected = nil -- leader of the picked circle

-- Wait: green when there's none, yellow for a few, orange for a long line.
local function waitText(q)
  if q == 0 then return c(GREEN, "no wait") end
  return c(q >= 6 and ORANGE or YELLOW, q .. " waiting")
end

local function circleLine(l)
  local n = l.summoners or 0
  return ("%s's circle  ·  %d summoner%s"):format(ns.Short(l.leader), n, n == 1 and "" or "s")
end

local function showTooltip(row)
  local l = row.listing
  if not l or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(l.spot, 1, 1, 1)
  GameTooltip:AddLine(circleLine(l), 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Price", ns.Coins(l.price), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Waiting", tostring(l.queue or 0), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Get summoned whispers \"%s\" to %s. You pay after you arrive."):format(
    l.keyword or "inv", ns.Short((l.contacts and l.contacts[1]) or l.leader)), 0.7, 0.7, 0.7, true)
  GameTooltip:Show()
end

local function buildRow(i)
  local r = CreateFrame("Button", nil, p)
  r:SetSize(UI.W - 24, ROW_H)
  r:SetPoint("TOPLEFT", 12, Y_TOP - (i - 1) * ROW_H)
  Style.Hover(r)
  r.sel = Style.SelectedBand(r)
  r.edge = Style.AccentLine(r, "LEFT")
  r.spot = Wd.Text(r, "GameFontHighlight"); r.spot:SetPoint("TOPLEFT", 8, -6)
  r.circle = Wd.Text(r, "GameFontDisableSmall"); r.circle:SetPoint("TOPLEFT", 8, -24)
  r.price = Wd.Text(r, "GameFontHighlight", "RIGHT"); r.price:SetPoint("TOPRIGHT", -8, -6)
  r.wait = Wd.Text(r, "GameFontHighlightSmall", "RIGHT"); r.wait:SetPoint("TOPRIGHT", -8, -24)
  r:SetScript("OnClick", function() page.Select(r.leader) end)
  r:SetScript("OnEnter", showTooltip)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r:Hide()
  return r
end

function page.Build(parent, height)
  p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  Wd.Section(p, "Find a Summon", -38)
  p.count = Wd.Text(p, "GameFontDisableSmall", "RIGHT")
  p.count:SetPoint("TOPRIGHT", -16, -38)
  p.note = Wd.Text(p, "GameFontDisable")
  p.note:SetPoint("TOPLEFT", 16, -62)
  p.note:SetWidth(UI.W - 32)
  p.rows = {}
  for i = 1, ROWS do p.rows[i] = buildRow(i) end
  p.more = Wd.Text(p, "GameFontDisableSmall")
  p.more:SetPoint("TOPLEFT", 16, Y_TOP - ROWS * ROW_H - 2)
  p.get = Wd.Button(p, "Get summoned", 150, 24)
  p.get:SetPoint("BOTTOMRIGHT", -14, 12)
  p.get:SetScript("OnClick", function()
    if page.selected then ns.Summon.Request(page.selected) end
  end)
  p.hint = Wd.Text(p, "GameFontDisableSmall")
  p.hint:SetPoint("BOTTOMLEFT", 16, 18)
  p.hint:SetPoint("RIGHT", p.get, "LEFT", -10, 0)
  page.frame = p
  return p
end

function page.Select(leader)
  page.selected = leader
  ns.Update()
end

-- The line above the list: why it's empty, or where you stand.
local function note(count)
  local mine = ns.Summon.CurrentCircle()
  if mine then
    return ("You're in %s's queue in %s. Watch for the summon."):format(ns.Short(mine.leader), mine.spot)
  end
  if not ns.Net.Available() then
    return ns.Net.status == "failed" and "The network is unavailable (see /sc net)."
      or "Connecting to the network..."
  end
  if count > 0 then return nil end
  if ns.Listings.Waiting() then return "Waiting up to a minute for existing circles..." end
  return "No circles are open for business right now."
end

local function refreshRow(r, l)
  r.listing, r.leader = l, l.leader
  r.spot:SetText(l.short and ("%s (%s)"):format(l.spot, l.short) or l.spot)
  r.circle:SetText(circleLine(l))
  r.price:SetText(ns.Coins(l.price))
  r.wait:SetText(waitText(l.queue or 0))
  local picked = l.leader == page.selected
  r.sel:SetShown(picked)
  r.edge:SetShown(picked)
  r:Show()
end

local function refreshButton(list)
  local picked
  for _, l in ipairs(list) do
    if l.leader == page.selected then picked = l end
  end
  if not picked then page.selected = nil end
  local state = picked and ns.Summon.State(picked.leader) or (IsInGroup() and "in group" or "get")
  p.get:SetShown(#list > 0)
  p.get:SetText(state == "requested" and "Requested" or "Get summoned")
  p.get:SetEnabled(picked ~= nil and state == "get")
  if state == "in group" then
    p.hint:SetText("Leave your group first: a circle invites you into theirs.")
  elseif state == "requested" then
    p.hint:SetText("Requested. Accept the invite when it comes.")
  elseif #list > 0 and not picked then
    p.hint:SetText("Pick a circle, then Get summoned.")
  else
    p.hint:SetText("")
  end
end

function page.Refresh()
  local list = ns.Summon.CurrentCircle() and {} or ns.Listings.Open()
  local msg = note(#list)
  p.note:SetText(msg or "")
  p.note:SetShown(msg ~= nil)
  p.count:SetText(#list > 0 and ("%d open circle%s"):format(#list, #list == 1 and "" or "s") or "")
  local shift = msg and 22 or 0
  for i, r in ipairs(p.rows) do
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 12, Y_TOP - shift - (i - 1) * ROW_H)
    local l = list[i]
    if l and (i < ROWS or not msg) then refreshRow(r, l) else r:Hide() end
  end
  local shown = msg and (ROWS - 1) or ROWS
  p.more:SetText(#list > shown and ("+%d more"):format(#list - shown) or "")
  refreshButton(list)
end

UI.AddPage(page)
