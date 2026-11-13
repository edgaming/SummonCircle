local function hello(name, shards)
  FireEvent("CHAT_MSG_ADDON", "SUMMONCIRCLE", "1:1:1:" .. C_EncodingUtil.SerializeCBOR({ t = "HELLO", shards = shards or 10 }), "PARTY", name)
end
local function invites() local n = 0 for _, m in ipairs(SENT) do if m.kind == "INVITE" then n = n + 1 end end return n end
local function check(label, cond) print((cond and "PASS " or "FAIL ") .. label) end

-- 1) Questing: I lead a party with a friend. Addon must do nothing on its own.
GROUP = { { name = "Ash Lock", leader = true }, { name = "Quest Buddy" } }
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD", true, false)
FireEvent("GROUP_ROSTER_UPDATE")
RunTimers(3)
FireEvent("CHAT_MSG_WHISPER", "+", "Random Person")
FireEvent("CHAT_MSG_WHISPER", "inv", "Other Person")
RunTimers(3)
check("questing: session off after login", not ns:IsActive())
check("questing: party NOT converted to raid", RAID == false)
check("questing: nobody auto-invited", invites() == 0)
check("questing: no reply whispers", #SENT == 0)
check("questing: closed, no action button", ns:NextAction().label == nil)

-- 2) Leader ticks a summoner while off: still no raid.
table.insert(GROUP, { name = "Bram Lock" })
FireEvent("GROUP_ROSTER_UPDATE"); hello("Bram Lock"); RunTimers(2)
ns:SetSummoner("Bram Lock", true); RunTimers(3)
check("ticking a summoner while off does not convert", RAID == false)

-- 3) Start the session: converts (2 summoners need assist), intake works.
ns:StartSession(); RunTimers(2)
check("start: session on", ns:IsActive())
check("start: converted to raid", RAID == true)
check("start: banner asks to give Bram assist", (ns:NextAction().label or ""):find("assist") ~= nil)
FireEvent("CHAT_MSG_WHISPER", "inv", "Bob Smith"); RunTimers(2)
check("start: customer invited", invites() == 1)

-- 4) Stop: intake stops.
ns:StopSession(); RunTimers(1)
FireEvent("CHAT_MSG_WHISPER", "inv", "Late Customer"); RunTimers(1)
check("stop: session off", not ns:IsActive())
check("stop: no more invites", invites() == 1)

-- 5) Solo-led session with one customer stays a party.
RAID = false
GROUP = { { name = "Ash Lock", leader = true }, { name = "Bob Smith" } }
ns.S.summoners = { "Ash Lock" }
FireEvent("GROUP_ROSTER_UPDATE"); ns:StartSession(); RunTimers(3)
check("one summoner + 1 customer stays a party", RAID == false)
table.insert(GROUP, { name = "C Two" }); table.insert(GROUP, { name = "C Three" })
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(2)
check("party of 4 during a session converts", RAID == true)

-- 6) Leaving the group ends the session.
GROUP = {}; RAID = false
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(1)
check("left group: session off", not ns:IsActive())

-- 7) Joining someone else's summoning group starts off until their leader switches us on.
ns.S.active = true
GROUP = { { name = "Other Leader", leader = true }, { name = "Ash Lock" } }
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(1)
check("joined as non-leader: off", not ns:IsActive())
