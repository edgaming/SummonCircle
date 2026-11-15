-- /sc demo: made-up data for trying the window alone. Nothing is sent.
PLAYER_CLASS = "MAGE"
ME_NAME = "Dana Mage"
Boot()
local UI = ns.UI
check("a mage has no tabs", not UI.HasTabs())
SlashCmdList.SUMMONCIRCLE("demo tabs")
check("demo tabs: tabs on any class", UI.HasTabs())
check("demo tabs: the tab bar shows", SummonCircleFrame.tabs[2]:IsShown())

ADDON_MSGS, SENT = {}, {}
SlashCmdList.SUMMONCIRCLE("demo circles")
eq("demo circles: three listed", #ns.Listings.Recruiting(), 3)
UI.ShowPage("find")
local page = UI.pages[1].frame
local shown = {}
for _, r in ipairs(page.rows) do if r:IsShown() then shown[#shown + 1] = r end end
eq("demo circles: three rows", #shown, 3)
check("demo circles: closest to full first", shown[1].top:GetText():find("Vex Shadow") == nil)
check("demo circles: the 1-summoner circle last", shown[3].top:GetText():find("Vex Shadow") ~= nil)
shown[1].btn:GetScript("OnClick")()
eq("demo circles: Ask to join turns into Asked", shown[1].btn:GetText(), "Asked")
eq("demo circles: no whisper sent", #SENT, 0)

-- Tabs: same size, one selected.
local t1, t2 = SummonCircleFrame.tabs[1], SummonCircleFrame.tabs[2]
check("tabs: Find a Circle selected", t2.selected and not t1.selected)
check("tabs: the selected one glows", t2.glow:IsShown() and not t1.glow:IsShown())
t1:GetScript("OnClick")()
check("tabs: back to My Circle", UI.page == "circle" and t1.selected and SummonCircleFrame.content:IsShown())

SlashCmdList.SUMMONCIRCLE("demo applicants")
local apps = ns.Recruit.Applicants()
eq("demo applicants: two", #apps, 2)
check("demo applicants: rows show", SummonCircleFrame.appRows[1]:IsShown() and SummonCircleFrame.appHeader:IsShown())
ns.Recruit.Invite(apps[1].name)
check("demo applicants: Invite marks them invited", apps[1].invited)
eq("demo applicants: no real invite", #SENT, 0)

SlashCmdList.SUMMONCIRCLE("demo clear")
eq("demo clear: circles gone", #ns.Listings.Recruiting(), 0)
eq("demo clear: applicants gone", #ns.Recruit.Applicants(), 0)
check("demo clear: tabs off again", not UI.HasTabs())
eq("nothing went over the network", #ADDON_MSGS, 0)
