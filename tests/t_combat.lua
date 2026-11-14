local function check(label, cond) print((cond and "PASS " or "FAIL ") .. label) end
GROUP = {}
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD", true, false)
RunTimers(1)
local F, B = SummonCircleFrame, SummonCircleActionButton
check("action button is not inside the window", B ~= nil)
ns.UI.Toggle(true)
FireEvent("PLAYER_REGEN_DISABLED"); COMBAT = true
check("entering combat hides the action button", not B:IsShown())
ns.UI.Toggle(false)
check("window closes in combat", not F:IsShown())
ns.UI.Toggle(true)
check("window opens in combat", F:IsShown())
COMBAT = false; FireEvent("PLAYER_REGEN_ENABLED")
check("window still open after combat", F:IsShown())
