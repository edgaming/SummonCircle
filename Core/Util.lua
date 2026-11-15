-- Summon Circle: pure helpers (no WoW API calls), so they're unit-testable.
local ADDON, ns = ...

-- WoW Forever has no realms: names are unique "First Last". Strip any
-- "-Realm" suffix the game attaches so every name is a plain "First Last".
function ns.Full(name)
  if not name or name == "" then return nil end
  return (name:gsub("%-.*$", ""))
end

function ns.Short(name)
  return name and ns.Full(name) or "?"
end

-- 13500 -> "1g35s"
function ns.Money(c)
  c = math.floor(c or 0)
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if s > 0 then t[#t + 1] = s .. "s" end
  if cc > 0 or #t == 0 then t[#t + 1] = cc .. "c" end
  return table.concat(t)
end

-- 13500 -> "1 [gold] 35 [silver]" with the game's coin icons, for anything
-- shown on screen. Chat text (ads, whispers) uses Money(): icons don't
-- survive being sent.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function ns.Coins(c)
  c = math.floor(c or 0)
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. COIN:format("Gold") end
  if s > 0 then t[#t + 1] = s .. COIN:format("Silver") end
  if cc > 0 or #t == 0 then t[#t + 1] = cc .. COIN:format("Copper") end
  return table.concat(t, " ")
end

-- "30s", "1g 20s", "50" (plain number = silver) -> copper, or nil
function ns.ParseMoney(str)
  if not str then return nil end
  str = str:lower():gsub("%s", "")
  if str:match("^%d+$") then return tonumber(str) * 100 end
  local total, matched = 0, false
  for n, u in str:gmatch("(%d+)([gsc])") do
    total = total + tonumber(n) * (u == "g" and 10000 or u == "s" and 100 or 1)
    matched = true
  end
  return matched and total or nil
end

-- 75 -> "1:15"
function ns.Clock(sec)
  sec = math.max(0, math.floor(sec or 0))
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- Seconds between two server times -> "just now", "3h ago", "yesterday", "4 days ago"
function ns.Ago(then_, now)
  local d = (now or 0) - (then_ or 0)
  if d < 3600 then return "just now" end
  if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
  local days = math.floor(d / 86400)
  return days == 1 and "yesterday" or ("%d days ago"):format(days)
end
