-- Summon Circle: every place a circle can summon to, with the names players
-- type for it. Ads, listings and the chat parser all read from here, so
-- "UC", "Undercity" and "under city" always mean the same place.
--
-- Pure data + lookups; the only game call is Current(), which reads the zone.
local ADDON, ns = ...
local Locations = ns:Module("Locations")

local byId, ordered = {}, {}

-- entry = { id, name, short, faction = "Horde"|"Alliance"|"Neutral", aliases = { ... } }
-- Aliases are lowercase; may be several words ("under city").
-- ambiguous = true marks aliases that are also common English words ("if"):
-- the chat parser only trusts them next to a summon word.
function Locations.Register(entry)
  assert(entry.id and entry.name and entry.short and entry.faction, "incomplete location")
  entry.aliases = entry.aliases or {}
  entry.ambiguous = entry.ambiguous or {}
  byId[entry.id] = entry
  ordered[#ordered + 1] = entry
  return entry
end

function Locations.Get(id)
  return byId[id]
end

function Locations.All()
  return ordered
end

-- The entry for a zone name as the game reports it (e.g. "Undercity").
function Locations.ByZone(zone)
  if not zone or ns.IsSecret(zone) then return nil end
  local z = zone:lower()
  for _, e in ipairs(ordered) do
    if e.name:lower() == z then return e end
  end
end

-- The city you're standing in, or nil.
function Locations.Current()
  return Locations.ByZone(ns.ZoneText())
end

-- Locations a faction can use (its own capitals plus neutral ones).
function Locations.ForFaction(faction)
  local out = {}
  for _, e in ipairs(ordered) do
    if e.faction == faction or e.faction == "Neutral" then out[#out + 1] = e end
  end
  return out
end

-- Lowercase, punctuation to spaces, single-spaced, padded so whole-word
-- matching is a plain substring search for " alias ".
local function normalize(text)
  local t = (" " .. text:lower():gsub("[^%w%s]", " ") .. " "):gsub("%s+", " ")
  return t
end
Locations.Normalize = normalize

-- Does this alias appear as a whole word (or phrase) in normalized text?
local function hasWord(norm, alias)
  return norm:find(" " .. alias .. " ", 1, true) ~= nil
end
Locations.HasWord = hasWord

-- Every location named in a chat message, as whole words. Ambiguous aliases
-- are only reported when `allowAmbiguous` is true.
function Locations.Match(text, allowAmbiguous)
  if type(text) ~= "string" or text == "" then return {} end
  local norm = normalize(text)
  local found = {}
  for _, e in ipairs(ordered) do
    for _, alias in ipairs(e.aliases) do
      local risky = false
      for _, a in ipairs(e.ambiguous) do if a == alias then risky = true end end
      if (allowAmbiguous or not risky) and hasWord(norm, alias) then
        found[#found + 1] = e
        break
      end
    end
  end
  return found
end

---------------------------------------------------------------------------
-- Starting entries: the six classic capitals. Add a city with one call.
---------------------------------------------------------------------------
Locations.Register { id = "orgrimmar", name = "Orgrimmar", short = "Org", faction = "Horde",
  aliases = { "org", "orgrimmar", "og" } }
Locations.Register { id = "undercity", name = "Undercity", short = "UC", faction = "Horde",
  aliases = { "uc", "undercity", "under city" } }
Locations.Register { id = "thunderbluff", name = "Thunder Bluff", short = "TB", faction = "Horde",
  aliases = { "tb", "thunder bluff", "thunderbluff" } }
Locations.Register { id = "stormwind", name = "Stormwind", short = "SW", faction = "Alliance",
  aliases = { "sw", "stormwind", "storm wind" } }
Locations.Register { id = "ironforge", name = "Ironforge", short = "IF", faction = "Alliance",
  aliases = { "if", "ironforge", "iron forge" }, ambiguous = { "if" } }
Locations.Register { id = "darnassus", name = "Darnassus", short = "Darn", faction = "Alliance",
  aliases = { "darn", "darnassus", "darna" } }
