-- Summon Circle: the Find a Circle page (warlocks only; design doc 03).
-- One plain list: a row per circle looking for summoners, one button per row.
--
--   Undercity (UC) · Ash Lock                              [Ask to join]
--   2/3 summoners · 30s · 4 waiting · 260 summons left
local ADDON, ns = ...
local UI, Wd = ns.UI, ns.Widgets
local c, GREY, GREEN, YELLOW, ORANGE = Wd.c, Wd.GREY, Wd.GREEN, Wd.YELLOW, Wd.ORANGE

local ROWS = 10
local ROW_H = 36
local page = { key = "find", label = "Find a Circle" }
local p -- the frame

local function shardColor(n)
  return n >= 20 and GREEN or n >= 10 and YELLOW or ORANGE
end

-- Hovering a row shows each summoner's shards.
local function showTooltip(row)
  local l = row.listing
  if not l or not GameTooltip then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.Short(l.leader) .. "'s circle")
  for _, s in ipairs(l.shards) do
    GameTooltip:AddDoubleLine(ns.Short(s.n), ("%d shards"):format(s.s), 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:Show()
end

local function buildRow(i)
  local r = CreateFrame("Frame", nil, p)
  r:SetSize(UI.W - 28, ROW_H)
  r:SetPoint("TOPLEFT", 14, -62 - (i - 1) * ROW_H)
  r:EnableMouse(true)
  r.top = Wd.Text(r, "GameFontHighlight"); r.top:SetPoint("TOPLEFT", 0, -2); r.top:SetWidth(UI.W - 140)
  r.sub = Wd.Text(r, "GameFontHighlightSmall"); r.sub:SetPoint("TOPLEFT", 0, -18); r.sub:SetWidth(UI.W - 140)
  r.btn = Wd.Button(r, "Ask to join", 100, 22); r.btn:SetPoint("RIGHT", 0, 0)
  r.btn:SetScript("OnClick", function() ns.Recruit.Ask(r.leader) end)
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
  p.note:SetPoint("TOPLEFT", 16, -64)
  p.note:SetWidth(UI.W - 32)
  p.rows = {}
  for i = 1, ROWS do p.rows[i] = buildRow(i) end
  p.more = Wd.Text(p, "GameFontDisableSmall")
  p.more:SetPoint("TOPLEFT", 16, -62 - ROWS * ROW_H - 2)
  page.frame = p
  return p
end

local function rowText(l)
  local spot = l.short and ("%s (%s)"):format(l.spot, l.short) or l.spot
  local left = ns.Listings.SummonsLeft(l)
  return ("%s  %s  %s"):format(spot, c(GREY, "·"), ns.Short(l.leader)),
    c(GREY, ("%d/%d summoners  ·  %s  ·  %d waiting  ·  "):format(
      l.summoners, l.wanted or 3, ns.Money(l.price), l.queue or 0))
      .. c(shardColor(left), ("%d summons left"):format(left))
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

function page.Refresh()
  local list = ns.Recruit.InACircle() and {} or ns.Listings.Recruiting()
  local msg = note(#list)
  p.note:SetText(msg or "")
  p.note:SetShown(msg ~= nil)
  p.count:SetText(#list > 0 and ("%d circle%s"):format(#list, #list == 1 and "" or "s") or "")
  local top = msg and 1 or 0 -- leave room for the note line
  for i, r in ipairs(p.rows) do
    local l = list[i - top]
    if l and i > top then
      r.listing, r.leader = l, l.leader
      r.top:SetText(select(1, rowText(l)))
      r.sub:SetText(select(2, rowText(l)))
      local state = ns.Recruit.RowState(l.leader)
      r.btn:SetText(state == "closed" and "Circle filled" or state == "asked" and "Asked" or "Ask to join")
      r.btn:SetEnabled(state == "ask")
      r:Show()
    else
      r:Hide()
    end
  end
  local shown = math.max(0, ROWS - top)
  p.more:SetText(#list > shown and ("+%d more"):format(#list - shown) or "")
end

UI.AddPage(page)
