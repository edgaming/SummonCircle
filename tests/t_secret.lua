-- Midnight "secret" values: hidden AFK status or shard counts must never
-- break the addon or a message.
GROUP = { { name = "Ash Lock", leader = true }, { name = "Bram Lock" } }
Boot()

AFK = SECRET
ADDON_MSGS, ERRORS = {}, {}
FireEvent("PLAYER_FLAGS_CHANGED", "player")
RunTimers(1)
eq("AFK hidden: no errors", #ERRORS, 0)
check("AFK hidden: the heartbeat still goes out", #ADDON_MSGS > 0)
eq("AFK hidden: counts as not AFK", ns.IsAFK("player"), false)
check("AFK hidden: rotation doesn't break", pcall(ns.Rotation.NextUp))
check("AFK hidden: listing still builds", pcall(ns.Listings.Build))
AFK = false

-- Shards hidden: keep the last count.
local real = ns.API.ItemCount
ns.API.ItemCount = function() return 7 end
eq("shards: normal", ns.GetShards(), 7)
ns.API.ItemCount = function() return SECRET end
eq("shards hidden: last known count", ns.GetShards(), 7)
ns.API.ItemCount = real

-- The encoder drops secrets anywhere in a message.
local data = ns.Protocol.Encode({ t = "TEST", a = SECRET, b = 2, nested = { c = SECRET, d = "x" } })
local msg = ns.Protocol.Decode(data)
check("encoder: message survives", msg ~= nil and msg.b == 2 and msg.nested.d == "x")
check("encoder: secrets dropped", msg ~= nil and msg.a == nil and msg.nested.c == nil)

-- Hidden zone names (e.g. in instances) don't break anything.
ZONE = SECRET
ERRORS = {}
check("zone hidden: no current city", ns.Locations.Current() == nil)
ns.Update()
RunTimers(1)
eq("zone hidden: no errors", #ERRORS, 0)
ZONE = "Undercity"
