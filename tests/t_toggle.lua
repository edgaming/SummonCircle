GROUP = { { name = "Ash Lock", leader = true }, { name = "Bram Lock" } }
LoadAddon(ADDON_DIR)
FireEvent("ADDON_LOADED", "SummonCircle"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD", true, false)
FireEvent("GROUP_ROSTER_UPDATE"); RunTimers(2)
local F = SummonCircleFrame
print("1:", F.statusText._text, "| button:", F.toggle._text)
F.toggle._scripts.OnClick(F.toggle); RunTimers(2)
print("2:", F.statusText._text, "| button:", F.toggle._text)
F.toggle._scripts.OnClick(F.toggle); RunTimers(2)
print("3:", F.statusText._text, "| button:", F.toggle._text)

-- Queue | Requests switch: the active label is underlined, clicking switches.
local sw = SummonCircleFrame.switch
check("switch: queue underlined by default", sw.segments.queue.underline:IsShown() and not sw.segments.requests.underline:IsShown())
sw.segments.requests:GetScript("OnClick")()
check("switch: clicking Requests switches", ns.UI.view == "requests" and sw.segments.requests.underline:IsShown() and not sw.segments.queue.underline:IsShown())
sw.segments.queue:GetScript("OnClick")()
check("switch: and back", ns.UI.view == "queue" and sw.segments.queue.underline:IsShown())
