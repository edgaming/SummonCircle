-- The minimap button and the game's addon menu.
Boot()
local b = SummonCircleMinimapButton
check("minimap: button exists", b ~= nil and b:IsShown())
local shown = SummonCircleFrame:IsShown()
b:GetScript("OnClick")()
check("minimap: click toggles the window", SummonCircleFrame:IsShown() ~= shown)
SummonCircle_OnCompartmentClick()
check("addon menu: click toggles it back", SummonCircleFrame:IsShown() == shown)
SummonCircle_OnCompartmentEnter(nil, UIParent)
check("addon menu: tooltip names the addon", TOOLTIP[1] == "Summon Circle")
check("tooltip: shows the shop status", TOOLTIP[2]:find("CLOSED") ~= nil)

-- Dragging: straight above the minimap's centre = 90 degrees.
b:GetScript("OnDragStart")(b)
b:GetScript("OnUpdate")(b)
b:GetScript("OnDragStop")(b)
eq("drag: angle saved", math.floor(ns.db.minimap.angle + 0.5), 90)

SlashCmdList.SUMMONCIRCLE("minimap")
check("/sc minimap hides it", not b:IsShown() and ns.db.minimap.hide)
SlashCmdList.SUMMONCIRCLE("minimap")
check("/sc minimap shows it again", b:IsShown() and not ns.db.minimap.hide)

-- "Looking for summoners" hint while the network starts vs when it failed.
ns.UI.ShowPage("circle")
ns.Update()
check("recruit hint: loading while the network starts", SummonCircleFrame.recruit.hint:GetText():find("loading network") ~= nil)
ns.Net.status = "failed"
ns.Update()
check("recruit hint: network off when it failed", SummonCircleFrame.recruit.hint:GetText():find("network off") ~= nil)
