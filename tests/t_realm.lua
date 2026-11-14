GROUP = { { name = "Ash Lock", leader = true }, { name = "Bram Lock" } }
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle")
FireEvent("PLAYER_LOGIN")
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(2)
-- Bram's addon says hello, as the game would deliver it (with a realm suffix)
FireEvent("CHAT_MSG_ADDON", "SUMMONCIRCLE", "1:1:1:" .. C_EncodingUtil.SerializeCBOR({ t = "HELLO", shards = 12 }), "RAID", "Bram Lock-CAMWOWUS2Realm8PvP")
ns.Session.SetSummoner("Bram Lock", true)
RunTimers(3)
-- A customer whispers with a realm suffix
FireEvent("CHAT_MSG_WHISPER", "inv", "Bob Smith-CAMWOWUS2Realm8PvP")
RunTimers(3)
local bad = 0
for _, m in ipairs(SENT) do
  print("sent:", m.kind, tostring(m.target), m.text or "")
  if tostring(m.target):find("-", 1, true) then bad = bad + 1 end
end
for _, m in ipairs(ADDON_MSGS) do
  if m.target and tostring(m.target):find("-", 1, true) then bad = bad + 1 end
end
print("addon msgs:", #ADDON_MSGS, "| names with realm suffix:", bad)
print("summoners:", table.concat(ns.S.summoners, ", "))
for n, e in pairs(ns.S.queue) do print("queue:", n, e.status) end
print("me:", ns.Me(), "| assist given to Bram:", tostring(GROUP[2].assist))
