-- Summon Circle: slash commands. Everything day-to-day is in the window.
local ADDON, ns = ...

local HELP = {
  "/sc - show/hide the window",
  "/sc keywords inv,invite,summon,+ - whisper triggers",
  "/sc thanks <text> - whisper sent when you kick a paid customer",
  "/sc bl add First Last [reason] | bl del First Last | bl list",
  "/sc sound on|off - quiet sound for new summon requests from chat",
  "/sc reset - reset the session earnings",
  "/sc stats - lifetime earnings",
  "/sc net - is the network working?",
  "/sc demo - made-up circles and applicants to try the window alone",
  "/sc minimap - hide or show the minimap button",
}

local commands = {}

function commands.keywords(rest)
  local list = {}
  for k in rest:gmatch("[^,%s]+") do list[#list + 1] = k:lower() end
  if #list > 0 then ns.db.keywords = list end
  ns.Print("Keywords: " .. table.concat(ns.db.keywords, ", "))
end

function commands.thanks(rest)
  ns.db.thanks = rest
  ns.Print("Thanks message: " .. (rest ~= "" and rest or "(none)"))
end

function commands.bl(rest)
  -- Names are two words ("Ash Lock"); anything after is the reason.
  local sub, args = rest:match("^(%S*)%s*(.-)$")
  local first, last, reason = args:match("^(%S+)%s+(%S+)%s*(.-)$")
  local name = first and (first .. " " .. last)
  if sub == "add" and name then
    ns.Blacklist.Set(name, reason ~= "" and reason or nil)
    ns.Print("Blacklisted " .. name)
  elseif sub == "del" and name then
    ns.Blacklist.Set(name, nil, true)
    ns.Print("Removed " .. name .. " from the blacklist")
  elseif sub == "add" or sub == "del" then
    ns.Print("Use the full name, e.g. /sc bl " .. sub .. " Ash Lock")
  else
    local any = false
    ns.Blacklist.Each(function(n, e)
      any = true
      ns.Print(("%s - %s (%s)"):format(n, e.reason or "no reason", ns.Blacklist.Source(e)))
    end)
    if not any then ns.Print("Blacklist is empty.") end
  end
end

function commands.debug()
  local P, Roster = ns.Print, ns.Roster
  local inst = LE_PARTY_CATEGORY_INSTANCE
  P("version", C_AddOns.GetAddOnMetadata(ADDON, "Version"), "| me", ns.Me())
  P("name sources: UnitName [" .. tostring(UnitName("player")) .. "] GetUnitName ["
    .. tostring(GetUnitName("player", true)) .. "] UnitFullName [" .. tostring((UnitFullName("player"))) .. "]")
  P("in group", tostring(IsInGroup()), "| raid", tostring(IsInRaid()),
    "| dungeon-finder group", tostring(inst and IsInGroup(inst) or false))
  P("I'm leader: normal", tostring(UnitIsGroupLeader("player")),
    "| dungeon-finder", tostring(inst and UnitIsGroupLeader("player", inst) or false))
  for n, r in pairs(Roster.members) do
    P("  group:", n, "| rank", r.rank, "| has addon", tostring(Roster.HasAddon(n)))
  end
  for n in pairs(Roster.peers) do P("  addon heard from:", n) end
  P("queue holder", ns.Sync.AuthorityName(), "| summoners:",
    #ns.S.summoners > 0 and table.concat(ns.S.summoners, ", ") or "(none)")
end

function commands.sound(rest)
  rest = rest:lower()
  if rest == "on" or rest == "off" then ns.db.requestSound = rest == "on" end
  ns.Print("Sound for new requests: " .. (ns.db.requestSound and "on" or "off"))
end

function commands.net() ns.Print(ns.Net.Describe()) end

function commands.demo(rest) ns.Demo.Command(rest) end

function commands.minimap()
  local show = ns.db.minimap and ns.db.minimap.hide
  ns.Minimap.SetShown(show and true or false)
  ns.Print(show and "Minimap button shown." or "Minimap button hidden. /sc minimap brings it back.")
end

function commands.reset()
  ns.Sync.Do("RESET", {})
  ns.Print("Session earnings reset.")
end

function commands.stats()
  ns.Print(("Lifetime: %s from %d summons."):format(ns.Coins(ns.db.lifetime.copper), ns.db.lifetime.summons))
end

local function slash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.UI.Toggle()
  elseif commands[cmd] then
    commands[cmd](rest)
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end

SLASH_SUMMONCIRCLE1 = "/sc"
SLASH_SUMMONCIRCLE2 = "/summoncircle"
SlashCmdList.SUMMONCIRCLE = ns.Safe(slash)
