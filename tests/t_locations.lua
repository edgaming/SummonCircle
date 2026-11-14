-- Places and the names people type for them.
Boot()
local Loc = ns.Locations

eq("six capitals", #Loc.All(), 6)
eq("get by id", Loc.Get("undercity").short, "UC")
eq("by zone", Loc.ByZone("Thunder Bluff").id, "thunderbluff")
eq("by zone: case", Loc.ByZone("orgrimmar").id, "orgrimmar")
eq("by zone: unknown", Loc.ByZone("The Barrens"), nil)
eq("current city", Loc.Current() and Loc.Current().id, "undercity")
ZONE = "Durotar"
eq("current: not a city", Loc.Current(), nil)
ZONE = "Undercity"

local function ids(list)
  local t = {}
  for _, e in ipairs(list) do t[#t + 1] = e.id end
  return table.concat(t, ",")
end
eq("horde", ids(Loc.ForFaction("Horde")), "orgrimmar,undercity,thunderbluff")
eq("alliance", ids(Loc.ForFaction("Alliance")), "stormwind,ironforge,darnassus")

eq("match: short", ids(Loc.Match("WTB summon to UC")), "undercity")
eq("match: punctuation", ids(Loc.Match("summon org??")), "orgrimmar")
eq("match: two words", ids(Loc.Match("anyone port to thunder bluff pls")), "thunderbluff")
eq("match: spaced spelling", ids(Loc.Match("summon under city")), "undercity")
eq("match: whole words only", ids(Loc.Match("my organ is swollen")), "")
eq("match: 'if' is ambiguous", ids(Loc.Match("what if i need a summon")), "")
eq("match: 'if' when allowed", ids(Loc.Match("summon IF", true)), "ironforge")
eq("match: ironforge always", ids(Loc.Match("summon ironforge")), "ironforge")
eq("match: several", ids(Loc.Match("SW or IF, whichever")), "stormwind")
eq("match: empty", ids(Loc.Match("")), "")
eq("match: nil", ids(Loc.Match(nil)), "")

local ok = pcall(Loc.Register, { id = "x" })
check("register: incomplete entry rejected", not ok)
