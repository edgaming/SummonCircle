local function check(label, cond) print((cond and "PASS " or "FAIL ") .. label) end

-- I'm in a group but NOT the leader, and the leader doesn't run the addon.
GROUP = { { name = "Quest Buddy", leader = true, class = "PRIEST" }, { name = "Ash Lock" } }
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD", true, false)
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(2)
local F = SummonCircleFrame
check("non-leader: not treated as leader", not ns:IsLeader())
check("non-leader: no Open for business button", not F.toggle:IsShown())
check("non-leader: no summoner gear", not F.sumGear:IsShown())
check("non-leader: no Advertise button or ad gear", not F.adBtn:IsShown() and not F.adGear:IsShown())
ns:StartSession(); RunTimers(1)
check("non-leader: can't open the shop", not ns:IsActive())
ns:SetSummoner("Ash Lock", true)
check("non-leader: can't pick summoners", #ns.S.summoners == 0)
check("non-leader: told the leader needs the addon", (ns:NextAction().text or ""):find("needs Summon Circle") ~= nil)

-- Now I'm the leader: controls appear.
GROUP = { { name = "Ash Lock", leader = true }, { name = "Quest Buddy", class = "PRIEST" } }
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(2)
check("leader: Open for business button shown", F.toggle:IsShown())
check("leader: summoner gear shown", F.sumGear:IsShown())
ns:StartSession(); RunTimers(1)
check("leader: can open the shop", ns:IsActive())
