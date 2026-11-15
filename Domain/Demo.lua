-- Summon Circle: /sc demo. Made-up data for trying the UI alone.
-- Nothing here is sent to anyone: fake circles, applicants, customers and
-- requests live only in your own window, and clicking their buttons doesn't
-- whisper, invite, trade or kick anyone.
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

-- One customer at every stage, so every row style shows.
local function queueEntries(me, now)
  return {
    { name = "Bob Smith", status = "PAID", caster = me, castAt = now - 300, arrivedAt = now - 200, paid = 3000, added = now - 600 },
    { name = "Cara Jones", status = "ARRIVED", caster = me, castAt = now - 90, arrivedAt = now - 40, added = now - 500 },
    { name = "Finn Moss", status = "ARRIVED", caster = "Bram Lock", castAt = now - 400, arrivedAt = now - 260, added = now - 480 },
    { name = "Hana Reed", status = "SUMMONING", caster = "Bram Lock", castAt = now - 20, added = now - 300 },
    { name = "Ivy Lane", status = "GROUP", added = now - 200 },
    { name = "Jon Pike", status = "GROUP", added = now - 120 },
    { name = "Kai Fern", status = "INVITED", added = now - 30 },
  }
end

-- Requests: a plain one, one with an offer and a long message, one another
-- summoner already whispered.
local function requestEntries(now)
  return {
    { from = "Gorak Stone", text = "WTB UC summon", at = now - 12 },
    { from = "Lia Moon", text = "LF port to undercity 20s, anyone around? been waiting a while here in the barrens",
      offer = 2000, at = now - 95 },
    { from = "Mog Tusk", text = "need summ uc pls", at = now - 150, claimedBy = "Bram Lock", claimedAt = now },
  }
end

function Demo.Queue()
  local me, now = ns.Me(), GetServerTime()
  for _, e in ipairs(queueEntries(me, now)) do
    e.demo = true
    ns.S.queue[e.name] = e
  end
  ns.UI.ShowView("queue")
  ns.Print("Added 7 made-up customers, one at every stage. Clear them with /sc demo clear.")
end

function Demo.Requests()
  local now = GetServerTime()
  for _, l in ipairs(requestEntries(now)) do
    l.channel, l.city, l.demo = "Trade - City", "undercity", true
    ns.Leads.list[l.from] = l
  end
  ns.Update()
  ns.Print("Added 3 made-up requests (see the Requests label). Clear them with /sc demo clear.")
end

function Demo.All()
  Demo.Circles()
  Demo.Applicants()
  Demo.Queue()
  Demo.Requests()
end

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
  for name, e in pairs(ns.S.queue) do
    if e.demo then ns.S.queue[name] = nil end
  end
  for name, l in pairs(ns.Leads.list) do
    if l.demo then ns.Leads.list[name] = nil end
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
  elseif sub == "queue" then Demo.Queue()
  elseif sub == "requests" then Demo.Requests()
  elseif sub == "all" then Demo.All()
  elseif sub == "clear" then Demo.Clear()
  else
    ns.Print("/sc demo tabs - show the tabs on any class")
    ns.Print("/sc demo circles - 3 made-up circles in Find a Circle")
    ns.Print("/sc demo applicants - 2 made-up applicants under Summoners (leader)")
    ns.Print("/sc demo queue - 7 made-up customers, one at every stage")
    ns.Print("/sc demo requests - 3 made-up summon requests from chat")
    ns.Print("/sc demo all - all of the above")
    ns.Print("/sc demo clear - remove all of it")
  end
end
