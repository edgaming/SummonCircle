-- Summon Circle: the Find a Circle page (warlocks only; design doc 03).
--
-- One row per circle looking for summoners. Click a row to pick it, then
-- Ask to join at the bottom; there's no button on the rows themselves.
--
--   Ash Lock                                     [lock][lock][ ]
--   Undercity                                   260 summons left
--   30(s) · 4 waiting
--
-- The slots on the right show the circle's summoners (warlock icons) and
-- its open places (faint icons). Hover a row for each summoner's shards.
local ADDON, ns = ...
local UI, Wd = ns.UI, ns.Widgets
local c, GREY, GREEN, YELLOW, ORANGE = Wd.c, Wd.GREY, Wd.GREEN, Wd.YELLOW, Wd.ORANGE

local ROWS = 7
local ROW_H = 54
local Y_TOP = -60
local SLOT = 22
local WARLOCK_ICON = "Interface\\Icons\\ClassIcon_Warlock"

local page = { key = "find", label = "Find a Circle" }
local p -- the frame

page.selected = nil -- leader of the picked circle

local function shardColor(n)
  return n >= 20 and GREEN or n >= 10 and YELLOW or ORANGE
end

-- Hovering a row: who's in the circle and their shards.
local function showTooltip(row)
  local l = row.listing
  if not l or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.Short(l.leader) .. "'s circle", 1, 0.82, 0)
  GameTooltip:AddLine(l.spot, 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")
  for _, s in ipairs(l.shards) do
    GameTooltip:AddDoubleLine(ns.Short(s.n), c(shardColor(s.s), ("%d shards"):format(s.s)), 1, 1, 1)
  end
  for _ = #l.shards + 1, (l.wanted or 3) do
    GameTooltip:AddLine("Open spot", 0.5, 0.5, 0.5)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Price", ns.Coins(l.price), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Waiting", tostring(l.queue or 0), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:Show()
end

local function buildRow(i)
  local r = CreateFrame("Button", nil, p)
  r:SetSize(UI.W - 24, ROW_H)
  r:SetPoint("TOPLEFT", 12, Y_TOP - (i - 1) * ROW_H)
  -- Picked: a soft purple band, like the "what to do now" box.
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  r.sel:SetColorTexture(0.30, 0.14, 0.42, 0.55)
  r.sel:Hide()
  r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  r.name = Wd.Text(r, "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 6, -5)
  r.spot = Wd.Text(r, "GameFontDisable"); r.spot:SetPoint("TOPLEFT", 6, -21)
  r.detail = Wd.Text(r, "GameFontHighlightSmall"); r.detail:SetPoint("TOPLEFT", 6, -37)
  r.slots = {}
  for k = 1, 3 do
    local t = r:CreateTexture(nil, "ARTWORK")
    t:SetSize(SLOT, SLOT)
    t:SetTexture(WARLOCK_ICON)
    t:SetPoint("TOPRIGHT", -6 - (3 - k) * (SLOT + 4), -5)
    r.slots[k] = t
  end
  r.left = Wd.Text(r, "GameFontHighlightSmall", "RIGHT"); r.left:SetPoint("TOPRIGHT", -6, -33)
  r:SetScript("OnClick", function() page.Select(r.leader) end)
  r:SetScript("OnEnter", showTooltip)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  r:Hide()
  return r
end

function page.Build(parent, height)
  p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  Wd.Section(p, "Find a Circle", -38)
  p.count = Wd.Text(p, "GameFontDisableSmall", "RIGHT")
  p.count:SetPoint("TOPRIGHT", -16, -38)
  p.note = Wd.Text(p, "GameFontDisable")
  p.note:SetPoint("TOPLEFT", 16, -62)
  p.note:SetWidth(UI.W - 32)
  p.rows = {}
  for i = 1, ROWS do p.rows[i] = buildRow(i) end
  p.more = Wd.Text(p, "GameFontDisableSmall")
  p.more:SetPoint("TOPLEFT", 16, Y_TOP - ROWS * ROW_H - 2)
  -- The one action, for the picked row.
  p.ask = Wd.Button(p, "Ask to join", 150, 24)
  p.ask:SetPoint("BOTTOMRIGHT", -14, 12)
  p.ask:SetScript("OnClick", function()
    if page.selected then ns.Recruit.Ask(page.selected) end
  end)
  p.hint = Wd.Text(p, "GameFontDisableSmall")
  p.hint:SetPoint("BOTTOMLEFT", 16, 18)
  page.frame = p
  return p
end

function page.Select(leader)
  page.selected = leader
  ns.Update()
end

-- Why the list is empty, or why it isn't shown at all.
local function note(count)
  if ns.Recruit.InACircle() then
    return "You're summoning in a circle. Leave the group to look for another one."
  end
  if not ns.Net.Available() then
    return ns.Net.status == "failed" and "The network is unavailable (see /sc net)."
      or "Connecting to the network..."
  end
  if count > 0 then return nil end
  if ns.Listings.Waiting() then return "Waiting up to a minute for existing circles..." end
  return "No circles are looking for summoners right now."
end

local function refreshRow(r, l)
  r.listing, r.leader = l, l.leader
  r.name:SetText(ns.Short(l.leader))
  r.spot:SetText(l.spot)
  local q = l.queue or 0
  r.detail:SetText(ns.Coins(l.price) .. c(GREY, "  ·  " .. (q == 0 and "nobody waiting" or (q .. " waiting"))))
  local wanted = l.wanted or 3
  for k, t in ipairs(r.slots) do
    t:SetShown(k <= wanted)
    local filled = k <= l.summoners
    t:SetDesaturated(not filled)
    t:SetAlpha(filled and 1 or 0.25)
  end
  local left = ns.Listings.SummonsLeft(l)
  r.left:SetText(c(shardColor(left), ("%d summons left"):format(left)))
  r.sel:SetShown(l.leader == page.selected)
  r:Show()
end

local function refreshAsk(list)
  local picked
  for _, l in ipairs(list) do
    if l.leader == page.selected then picked = l end
  end
  if not picked then page.selected = nil end
  local state = picked and ns.Recruit.RowState(picked.leader) or "ask"
  p.ask:SetShown(#list > 0)
  p.ask:SetText(state == "closed" and "Circle filled" or state == "asked" and "Asked" or "Ask to join")
  p.ask:SetEnabled(picked ~= nil and state == "ask")
  p.hint:SetText(#list > 0 and not picked and "Pick a circle, then Ask to join." or "")
end

function page.Refresh()
  local list = ns.Recruit.InACircle() and {} or ns.Listings.Recruiting()
  local msg = note(#list)
  p.note:SetText(msg or "")
  p.note:SetShown(msg ~= nil)
  p.count:SetText(#list > 0 and ("%d circle%s"):format(#list, #list == 1 and "" or "s") or "")
  -- A note pushes the rows down a little.
  local shift = msg and 22 or 0
  for i, r in ipairs(p.rows) do
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 12, Y_TOP - shift - (i - 1) * ROW_H)
    local l = list[i]
    if l and (i < ROWS or not msg) then refreshRow(r, l) else r:Hide() end
  end
  local shown = msg and (ROWS - 1) or ROWS
  p.more:SetText(#list > shown and ("+%d more"):format(#list - shown) or "")
  refreshAsk(list)
end

UI.AddPage(page)
