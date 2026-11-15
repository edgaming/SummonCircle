-- Summon Circle: /sc demo. Made-up data for trying the UI alone.
-- Nothing here is sent to anyone: fake circles and applicants live only in
-- your own window, and clicking their buttons doesn't whisper or invite.
local ADDON, ns = ...
local Demo = ns:Module("Demo")

local DEMO_FOR = 600 -- seconds fake circles stay listed

local CIRCLES = {
  { leader = "Ash Lock", spot = "Undercity", short = "UC", price = 3000, queue = 4,
    shards = { { n = "Ash Lock", s = 240 }, { n = "Bram Lock", s = 20 } } },
  { leader = "Vex Shadow", spot = "Orgrimmar", short = "Org", price = 4000, queue = 0,
    shards = { { n = "Vex Shadow", s = 8 } } },
  { leader = "Moon Lock", spot = "Badlands", price = 2500, queue = 1,
    shards = { { n = "Moon Lock", s = 18 }, { n = "Sol Ember", s = 13 } } },
}

local APPLICANTS = {
  { name = "Rook Vale", zone = "Orgrimmar", shards = 14 },
  { name = "Nyx Thorn", zone = "Stranglethorn Vale", shards = 31 },
}

function Demo.Tabs()
  ns.UI.forceTabs = true
  ns.Update()
  ns.Print("Tabs are on for this character until /reload.")
end

function Demo.Circles()
  Demo.Tabs()
  local now = GetTime()
  for _, c in ipairs(CIRCLES) do
    ns.Listings.all[c.leader] = {
      t = "LISTING", leader = c.leader, contacts = { c.leader }, spot = c.spot, short = c.short,
      open = true, recruiting = true, summoners = #c.shards, wanted = 3, shards = c.shards,
      price = c.price, queue = c.queue, at = GetServerTime(),
      seen = now + DEMO_FOR - ns.Listings.EXPIRE, demo = true,
    }
  end
  ns.Update()
  ns.Print("Added 3 made-up circles. Open the Find a Circle tab. They go away in 10 minutes or with /sc demo clear.")
end

function Demo.Applicants()
  if not ns.Roster.IsLeader() then
    return ns.Print("Only the group leader sees applicants.")
  end
  ns.S.applicants = ns.S.applicants or {}
  local at = GetServerTime()
  for i, a in ipairs(APPLICANTS) do
    ns.S.applicants[a.name] = { name = a.name, zone = a.zone, shards = a.shards, at = at - i, demo = true }
  end
  ns.Update()
  ns.Print("Added 2 made-up applicants under Summoners. Clear them with /sc demo clear.")
end

function Demo.Clear()
  for leader, l in pairs(ns.Listings.all) do
    if l.demo then ns.Listings.all[leader] = nil end
  end
  for name, a in pairs(ns.S.applicants or {}) do
    if a.demo then ns.S.applicants[name] = nil end
  end
  ns.UI.forceTabs = false
  ns.Update()
  ns.Print("Demo data cleared.")
end

function Demo.Command(rest)
  local sub = (rest or ""):lower()
  if sub == "tabs" then Demo.Tabs()
  elseif sub == "circles" then Demo.Circles()
  elseif sub == "applicants" then Demo.Applicants()
  elseif sub == "clear" then Demo.Clear()
  else
    ns.Print("/sc demo tabs - show the tabs on any class")
    ns.Print("/sc demo circles - 3 made-up circles in Find a Circle")
    ns.Print("/sc demo applicants - 2 made-up applicants under Summoners (leader)")
    ns.Print("/sc demo clear - remove all of it")
  end
end
